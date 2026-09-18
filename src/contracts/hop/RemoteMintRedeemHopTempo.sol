// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { RemoteMintRedeemHop } from "./RemoteMintRedeemHop.sol";
import { TempoGasTokenBase } from "src/contracts/base/TempoGasTokenBase.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ===================== RemoteMintRedeemHopTempo =====================
// ====================================================================

/// @title RemoteMintRedeemHopTempo
/// @notice Tempo variant of `RemoteMintRedeemHop`. Tempo's LayerZero endpoint is an EndpointV2Alt,
///         which charges message fees in an ERC20 (`LZEndpointDollar`, 6 decimals) rather than in
///         native gas. The stock hop pays `IOFT.send{value: fee.nativeFee}` and refunds the caller's
///         `msg.value`, both of which revert on Tempo -- the OFT there opens with
///         `if (msg.value > 0) revert OFTAltCore__msg_value_not_zero(msg.value)`.
///
///         This override keeps the mint/redeem flow and the Fraxtal-side protocol identical, and only
///         changes how the fee is collected and paid: the caller is debited a TIP20 gas token, which is
///         swapped into a whitelisted stablecoin if needed, and the OFT consumes it through the
///         endpoint's alt-token path.
///
/// @dev Fee bookkeeping mirrors the native chains. The caller pays `quoteSend + quoteHop()`; the
///      `quoteSend` portion is consumed by the outbound message and the `quoteHop()` portion -- the
///      estimate for Fraxtal's return leg -- is retained on this contract, denominated in the collected
///      payment token instead of native. Sweep it with `recoverERC20`, not `recoverETH`.
///
/// @dev frxUSD on Tempo is minted under a TIP-403 blacklist policy. A return packet addressed to a
///      blacklisted recipient waits in the LayerZero payload store until they are unblocked; sfrxUSD
///      carries no policy, so a frxUSD-blacklisted caller can still start an sfrxUSD -> frxUSD
///      conversion whose delivery will wait the same way.
///
/// @author Frax Finance: https://github.com/FraxFinance
contract RemoteMintRedeemHopTempo is RemoteMintRedeemHop, TempoGasTokenBase {
    event FeeCollected(address indexed paymentToken, uint256 sendFee, uint256 retained);
    event RecoveredERC20(address indexed token, address indexed recipient, uint256 amount);

    error InvalidFeeToken();
    error NotImplemented();

    constructor(
        address _owner,
        bytes32 _fraxtalHop,
        uint256 _numDVNs,
        address _EXECUTOR,
        address _DVN,
        address _TREASURY,
        uint32 _EID,
        address _frxUsdOft,
        address _sfrxUsdOft,
        address _endpoint
    )
        RemoteMintRedeemHop(_owner, _fraxtalHop, _numDVNs, _EXECUTOR, _DVN, _TREASURY, _EID, _frxUsdOft, _sfrxUsdOft)
        TempoGasTokenBase(_endpoint)
    {}

    function version() external pure virtual override returns (string memory) {
        return "1.0.1-tempo";
    }

    /// @notice Set the slippage allowance applied to a DEX-routed fee swap, in basis points.
    /// @param _bps Allowance in bps, capped by MAX_FEE_SWAP_SLIPPAGE_BPS. 0 restores the default.
    function setFeeSwapSlippageBps(uint16 _bps) external onlyOwner {
        _setFeeSwapSlippageBps(_bps);
    }

    /// @notice Sweep a token held here -- the retained return-leg fees (pathUSD / USDC.e / USDT0) or
    ///         anything stranded. Same signature as every other chain's hop, with the transfer checked.
    function recoverERC20(address tokenAddress, address recipient, uint256 tokenAmount) external override onlyOwner {
        SafeERC20.safeTransfer(IERC20(tokenAddress), recipient, tokenAmount);
        emit RecoveredERC20(tokenAddress, recipient, tokenAmount);
    }

    /// @dev Tempo has no native path into this contract (value-carrying calls fail at the EVM), so the
    ///      inherited sweep would only ever be a silent no-op. Say so instead.
    function recoverETH(address, uint256) external view override onlyOwner {
        revert NotImplemented();
    }

    /// @inheritdoc RemoteMintRedeemHop
    /// @dev Rejects native value -- on Tempo the fee is debited as a TIP20 inside
    ///      `_mintRedeemViaFraxtal`, so a caller sending gas here would simply strand it. The fee is
    ///      pulled in `feeTokenOf(msg.sender)` with no cap; see the four-argument overload for both.
    function mintRedeem(address _oft, uint256 _amountLD) external payable virtual override {
        if (msg.value > 0) revert OFTAltCore__msg_value_not_zero(msg.value);
        _mintRedeem(_oft, _amountLD, address(0), type(uint256).max);
    }

    /// @notice As `mintRedeem(oft, amount)`, but the caller names the TIP20 the fee is pulled in and
    ///         caps that debit -- the Tempo equivalent of the `msg.value` ceiling on native chains.
    /// @param _feeToken TIP20 to pay the fee in. Pulled 1:1 when LZ-whitelisted, otherwise swapped on
    ///        the DEX; `feeTokenOf(caller)` reproduces the two-argument behaviour.
    /// @param _maxFeeTokenAmount Reverts `FeeAboveCap` -- before anything is pulled -- if the fee in
    ///        `_feeToken`, as `quoteUserTokenFee(oft, caller, amount, feeToken)` reports it at execution,
    ///        exceeds this.
    function mintRedeem(
        address _oft,
        uint256 _amountLD,
        address _feeToken,
        uint256 _maxFeeTokenAmount
    ) external virtual {
        if (_feeToken == address(0)) revert InvalidFeeToken();
        _mintRedeem(_oft, _amountLD, _feeToken, _maxFeeTokenAmount);
    }

    /// @dev `_feeToken == address(0)` means `feeTokenOf(msg.sender)`, resolved only once the cheap guards pass.
    function _mintRedeem(address _oft, uint256 _amountLD, address _feeToken, uint256 _maxFeeTokenAmount) internal {
        if (paused) revert HopPaused();
        if (_oft != frxUsdOft && _oft != sfrxUsdOft) revert InvalidOFT();

        _amountLD = removeDust(_oft, _amountLD);
        if (_amountLD == 0) revert ZeroAmountSend();
        if (_feeToken == address(0)) _feeToken = _resolveUserToken();
        SafeERC20.safeTransferFrom(IERC20(IOFT(_oft).token()), msg.sender, address(this), _amountLD);
        _mintRedeemViaFraxtal(_oft, bytes32(uint256(uint160(msg.sender))), _amountLD, _feeToken, _maxFeeTokenAmount);

        emit MintRedeem(_oft, msg.sender, _amountLD);
    }

    /// @dev Parent hook; fee in `feeTokenOf(msg.sender)`, uncapped.
    function _mintRedeemViaFraxtal(address _oft, bytes32 _to, uint256 _amountLD) internal virtual override {
        _mintRedeemViaFraxtal(_oft, _to, _amountLD, _resolveUserToken(), type(uint256).max);
    }

    /// @dev Replaces the native-fee path: collects the full fee as one whitelisted TIP20, binds this
    ///      contract's fee token so the OFT's `_payNative` consumes that same token without a second
    ///      swap, then sends with zero value.
    function _mintRedeemViaFraxtal(
        address _oft,
        bytes32 _to,
        uint256 _amountLD,
        address _feeToken,
        uint256 _maxFeeTokenAmount
    ) internal virtual {
        SendParam memory sendParam = _generateSendParam({ _to: _to, _amountLD: _amountLD, _minAmountLD: _amountLD });
        MessagingFee memory fee = _quoteSendRebindingOnFailure(_oft, sendParam, _feeToken);

        // Collect the outbound fee and the retained return-leg estimate in one debit of the fee token,
        // so there is a single fee pull and no native refund to hand back.
        uint256 retained = quoteHop();
        address paymentToken = _collectNativeAltToken(fee.nativeFee + retained, _feeToken, _maxFeeTokenAmount);
        if (paymentToken != address(0)) {
            _bindFeeToken(paymentToken);
            emit FeeCollected(paymentToken, fee.nativeFee, retained);
        }
        _approveOftFee(_oft, paymentToken, _amountLD, fee.nativeFee);

        IOFT(_oft).send(sendParam, fee, address(this));
    }

    /// @dev The OFT's quote validates THIS contract's FeeManager binding, which is whatever the previous
    ///      call paid with. Normally that token is still LZ-whitelisted and the quote just works. If
    ///      LayerZero has since delisted it and the DEX has no route out of it, the quote reverts -- so
    ///      re-bind to the token this call pays with (as FraxOFTWalletUpgradeableTempo does up front) and
    ///      quote again. Free on the happy path; an inherited binding can never wedge the hop.
    function _quoteSendRebindingOnFailure(
        address _oft,
        SendParam memory _sendParam,
        address _feeToken
    ) internal returns (MessagingFee memory fee) {
        try IOFT(_oft).quoteSend(_sendParam, false) returns (MessagingFee memory _fee) {
            return _fee;
        } catch {
            _bindFeeToken(_feeToken);
            return IOFT(_oft).quoteSend(_sendParam, false);
        }
    }

    /// @notice Fee a caller must hold and approve in `_userToken` to bridge `_amountLD` (on top of
    ///         `_amountLD` itself when `_userToken` is the bridged token).
    /// @dev `quote()` reports the fee in endpoint-native (LZD) units; UIs need the figure in whichever
    ///      TIP20 the user actually pays with, which is what this converts to. Pass the token the call
    ///      will use: the `_feeToken` argument of the four-argument `mintRedeem`, or `feeTokenOf(caller)`
    ///      for the two-argument one. For a token that must be swapped the figure includes the fee-swap
    ///      slippage allowance; the part the swap does not consume is refunded in the same call, so the
    ///      net debit is at most this amount -- and it is the figure `_maxFeeTokenAmount` is checked against.
    function quoteUserTokenFee(
        address _oft,
        bytes32 _to,
        uint256 _amountLD,
        address _userToken
    ) external view returns (uint256) {
        return _quoteUserTokenFee(_userToken, quote(_oft, _to, _amountLD).nativeFee);
    }

    /// @dev Approves the OFT for the bridged amount -- only when it pulls with `transferFrom`; a mintable
    ///      OFT burns from the caller and would just be left holding a dead self-allowance -- and, when the
    ///      fee rides on a different token, for the fee as well. When both are the same TIP20 they must be
    ///      approved as a single combined allowance: two `approve` calls would overwrite one another and
    ///      under-fund the send.
    function _approveOftFee(address _oft, address _paymentToken, uint256 _amountLD, uint256 _nativeFee) internal {
        address oftToken = IOFT(_oft).token();
        uint256 oftTokenAllowance = IOFT(_oft).approvalRequired() ? _amountLD : 0;

        if (_nativeFee > 0) {
            if (_paymentToken == oftToken) {
                oftTokenAllowance += _nativeFee;
            } else {
                SafeERC20.forceApprove(IERC20(_paymentToken), _oft, _nativeFee);
            }
        }

        if (oftTokenAllowance > 0) SafeERC20.forceApprove(IERC20(oftToken), _oft, oftTokenAllowance);
    }
}

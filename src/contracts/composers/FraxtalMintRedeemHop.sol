// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IFraxtalERC4626MintRedeemer } from "./interfaces/IFraxtalERC4626MintRedeemer.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ====================== FraxtalLZCurveComposer ======================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract FraxtalMintRedeemHop is Ownable, IOAppComposer {
    IFraxtalERC4626MintRedeemer constant public fraxtalERC4626MintRedeemer = IFraxtalERC4626MintRedeemer(0xBFc4D34Db83553725eC6c768da71D2D9c1456B55);
    IOFT constant public frxUSDOAPP = IOFT(0x96A394058E2b84A89bac9667B19661Ed003cF5D4);
    IOFT constant public sfrxUSDOAPP = IOFT(0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361);
    address constant endpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    bool public paused = false;
    uint256 public gasConvertionRate = 2800E18;
    uint256 public maxAllowedFee = 10e18;

    error InvalidOApp();
    error HopPaused();
    error NotEndpoint();

    constructor(uint256 _gasConvertionRate) Ownable(msg.sender) {
        gasConvertionRate = _gasConvertionRate;
    }

    // Admin functions
    function setGasConvertionRate(uint256 _gasConvertionRate) external onlyOwner {
        gasConvertionRate = _gasConvertionRate;
    }

    function setMaxAllowedFee(uint256 _maxAllowedFee) external onlyOwner {
        maxAllowedFee = _maxAllowedFee;
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
    }

    function recoverETH(uint256 tokenAmount) external onlyOwner {
        payable(msg.sender).transfer(tokenAmount);
    }

    function pause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    // receive ETH
    receive() external payable {}

    /// @notice Handles incoming composed messages from LayerZero.
    /// @dev Decodes the message payload to perform a token swap.
    ///      This method expects the encoded compose message to contain the swap amount and recipient address.
    /// @dev source: https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
    /// @param _oApp The address of the originating OApp/Token.
    /// @param /*_guid*/ The globally unique identifier of the message
    /// @param _message The encoded message content in the format of the OFTComposeMsgCodec.
    /// @param /*Executor*/ Executor address
    /// @param /*Executor Data*/ Additional data for checking for a specific executor
    function lzCompose(
        address _oApp,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*Executor*/,
        bytes calldata /*Executor Data*/
    ) external payable override {
        if (msg.sender != endpoint) revert NotEndpoint();
        if (paused) revert HopPaused();

        // Extract the composed message from the delivered message using the MsgCodec
        (bytes32 recipient, uint32 _dstEid) = abi.decode(
            OFTComposeMsgCodec.composeMsg(_message),
            (bytes32, uint32)
        );
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);

        // Approve the redeemer contract
        IERC20(IOFT(_oApp).token()).approve(address(fraxtalERC4626MintRedeemer), amount);
        
        // Redeem frxUsd => sfrxUsd or vice versa
        IOFT newOApp;
        if (_oApp == address(frxUSDOAPP)) {
            newOApp = sfrxUSDOAPP;
            uint256 amountOut = fraxtalERC4626MintRedeemer.deposit(amount, address(this));
        } else if (_oApp == address(sfrxUSDOAPP)) {
            newOApp = frxUSDOAPP;
            uint256 amountOut = fraxtalERC4626MintRedeemer.redeem(amount, address(this), address(this));
        } else {
            revert InvalidOApp();
        }

        if (_dstEid == 30255) {
            // Skip send if the dstEid is Fraxtal
            // TODO: can recipient be incorrectly cast and cause a loss of funds?
            IERC20(newOApp.token()).transfer(address(uint160(uint256(recipient))), amount);
        } else {
            IERC20(newOApp.token()).approve(address(newOApp), amount);
            _send({
                _oApp: address(newOApp),
                _dstEid: _dstEid,
                _to: recipient,
                _amountLD: amount
            });
        }
    }

    function _send(
        address _oApp,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD
    ) internal {
        uint256 pps = fraxtalERC4626MintRedeemer.pricePerShare();
        uint256 maxFee = maxAllowedFee;
        if (_oApp == address(sfrxUSDOAPP)) maxFee = maxAllowedFee*1e18/pps;
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _amountLD - maxFee
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);
        uint256 gasFee = fee.nativeFee * gasConvertionRate/1e18;
        if (_oApp == address(sfrxUSDOAPP)) {
            gasFee = gasFee * 1e18 / pps;
        }

        // Subtract gas fee
        sendParam.amountLD = _amountLD - gasFee;

        // Send the oft
        IOFT(_oApp).send{ value: fee.nativeFee }(sendParam, fee, address(this));
    }

    function _generateSendParam(
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) internal pure returns (SendParam memory sendParam) {
        bytes memory options = OptionsBuilder.newOptions();
        sendParam.dstEid = _dstEid;
        sendParam.to = _to;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        sendParam.extraOptions = options;
    }
}

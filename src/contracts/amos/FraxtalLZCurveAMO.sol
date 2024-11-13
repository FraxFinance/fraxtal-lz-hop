// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { FraxtalConstants } from "src/contracts/FraxtalConstants.sol";
import { FraxtalL2 } from "src/contracts/chain-constants/FraxtalL2.sol";
import { ICurve } from "src/contracts/shared/ICurve.sol";
import { IFerry } from "src/contracts/shared/IFerry.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ========================= FraxtalLZCurveAMO ========================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract FraxtalLZCurveAMO is AccessControlUpgradeable, FraxtalConstants {
    using OptionsBuilder for bytes;

    bytes32 public constant EXCHANGE_ROLE = keccak256("EXCHANGE_ROLE");
    uint256 public constant ONE_HUNDRED_PCT = 10000;

    // keccak256(abi.encode(uint256(keccak256("frax.storage.LZCurveAmoStorage")) - 1));
    bytes32 private constant LZCurveAmoStorageLocation =
        0x34cfa87765bced8684ef975fad48f7c370ba6aca6fca817512efcf044977addf;
    struct LZCurveAmoStorage {
        address ethereumComposer;
        address ethereumLzSenderAmo;
        uint256 fraxPct;
        uint256 sFraxPct;
        uint256 sFrxEthPct;
        uint256 fxsPct;
        uint256 fpiPct;
    }
    function _getLZCurveAmoStorage() private pure returns (LZCurveAmoStorage storage $) {
        assembly {
            $.slot := LZCurveAmoStorageLocation
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(EXCHANGE_ROLE, _owner);
    }

    function setStorage(address _ethereumComposer, address _ethereumLzSenderAmo) external onlyRole(DEFAULT_ADMIN_ROLE) {
        LZCurveAmoStorage storage $ = _getLZCurveAmoStorage();
        $.ethereumComposer = _ethereumComposer;
        $.ethereumLzSenderAmo = _ethereumLzSenderAmo;
    }

    function exchange(
        address _oApp,
        bool _sell,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) external onlyRole(EXCHANGE_ROLE) {
        (address nToken, address curve) = _getRespectiveTokens(_oApp);

        uint256 amountOut;
        if (_sell) {
            // _sell oft for nToken
            IERC20(_oApp).approve(curve, _amountIn);
            amountOut = ICurve(curve).exchange({ i: int128(1), j: int128(0), _dx: _amountIn, _min_dy: _amountOutMin });
        } else {
            // sell nToken for oft
            IERC20(nToken).approve(curve, _amountIn);
            amountOut = ICurve(curve).exchange({ i: int128(0), j: int128(1), _dx: _amountIn, _min_dy: _amountOutMin });
        }
    }

    function rebalanceReserves() external {
        _rebalanceReserves(FraxtalConstants.fraxOft);
        _rebalanceReserves(FraxtalConstants.sFraxOft);
        _rebalanceReserves(FraxtalConstants.sFrxEthOft);
        _rebalanceReserves(FraxtalConstants.fxsOft);
        _rebalanceReserves(FraxtalConstants.fpiOft);
    }

    function _rebalanceReserves(address _oApp) internal {
        LZCurveAmoStorage storage $ = _getLZCurveAmoStorage();

        (address nToken, ) = _getRespectiveTokens(_oApp);
        uint256 pct;
        if (nToken == FraxtalConstants.frax) {
            pct = $.fraxPct;
        } else if (nToken == FraxtalConstants.sFrax) {
            pct = $.sFraxPct;
        } else if (nToken == FraxtalConstants.sFrxEth) {
            pct = $.sFrxEthPct;
        } else if (nToken == FraxtalConstants.fxs) {
            pct = $.fxsPct;
        } else if (nToken == FraxtalConstants.fpi) {
            pct = $.fpiPct;
        }

        uint256 balanceNative = IERC20(nToken).balanceOf(address(this));
        uint256 balanceLz = IERC20(_oApp).balanceOf(address(this));
        bool excessNative = balanceNative > balanceLz;
        uint256 delta = excessNative ? balanceNative - balanceLz : balanceLz - balanceNative;
        uint256 deltaPct = (ONE_HUNDRED_PCT * delta) / (balanceNative + balanceLz);

        if (deltaPct > pct) {
            // divide the difference by 2 to get the amount needed to equally weight the tokens
            // For example, nToken/lzToken balance of 60/40 would have delta = 20, and require
            //  rebalancing 10 units back to 50/50
            uint256 amount = delta / 2;
            if (excessNative) {
                _sendViaFerry({ _oApp: _oApp, _amount: amount });
            } else {
                _sendViaLz({ _oApp: _oApp, _amount: amount });
            }
        }
    }

    function _sendViaLz(address _oApp, uint256 _amount) internal {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzComposeOption(0, 100_000, 0);
        bytes memory composeMsg = abi.encode(uint256(0));
        // Round down to avoid dust loss in send
        uint256 amountRounded = (_amount / 1e13) * 1e13;
        SendParam memory sendParam = SendParam({
            dstEid: uint32(30101), // Ethereum
            to: bytes32(uint256(uint160(ethereumComposer()))),
            amountLD: amountRounded,
            minAmountLD: amountRounded,
            extraOptions: options,
            composeMsg: composeMsg,
            oftCmd: ""
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);
        IOFT(_oApp).send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    }

    function _sendViaFerry(address _oApp, uint256 _amount) internal {
        (address nToken, ) = _getRespectiveTokens(_oApp);
        address ferry;
        if (nToken == FraxtalConstants.frax) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_FRAX;
        } else if (nToken == FraxtalConstants.sFrax) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_SFRAX;
        } else if (nToken == FraxtalConstants.sFrxEth) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_SFRXETH;
        } else if (nToken == FraxtalConstants.fxs) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_FXS;
        } else if (nToken == FraxtalConstants.fpi) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_FPI;
        }
        IFerry(ferry).embarkWithRecipient({ amount: _amount, recipient: ethereumLzSenderAmo() });
    }

    function setPcts(
        uint256 _fraxPct,
        uint256 _sFraxPct,
        uint256 _sFrxEthPct,
        uint256 _fxsPct,
        uint256 _fpiPct
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _fraxPct < ONE_HUNDRED_PCT &&
                _sFraxPct < ONE_HUNDRED_PCT &&
                _sFrxEthPct < ONE_HUNDRED_PCT &&
                _fxsPct < ONE_HUNDRED_PCT &&
                _fpiPct < ONE_HUNDRED_PCT,
            "Exceeds 100 pct"
        );
        LZCurveAmoStorage storage $ = _getLZCurveAmoStorage();
        $.fraxPct = _fraxPct;
        $.sFraxPct = _sFraxPct;
        $.sFrxEthPct = _sFrxEthPct;
        $.fxsPct = _fxsPct;
        $.fpiPct = _fpiPct;
    }

    function ethereumComposer() public view returns (address) {
        LZCurveAmoStorage storage $ = _getLZCurveAmoStorage();
        return $.ethereumComposer;
    }

    function ethereumLzSenderAmo() public view returns (address) {
        LZCurveAmoStorage storage $ = _getLZCurveAmoStorage();
        return $.ethereumLzSenderAmo;
    }
}

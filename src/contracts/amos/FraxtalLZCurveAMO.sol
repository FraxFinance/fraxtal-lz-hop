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
    bytes32 public constant SEND_ROLE = keccak256("SEND_ROLE");

    // keccak256(abi.encode(uint256(keccak256("frax.storage.LZCurveAmoStorage")) - 1));
    bytes32 private constant LZCurveAmoStorageLocation =
        0x34cfa87765bced8684ef975fad48f7c370ba6aca6fca817512efcf044977addf;
    struct LZCurveAmoStorage {
        address ethereumComposer;
        address ethereumLzSenderAmo;
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
        _grantRole(SEND_ROLE, _owner);
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

        // TODO: now what
    }

    function sendViaLz(address _oApp, uint256 _amount) external onlyRole(SEND_ROLE) {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzComposeOption(0, 100_000, 0);
        SendParam memory sendParam = SendParam({
            dstEid: uint32(30101), // Ethereum
            to: bytes32(uint256(uint160(ethereumComposer()))),
            amountLD: _amount,
            minAmountLD: 0,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);
        IOFT(_oApp).send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    }

    function sendViaFerry(address _oApp, uint256 _amount) external onlyRole(SEND_ROLE) {
        (address nToken, ) = _getRespectiveTokens(_oApp);
        address ferry;
        if (nToken == FraxtalL2.FRAX) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_FRAX;
        } else if (nToken == FraxtalL2.SFRAX) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_SFRAX;
        } else if (nToken == FraxtalL2.SFRXETH) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_SFRXETH;
        } else if (nToken == FraxtalL2.FXS) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_FXS;
        } else if (nToken == FraxtalL2.FPI) {
            ferry = FraxtalL2.FRAXFERRY_ETHEREUM_FPI;
        }
        IFerry(ferry).embarkWithRecipient({ amount: _amount, recipient: ethereumLzSenderAmo() });
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

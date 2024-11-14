// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";

import { FraxtalConstants } from "src/contracts/FraxtalConstants.sol";
import { IL1Bridge } from "src/contracts/shared/IL1Bridge.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ======================= EthereumLZCurveAMO ========================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract EthereumLZCurveAMO is OwnableUpgradeable, FraxtalConstants {
    using OptionsBuilder for bytes;

    error FailedEthTransfer();

    // keccak256(abi.encode(uint256(keccak256("frax.storage.EthereumLZCurveAMO")) - 1));
    bytes32 private constant EthereumLZCurveAmoStorageLocation =
        0x9457c09651b1abd0043ec778e295270b24c7b02014c9a6e064fec36091d1f6ce;

    struct EthereumLZCurveAmoStorage {
        address l1Bridge;
        address fraxtalLzCurveAmo;
        address fraxOft;
        address sFraxOft;
        address sFrxEthOft;
        address fxsOft;
        address fpiOft;
    }

    function _getEthereumLZCurveAmoStorage() private pure returns (EthereumLZCurveAmoStorage storage $) {
        assembly {
            $.slot := EthereumLZCurveAmoStorageLocation
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _l1Bridge,
        address _fraxtalLzCurveAmo,
        address _fraxOft,
        address _sFraxOft,
        address _sFrxEthOft,
        address _fxsOft,
        address _fpiOft
    ) external initializer {
        EthereumLZCurveAmoStorage storage $ = _getEthereumLZCurveAmoStorage();
        $.l1Bridge = _l1Bridge;
        $.fraxtalLzCurveAmo = _fraxtalLzCurveAmo;
        $.fraxOft = _fraxOft;
        $.sFraxOft = _sFraxOft;
        $.sFrxEthOft = _sFrxEthOft;
        $.fxsOft = _fxsOft;
        $.fpiOft = _fpiOft;

        _transferOwnership(_owner);
    }

    function _validateOft(address _oApp) internal view {
        EthereumLZCurveAmoStorage storage $ = _getEthereumLZCurveAmoStorage();
        require(
            _oApp == $.fraxOft ||
                _oApp == $.sFraxOft ||
                _oApp == $.sFrxEthOft ||
                _oApp == $.fxsOft ||
                _oApp == $.fpiOft,
            "Invalid OFT"
        );
    }

    function _getL2Token(address _oApp) internal view returns (address) {
        EthereumLZCurveAmoStorage storage $ = _getEthereumLZCurveAmoStorage();
        if (_oApp == $.fraxOft) {
            return FraxtalConstants.frax;
        } else if (_oApp == $.sFraxOft) {
            return FraxtalConstants.sFrax;
        } else if (_oApp == $.sFrxEthOft) {
            return FraxtalConstants.sFrxEth;
        } else if (_oApp == $.fxsOft) {
            return FraxtalConstants.fxs;
        } else {
            /// @dev assume _oApp is one of these tokens as _validateOft is called prior and would revert
            return FraxtalConstants.fpi;
        }
    }

    function sendViaLz(address _oApp, uint256 _amount) external {
        // reverts if invalid OFT
        _validateOft(_oApp);

        address token = IOFT(_oApp).token();

        // craft tx
        bytes memory options = OptionsBuilder.newOptions();
        // round amount to prevent dust lost
        uint256 amount = (_amount / 1e13) * 1e13;
        SendParam memory sendParam = SendParam({
            dstEid: uint32(30255), // fraxtal
            to: bytes32(uint256(uint160(fraxtalLzCurveAmo()))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);

        // approve and send
        IERC20(token).approve(_oApp, amount);
        IOFT(_oApp).send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    }

    function sendViaNativeBridge(address _oApp, uint256 _amount) external {
        // reverts if invalid OFT
        _validateOft(_oApp);

        address token = IOFT(_oApp).token();

        // approve and send
        EthereumLZCurveAmoStorage storage $ = _getEthereumLZCurveAmoStorage();
        IERC20(token).approve($.l1Bridge, _amount);
        IL1Bridge($.l1Bridge).depositERC20To({
            _l1Token: token,
            _l2Token: _getL2Token(_oApp),
            _to: $.fraxtalLzCurveAmo,
            _amount: _amount,
            _minGasLimit: uint32(200_000),
            _extraData: ""
        });
    }

    function rescueEth(address to, uint256 amount) external payable onlyOwner {
        (bool success, ) = to.call{ value: amount }("");
        if (!success) revert FailedEthTransfer();
    }

    function fraxtalLzCurveAmo() public view returns (address) {
        EthereumLZCurveAmoStorage storage $ = _getEthereumLZCurveAmoStorage();
        return $.fraxtalLzCurveAmo;
    }

    function l1Bridge() public view returns (address) {
        EthereumLZCurveAmoStorage storage $ = _getEthereumLZCurveAmoStorage();
        return $.l1Bridge;
    }
}

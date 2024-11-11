// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";

import { FraxtalConstants } from "src/contracts/FraxtalConstants.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ======================= EthereumLZSenderAMO ========================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract EthereumLZSenderAMO is OwnableUpgradeable, FraxtalConstants {
    using OptionsBuilder for bytes;

    error FailedEthTransfer();

    // keccak256(abi.encode(uint256(keccak256("frax.storage.EthereumLZSenderAMO")) - 1));
    bytes32 private constant EthereumLZSenderAmoStorageLocation =
        0xae71d745ae90af64f9f5e208d9e8dce64cca865b5246e2309de5b63cca6b882a;

    struct EthereumLZSenderAmoStorage {
        address fraxtalLzCurveAmo;
        address fraxOft;
        address sFraxOft;
        address sFrxEthOft;
        address fxsOft;
        address fpiOft;
    }

    function _getEthereumLZSenderAmoStorage() private pure returns (EthereumLZSenderAmoStorage storage $) {
        assembly {
            $.slot := EthereumLZSenderAmoStorageLocation
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _fraxtalLzCurveAmo,
        address _fraxOft,
        address _sFraxOft,
        address _sFrxEthOft,
        address _fxsOft,
        address _fpiOft
    ) external initializer {
        EthereumLZSenderAmoStorage storage $ = _getEthereumLZSenderAmoStorage();
        $.fraxtalLzCurveAmo = _fraxtalLzCurveAmo;
        $.fraxOft = _fraxOft;
        $.sFraxOft = _sFraxOft;
        $.sFrxEthOft = _sFrxEthOft;
        $.fxsOft = _fxsOft;
        $.fpiOft = _fpiOft;

        _transferOwnership(_owner);
    }

    function sendAllToFraxtal() external {
        EthereumLZSenderAmoStorage storage $ = _getEthereumLZSenderAmoStorage();

        sendToFraxtal($.fraxOft);
        sendToFraxtal($.sFraxOft);
        sendToFraxtal($.sFrxEthOft);
        sendToFraxtal($.fxsOft);
        sendToFraxtal($.fpiOft);
    }

    function sendToFraxtal(address _oApp) internal {
        address token = IOFT(_oApp).token();
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) return;

        // craft tx
        bytes memory options = OptionsBuilder.newOptions();
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

    function rescueEth(address to, uint256 amount) external payable onlyOwner {
        (bool success, ) = to.call{ value: amount }("");
        if (!success) revert FailedEthTransfer();
    }

    function fraxtalLzCurveAmo() public view returns (address) {
        EthereumLZSenderAmoStorage storage $ = _getEthereumLZSenderAmoStorage();
        return $.fraxtalLzCurveAmo;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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
// ==================== EthereumNativeBridgeComposer ==================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract EthereumNativeBridgeComposer is IOAppComposer, Initializable, FraxtalConstants {
    using OptionsBuilder for bytes;

    uint256 public counterA;
    uint256 public counterB;

    // keccak256(abi.encode(uint256(keccak256("frax.storage.EthereumNativeBridgeComposer")) - 1));
    bytes32 private constant EthereumNativeBridgeComposerStorageLocation =
        0x0bb7e48c2e948c6814cc15299d1ccfc0eafc6cbe8616be42cbb8c40105c27f52;

    struct EthereumNativeBridgeComposerStorage {
        address endpoint;
        address l1Bridge;
        address fraxtalLzCurveAmo;
    }

    function _getEthereumNativeBridgeComposerStorage()
        private
        pure
        returns (EthereumNativeBridgeComposerStorage storage $)
    {
        assembly {
            $.slot := EthereumNativeBridgeComposerStorageLocation
        }
    }

    constructor() {
        _disableInitializers();
        // approve bridge spending all six tokens
    }

    /// @dev Initializes the contract.
    function initialize(address _endpoint, address _l1Bridge, address _fraxtalLzCurveAmo) external initializer {
        EthereumNativeBridgeComposerStorage storage $ = _getEthereumNativeBridgeComposerStorage();
        $.endpoint = _endpoint;
        $.l1Bridge = _l1Bridge;
        $.fraxtalLzCurveAmo = _fraxtalLzCurveAmo;
    }

    /// @notice Handles incoming composed messages from LayerZero.
    /// @dev Decodes the message payload to perform a native bridge back to L2.
    ///      This method expects the encoded compose message to contain the recipient address as the AMO.
    /// @dev source: https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
    /// @param _oApp The address of the originating OApp.
    /// @param /*_guid*/ The globally unique identifier of the message (unused).
    /// @param _message The encoded message content in the format of the OFTComposeMsgCodec.
    /// @param /*Executor*/ Executor address (unused).
    /// @param /*Executor Data*/ Additional data for checking for a specific executor (unused).
    function lzCompose(
        address _oApp,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*Executor*/,
        bytes calldata /*Executor Data*/
    ) external payable override {
        EthereumNativeBridgeComposerStorage storage $ = _getEthereumNativeBridgeComposerStorage();
        require(msg.sender == $.endpoint, "!endpoint");

        address l1Token = IOFT(_oApp).token();
        (address l2Token, ) = _getRespectiveTokens(_oApp);
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);

        // approve and send
        IERC20(l1Token).approve($.l1Bridge, amount);
        try
            IL1Bridge($.l1Bridge).depositERC20To({
                _l1Token: l1Token,
                _l2Token: l2Token,
                _to: $.fraxtalLzCurveAmo,
                _amount: amount,
                _minGasLimit: uint32(200_000),
                _extraData: ""
            })
        {
            counterA += 1;
        } catch {
            IERC20(l1Token).approve($.l1Bridge, 0);
            counterB += 1;
        }
    }

    function endpoint() external view returns (address) {
        EthereumNativeBridgeComposerStorage storage $ = _getEthereumNativeBridgeComposerStorage();
        return $.endpoint;
    }

    function l1Bridge() external view returns (address) {
        EthereumNativeBridgeComposerStorage storage $ = _getEthereumNativeBridgeComposerStorage();
        return $.l1Bridge;
    }

    function fraxtalLzCurveAmo() public view returns (address) {
        EthereumNativeBridgeComposerStorage storage $ = _getEthereumNativeBridgeComposerStorage();
        return $.fraxtalLzCurveAmo;
    }
}

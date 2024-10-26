// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface ICurve {
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy, address _receiver) external;
}

// Simplified version of https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
contract MockReceiver is IOAppComposer {
    address public immutable endpoint;
    address public immutable oApp;

    address public nFraxlzFraxPool = 0x53f8F4e154F68C2D29a0D06BD50f82bCf1bd95dB;
    address public nFrax = 0xFc00000000000000000000000000000000000001;
    address public lzFrax = 0x80Eede496655FB9047dd39d9f418d5483ED600df;

    /// @dev Initializes the contract.
    /// @param _endpoint LayerZero Endpoint address
    /// @param _oApp The address of the OApp that is sending the composed message.
    constructor(address _endpoint, address _oApp) {
        endpoint = _endpoint;
        oApp = _oApp;
    }

    /// @notice Handles incoming composed messages from LayerZero.
    /// @dev Decodes the message payload to perform a token swap.
    ///      This method expects the encoded compose message to contain the swap amount and recipient address.
    /// @param _oApp The address of the originating OApp.
    /// @param /*_guid*/ The globally unique identifier of the message (unused in this mock).
    /// @param _message The encoded message content in the format of the OFTComposeMsgCodec.
    /// @param /*Executor*/ Executor address (unused in this mock).
    /// @param /*Executor Data*/ Additional data for checking for a specific executor (unused in this mock).
    function lzCompose(
        address _oApp,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*Executor*/,
        bytes calldata /*Executor Data*/
    ) external payable override {
        require(_oApp == oApp, "!oApp");
        require(msg.sender == endpoint, "!endpoint");
        // Extract the composed message from the delivered message using the MsgCodec
        (address recipient, uint256 amountOutMin) = abi.decode(OFTComposeMsgCodec.composeMsg(_message), (address, uint256));
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);
        IERC20(lzFrax).approve(nFraxlzFraxPool, amount);
        try ICurve(nFraxlzFraxPool).exchange({
            i: int128(1),
            j: int128(0),
            _dx: amount,
            _min_dy: amountOutMin,
            _receiver: recipient
        }) {} catch {
            // reset approval
            IERC20(lzFrax).approve(nFraxlzFraxPool, 0);
            IERC20(_oApp).transfer(recipient, amount);
        }
    }
}

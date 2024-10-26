// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { FraxtalL2 } from "src/contracts/chain-constants/FraxtalL2.sol";

interface ICurve {
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external;
}

interface IWETH {
    function withdraw(uint256 wad) external;
}

// Simplified version of https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
contract MockReceiver is IOAppComposer {
    error InvalidOApp();
    error FailedEthTransfer();

    address public immutable endpoint;

    address public lzFrax = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address public lzFraxCurve = 0x53f8F4e154F68C2D29a0D06BD50f82bCf1bd95dB;

    address public lzFrxEth = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
    address public lzFrxEthCurve = 0x50842664DfBD876249D0113671d72dB168FBE4d0;

    /// @dev Initializes the contract.
    /// @param _endpoint LayerZero Endpoint address
    constructor(address _endpoint) {
        endpoint = _endpoint;
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
        require(msg.sender == endpoint, "!endpoint");
        
        address nToken; // "native" token
        address lzToken; // "LayerZero" token
        address curve; // curve.fi pool
        if (_oApp == lzFrax) {
            nToken = FraxtalL2.FRAX;
            lzToken = lzFrax;
            curve = lzFraxCurve;
        } else if (_oApp == lzfrxEth) {
            nToken = FraxtalL2.WFRXETH;
            lzToken = lzFrxEth;
            curve = lzFrxEthCurve;
        } else {
            revert InvalidOApp();
        }
        
        // Extract the composed message from the delivered message using the MsgCodec
        (address recipient, uint256 amountOutMin) = abi.decode(OFTComposeMsgCodec.composeMsg(_message), (address, uint256));
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);
        
        IERC20(lzToken).approve(curve, amount);
        try ICurve(curve).exchange({
            i: int128(1),
            j: int128(0),
            _dx: amount,
            _min_dy: amountOutMin
        }) returns (uint256 amountOut) {
            if (nToken == FraxtalL2.WFRXETH) {
                // unwrap then send
                IWETH(nToken).withdraw(amountOut);
                (bool success,) = recipient.call{value: amountOut}(new bytes(0));
                if (!success) revert FailedEthTransfer();
            } else {
                // simple send the now-native token
                IERC20(nToken).transfer(recipient, amountOut);
            }
        } catch {
            // reset approval - swap failed
            IERC20(lzFrax).approve(lzFraxPool, 0);
            IERC20(_oApp).transfer(recipient, amount);
        }
    }
}

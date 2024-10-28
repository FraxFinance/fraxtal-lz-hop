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
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256);
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

    address public lzSFrax = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address public lzSFraxCurve = 0xd2866eF5A94E741Ec8EDE5FF8e3A1f9C59c5e298;

    address public lzFrxEth = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
    address public lzFrxEthCurve = 0x50842664DfBD876249D0113671d72dB168FBE4d0;

    address public lzSFrxEth = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address public lzSFrxEthCurve = 0xe5F61df936d50302962d5B914537Ff3cB63b3526;

    address public lzFxs = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
    address public lzFxsCurve = 0xBc383485068Ffd275D7262Bef65005eE7a5A1870;

    address public lzFpi = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    address public lzFpiCurve = 0x7FaA69f8fEbe38bBfFbAE3252DE7D1491F0c6157;

    /// @dev Initializes the contract.
    /// @param _endpoint LayerZero Endpoint address
    constructor(address _endpoint) {
        endpoint = _endpoint;
    }

    receive() external payable {}

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
        else if (_oApp == lzSFrax) {
            nToken = FraxtalL2.SFRAX;
            lzToken = lzSFrax;
            curve = lzSFraxCurve;
        } else if (_oApp == lzFrxEth) {
            nToken = FraxtalL2.WFRXETH;
            lzToken = lzFrxEth;
            curve = lzFrxEthCurve;
        } else if (_oApp == lzSFrxEth) {
            nToken = FraxtalL2.SFRXETH;
            lzToken = lzSFrxEth;
            curve = lzSFrxEthCurve;
        } else if (_oApp == lzFxs) {
            nToken = FraxtalL2.FXS;
            lzToken = lzFxs;
            curve = lzFxsCurve;
        } else if (_oApp == lzFpi) {
            nToken = FraxtalL2.FPI;
            lzToken = lzFpi;
            curve = lzFpiCurve;
        } else {
            revert InvalidOApp();
        }

        // Extract the composed message from the delivered message using the MsgCodec
        (address recipient, uint256 amountOutMin) = abi.decode(
            OFTComposeMsgCodec.composeMsg(_message),
            (address, uint256)
        );
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);

        IERC20(lzToken).approve(curve, amount);
        try ICurve(curve).exchange({ i: int128(1), j: int128(0), _dx: amount, _min_dy: amountOutMin }) returns (
            uint256 amountOut
        ) {
            if (nToken == FraxtalL2.WFRXETH) {
                // unwrap then send
                IWETH(nToken).withdraw(amountOut);
                (bool success, ) = recipient.call{ value: amountOut }("");
                if (!success) revert FailedEthTransfer();
            } else {
                // simple send the now-native token
                IERC20(nToken).transfer(recipient, amountOut);
            }
        } catch {
            // reset approval - swap failed
            IERC20(lzToken).approve(curve, 0);
            IERC20(lzToken).transfer(recipient, amount);
        }
    }
}

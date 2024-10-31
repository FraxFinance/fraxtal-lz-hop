// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { FraxtalL2 } from "src/contracts/chain-constants/FraxtalL2.sol";

interface ICurve {
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256);
}

interface IWETH {
    function withdraw(uint256 wad) external;
    function deposit() external payable;
}

// Simplified version of https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
contract MockReceiver is IOAppComposer {
    error InvalidOApp();
    error FailedEthTransfer();

    address public immutable endpoint;

    address public fraxOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address public fraxCurve = 0x53f8F4e154F68C2D29a0D06BD50f82bCf1bd95dB;

    address public sFraxOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address public sFraxCurve = 0xd2866eF5A94E741Ec8EDE5FF8e3A1f9C59c5e298;

    address public frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
    address public frxEthCurve = 0x50842664DfBD876249D0113671d72dB168FBE4d0;

    address public sFrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address public sFrxEthCurve = 0xe5F61df936d50302962d5B914537Ff3cB63b3526;

    address public fxsOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
    address public fxsCurve = 0xBc383485068Ffd275D7262Bef65005eE7a5A1870;

    address public fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    address public fpiCurve = 0x7FaA69f8fEbe38bBfFbAE3252DE7D1491F0c6157;

    /// @dev Initializes the contract.
    /// @param _endpoint LayerZero Endpoint address
    constructor(address _endpoint) {
        endpoint = _endpoint;
    }

    receive() external payable {}

    /// @dev Using the _oApp address (as provided by the endpoint), return the respective tokens
    /// @dev ie. a send of FRAX would have the _oApp address of the FRAX OFT
    /// @return nToken "Native token" (pre-compiled proxy address)
    /// @return curve (Address of curve.fi pool for nToken/lzToken)
    function _getRespectiveTokens(address _oApp) internal view returns (address nToken, address curve) {
        if (_oApp == fraxOft) {
            nToken = FraxtalL2.FRAX;
            curve = fraxCurve;
        } else if (_oApp == sFraxOft) {
            nToken = FraxtalL2.SFRAX;
            curve = sFraxCurve;
        } else if (_oApp == frxEthOft) {
            nToken = FraxtalL2.WFRXETH;
            curve = frxEthCurve;
        } else if (_oApp == sFrxEthOft) {
            nToken = FraxtalL2.SFRXETH;
            curve = sFrxEthCurve;
        } else if (_oApp == fxsOft) {
            nToken = FraxtalL2.FXS;
            curve = fxsCurve;
        } else if (_oApp == fpiOft) {
            nToken = FraxtalL2.FPI;
            curve = fpiCurve;
        } else {
            revert InvalidOApp();
        }
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

        (address nToken, address curve) = _getRespectiveTokens(_oApp);

        // Extract the composed message from the delivered message using the MsgCodec
        (address recipient, uint256 amountOutMin) = abi.decode(
            OFTComposeMsgCodec.composeMsg(_message),
            (address, uint256)
        );
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);

        // try swap
        IERC20(_oApp).approve(curve, amount);
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
            IERC20(_oApp).approve(curve, 0);

            // send non-converted OFT to recipient
            IERC20(_oApp).transfer(recipient, amount);
        }
    }

    /// @notice Quote the send cost of ETH required
    function quoteSendNativeFee(
        address _oApp,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) external view returns (uint256) {
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _minAmountLD
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);
        return fee.nativeFee;
    }

    /// @notice swap native token on curve and send OFT to another chain
    /// @param _oApp Address of the upgradeable OFT
    /// @param _dstEid Destination EID
    /// @param _to  Bytes32 representation of recipient ( ie. for EVM: bytes32(uint256(uint160(addr))) )
    /// @param _amount Amount of OFT to send
    /// @param _minAmountLD Minimum amount allowed to receive after LZ send (includes curve.fi swap slippage)
    function swapAndSend(
        address _oApp,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amount,
        uint256 _minAmountLD
    ) external payable {
        (address nToken, address curve) = _getRespectiveTokens(_oApp);

        // transfer from sender to here
        uint256 msgValue;
        if (nToken == FraxtalL2.WFRXETH) {
            // wrap amount to swap
            IWETH(nToken).deposit{ value: _amount }();
            // subtract amount wrapped from msg.value (remaining is to be paid through IOFT(_oApp.send()) )
            msgValue = msg.value - _amount;
        } else {
            // Simple token pull
            IERC20(nToken).transferFrom(msg.sender, address(this), _amount);
            msgValue = msg.value;
        }

        // Swap
        IERC20(nToken).approve(curve, _amount);
        /// @dev: can have amountOut as 0 as net slippage is checked via _minAmountLD in _send()
        uint256 amountOut = ICurve(curve).exchange({ i: int128(0), j: int128(1), _dx: _amount, _min_dy: 0 });

        // Send OFT to destination chain
        _send({
            _oApp: _oApp,
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: amountOut,
            _minAmountLD: _minAmountLD,
            _msgValue: msgValue
        });
    }

    function _send(
        address _oApp,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint256 _msgValue
    ) internal {
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _minAmountLD
        });
        MessagingFee memory fee = IOFT(_oApp).quoteSend(sendParam, false);
        require(_msgValue >= fee.nativeFee);

        // Send the oft
        IOFT(_oApp).send{ value: fee.nativeFee }(sendParam, fee, payable(msg.sender));

        // refund any extra sent ETH
        if (_msgValue > fee.nativeFee) {
            (bool success, ) = address(msg.sender).call{ value: _msgValue - fee.nativeFee }("");
            if (!success) revert FailedEthTransfer();
        }
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

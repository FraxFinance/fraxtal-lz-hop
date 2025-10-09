// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IHopComposer } from "./interfaces/IHopComposer.sol";
import { IHopV2, HopMessage } from "./interfaces/IHopV2.sol";

import { HopV2 } from "src/contracts/hop/HopV2.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== FraxtalHopV2 ===========================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract FraxtalHopV2 is HopV2, IOAppComposer, IHopV2 {
    event Hop(address oft, uint32 indexed srcEid, uint32 indexed dstEid, bytes32 indexed recipient, uint256 amount);
    event SendOFT(address oft, address indexed sender, uint32 indexed dstEid, bytes32 indexed to, uint256 amount);

    error ZeroAmountSend();
    error InvalidDestinationChain();

    constructor(address _executor, address[] memory _approvedOfts) HopV2(_executor, _approvedOfts) {}

    // receive ETH
    receive() external payable {}

    /// @notice Handles incoming composed messages from LayerZero.
    /// @dev Decodes the message payload to perform a token swap.
    ///      This method expects the encoded compose message to contain the swap amount and recipient address.
    /// @dev source: https://docs.layerzero.network/v2/developers/evm/protocol-gas-settings/options#lzcompose-option
    /// @param _oft The address of the originating OApp/Token.
    /// @param /*_guid*/ The globally unique identifier of the message
    /// @param _message The encoded message content in the format of the OFTComposeMsgCodec.
    /// @param /*Executor*/ Executor address
    /// @param /*Executor Data*/ Additional data for checking for a specific executor
    function lzCompose(
        address _oft,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*Executor*/,
        bytes calldata /*Executor Data*/
    ) external payable override {
        (bool isTrustedHopMessage, bool isDuplicateMessage) = _validateComposeMessage(_oft, _message);
        if (isDuplicateMessage) return;

        // Extract the composed message from the delivered message using the MsgCodec
        HopMessage memory hopMessage = abi.decode(OFTComposeMsgCodec.composeMsg(_message), (HopMessage));
        uint256 amountLD = OFTComposeMsgCodec.amountLD(_message);

        if (hopMessage.dstEid == localEid) {
            _sendLocal(_oft, amountLD, hopMessage);
        } else {
            _sendToDestination({
                _oft: _oft,
                _amountLD: removeDust(_oft, amountLD),
                _isTrustedHopMessage: isTrustedHopMessage,
                _hopMessage: hopMessage
            });
            emit Hop(_oft, OFTComposeMsgCodec.srcEid(_message), hopMessage.dstEid, hopMessage.recipient, amountLD);
        }
    }

    function _generateSendParam(
        uint256 _amountLD,
        HopMessage memory _hopMessage
    ) internal view override returns (SendParam memory sendParam) {
        sendParam.dstEid = _hopMessage.dstEid;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _amountLD;
        
        if (_hopMessage.data.length == 0) {
            sendParam.to = _hopMessage.recipient;
        } else {
            sendParam.to = remoteHop[_hopMessage.dstEid];

            bytes memory options = OptionsBuilder.newOptions();
            options = OptionsBuilder.addExecutorLzComposeOption(options, 0, _hopMessage.dstGas, 0);
            sendParam.extraOptions = options;

            sendParam.composeMsg = abi.encode(_hopMessage);
        }
    }

    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amount,
        uint128 _dstGas,
        bytes memory _data
    ) public view returns (uint256) {
        if (_dstEid == localEid) return 0;

        // generate hop message
        HopMessage memory hopMessage = HopMessage({
            srcEid: localEid,
            dstEid: _dstEid,
            dstGas: _dstGas,
            sender: bytes32(uint256(uint160(msg.sender))),
            recipient: _recipient,
            data: _data
        });

        SendParam memory sendParam = _generateSendParam({
            _hopMessage: hopMessage,
            _amountLD: removeDust(_oft, _amount)
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        return fee.nativeFee;
    }

    function quoteHop(uint32, uint128, bytes memory) public view override returns (uint256) {
        return 0;
    }

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable {
        sendOFT(_oft, _dstEid, _recipient, _amountLD, 0, "");
    }    

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD, uint128 _dstGas, bytes memory _data) public payable {
        if (paused) revert HopPaused();
        if (!approvedOft[_oft]) revert InvalidOFT();
        if (_dstEid != localEid && remoteHop[_dstEid] == bytes32(0)) revert InvalidDestinationChain();
        _amountLD = removeDust(_oft, _amountLD);

        // generate hop message
        HopMessage memory hopMessage = HopMessage({
            srcEid: localEid,
            dstEid: _dstEid,
            dstGas: _dstGas,
            sender: bytes32(uint256(uint160(msg.sender))),
            recipient: _recipient,
            data: _data
        });

        // Transfer the OFT token to the hop
        if (_amountLD > 0) SafeERC20.safeTransferFrom(IERC20(IOFT(_oft).token()), msg.sender, address(this), _amountLD);

        uint256 sendFee;
        if (_dstEid == localEid) {
            // Sending from fraxtal => fraxtal- no LZ send needed
            _sendLocal(_oft, _amountLD, hopMessage);
        } else {
            sendFee = _sendToDestination(_oft, _amountLD, true, hopMessage);
        }

        // Validate the msg.value
        _handleMsgValue(sendFee);

        emit SendOFT(_oft, msg.sender, _dstEid, _recipient, _amountLD);
    }

    // Owner functions
    function setMessageProcessed(address oft, uint32 srcEid, uint64 nonce, bytes32 composeFrom) external onlyOwner {
        bytes32 messageHash = keccak256(abi.encodePacked(oft, srcEid, nonce, composeFrom));
        emit MessageHash(oft, srcEid, nonce, composeFrom);
        messageProcessed[messageHash] = true;
    }    
}
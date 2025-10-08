// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { IOFT2 } from "./interfaces/IOFT2.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IHopComposer } from "./interfaces/IHopComposer.sol";
import { IHopV2, HopMessage } from "./interfaces/IHopV2.sol";

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
contract FraxtalHopV2 is Ownable2Step, IOAppComposer, IHopV2 {
    address public constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    uint32 constant FRAXTAL_EID = 30255;

    bool public paused = false;
    mapping(uint32 => bytes32) public remoteHop;
    mapping(bytes32 => bool) public messageProcessed;
    mapping(address => bool) public approvedOft;

    event Hop(address oft, uint32 indexed srcEid, uint32 indexed dstEid, bytes32 indexed recipient, uint256 amount);
    event MessageHash(address oft, uint32 indexed srcEid, uint64 indexed nonce, bytes32 indexed composeFrom);
    event SendOFT(address oft, address indexed sender, uint32 indexed dstEid, bytes32 indexed to, uint256 amount);

    error InvalidOFT();
    error HopPaused();
    error NotEndpoint();
    error InvalidSourceChain();
    error InvalidSourceHop();
    error ZeroAmountSend();
    error InvalidDestinationChain();
    error InsufficientFee();
    error RefundFailed();

    constructor(address[] memory _approvedOfts) Ownable(msg.sender) {
        for (uint256 i = 0; i < _approvedOfts.length; i++) {
            approvedOft[_approvedOfts[i]] = true;
        }
    }

    // Admin functions
    function recoverERC20(address tokenAddress, address recipient, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).transfer(recipient, tokenAmount);
    }

    function recoverETH(address recipient, uint256 tokenAmount) external onlyOwner {
        payable(recipient).call{ value: tokenAmount }("");
    }

    function setRemoteHop(uint32 _eid, address _remoteHop) external {
        setRemoteHop(_eid, bytes32(uint256(uint160(_remoteHop))));
    }

    function setRemoteHop(uint32 _eid, bytes32 _remoteHop) public onlyOwner {
        remoteHop[_eid] = _remoteHop;
    }

    function pause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function toggleOFTApproval(address oft, bool approved) external onlyOwner {
        approvedOft[oft] = approved;
    }

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
        if (msg.sender != ENDPOINT) revert NotEndpoint();
        if (paused) revert HopPaused();
        if (!approvedOft[_oft]) revert InvalidOFT();

        uint32 srcEid = OFTComposeMsgCodec.srcEid(_message);
        bytes32 composeFrom = OFTComposeMsgCodec.composeFrom(_message);
        bool isFromRemoteHop = remoteHop[srcEid] == composeFrom;
        {
            uint64 nonce = OFTComposeMsgCodec.nonce(_message);
            bytes32 messageHash = keccak256(abi.encode(_oft, srcEid, nonce, composeFrom));

            emit MessageHash(_oft, srcEid, nonce, composeFrom);
            // Avoid duplicated messages
            if (!messageProcessed[messageHash]) {
                messageProcessed[messageHash] = true;
            } else {
                return;
            }
        }

        // Extract the composed message from the delivered message using the MsgCodec
        HopMessage memory hopMessage = abi.decode(OFTComposeMsgCodec.composeMsg(_message), (HopMessage));
        uint256 amountLD = OFTComposeMsgCodec.amountLD(_message);

        if (hopMessage.dstEid == FRAXTAL_EID) {
            _sendLocal(_oft, hopMessage, amountLD);
        } else {
            _sendToDestination({
                _oft: _oft,
                _amountLD: amountLD,
                _hopMessage: hopMessage,
                _isFromRemoteHop: isFromRemoteHop
            });
            emit Hop(_oft, srcEid, hopMessage.dstEid, hopMessage.recipient, amountLD);
        }
    }
    
    function _sendLocal(address _oft, HopMessage memory _hopMessage, uint256 _amountLD) internal {
        // transfer the OFT token to the recipient
        address recipient = address(uint160(uint256(_hopMessage.recipient)));
        if (_amountLD > 0) SafeERC20.safeTransfer(IERC20(IOFT(_oft).token()), recipient, _amountLD);

        // Call the compose if there is data
        if (_hopMessage.data.length != 0) {
            IHopComposer(recipient).hopCompose({
                _srcEid: _hopMessage.srcEid,
                _sender: _hopMessage.sender,
                _oft: _oft,
                _amount: _amountLD,
                _data: _hopMessage.data
            });
        }
    }

    function _sendToDestination(
        address _oft,
        uint256 _amountLD,
        HopMessage memory _hopMessage,
        bool _isFromRemoteHop
    ) internal returns (uint256) {
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _hopMessage: _hopMessage,
            _amountLD: _amountLD,
            _minAmountLD: removeDust(_oft, _amountLD)
        });
        // Send the oft
        MessagingFee memory fee;
        if (!_isFromRemoteHop) {
            // Direct messages pay the full msg.value as fee
            fee.nativeFee = msg.value;
        } else {
            fee = IOFT(_oft).quoteSend(sendParam, false);
        }

        // send the tokens
        if (_amountLD > 0) SafeERC20.forceApprove(IERC20(IOFT(_oft).token()), _oft, _amountLD);
        IOFT(_oft).send{ value: fee.nativeFee }(sendParam, fee, address(this));

        return fee.nativeFee;
    }

    function _generateSendParam(
        HopMessage memory _hopMessage,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) internal view returns (SendParam memory sendParam) {
        sendParam.dstEid = _hopMessage.dstEid;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        
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
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) public view returns (uint256) {
        if (_dstEid == FRAXTAL_EID) return 0;
        uint256 _minAmountLD = removeDust(_oft, _amountLD);

        // generate hop message
        HopMessage memory hopMessage = HopMessage({
            srcEid: FRAXTAL_EID,
            dstEid: _dstEid,
            dstGas: _dstGas,
            sender: bytes32(uint256(uint160(msg.sender))),
            recipient: _recipient,
            data: _data
        });

        SendParam memory sendParam = _generateSendParam({
            _hopMessage: hopMessage,
            _amountLD: _amountLD,
            _minAmountLD: _minAmountLD
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        return fee.nativeFee;
    }   

    function removeDust(address oft, uint256 _amountLD) internal view returns (uint256) {
        uint256 decimalConversionRate = IOFT2(oft).decimalConversionRate();
        return (_amountLD / decimalConversionRate) * decimalConversionRate;
    }

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable {
        sendOFT(_oft, _dstEid, _recipient, _amountLD, 0, "");
    }    

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD, uint128 _dstGas, bytes memory _data) public payable {
        if (paused) revert HopPaused();
        if (!approvedOft[_oft]) revert InvalidOFT();
        if (_dstEid != FRAXTAL_EID && remoteHop[_dstEid] == bytes32(0)) revert InvalidDestinationChain();
        _amountLD = removeDust(_oft, _amountLD);

        // generate hop message
        HopMessage memory hopMessage = HopMessage({
            srcEid: FRAXTAL_EID,
            dstEid: _dstEid,
            dstGas: _dstGas,
            sender: bytes32(uint256(uint160(msg.sender))),
            recipient: _recipient,
            data: _data
        });

        // Transfer the OFT token to the hop
        if (_amountLD > 0) SafeERC20.safeTransferFrom(IERC20(IOFT(_oft).token()), msg.sender, address(this), _amountLD);

        uint256 sendFee;
        if (_dstEid == FRAXTAL_EID) {
            // Sending from fraxtal => fraxtal- no LZ send needed
            _sendLocal(_oft, hopMessage, _amountLD);
        } else {
            sendFee = _sendToDestination(_oft, _amountLD, hopMessage, false);
        }

        // Validate the msg.value
        _handleMsgValue(sendFee);

        emit SendOFT(_oft, msg.sender, _dstEid, _recipient, _amountLD);
    }

    function _handleMsgValue(uint256 _sendFee) internal {
        if (msg.value < _sendFee) {
            revert InsufficientFee();
        } else if (msg.value > _sendFee) {
            // refund redundant fee to sender
            (bool success, ) = payable(msg.sender).call{ value: msg.value - _sendFee }("");
            if (!success) revert RefundFailed();
        }
    }

    // Owner functions
    function setMessageProcessed(address oft, uint32 srcEid, uint64 nonce, bytes32 composeFrom) external onlyOwner {
        bytes32 messageHash = keccak256(abi.encodePacked(oft, srcEid, nonce, composeFrom));
        emit MessageHash(oft, srcEid, nonce, composeFrom);
        messageProcessed[messageHash] = true;
    }    
}
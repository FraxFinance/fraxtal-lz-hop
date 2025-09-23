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
contract FraxtalHopV2 is Ownable2Step, IOAppComposer {
    address public constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

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
        {
            bytes32 composeFrom = OFTComposeMsgCodec.composeFrom(_message);
            uint64 nonce = OFTComposeMsgCodec.nonce(_message);
            bytes32 messageHash = keccak256(abi.encode(_oft, srcEid, nonce, composeFrom));

            emit MessageHash(_oft, srcEid, nonce, composeFrom);
            // Avoid duplicated messages
            if (!messageProcessed[messageHash]) {
                messageProcessed[messageHash] = true;
            } else {
                return;
            }
            if (remoteHop[srcEid] == bytes32(0)) revert InvalidSourceChain();
            if (remoteHop[srcEid] != composeFrom) revert InvalidSourceHop();
        }

        // Extract the composed message from the delivered message using the MsgCodec
        (bytes32 _recipient, uint32 _dstEid, uint128 _composeGas, bytes memory _composeMsg) = abi.decode(OFTComposeMsgCodec.composeMsg(_message), (bytes32, uint32, uint128, bytes));
        uint256 amount = OFTComposeMsgCodec.amountLD(_message);
        address __oft = _oft;
        if (_dstEid == 30255) {
            SafeERC20.safeTransfer(IERC20(IOFT(_oft).token()), address(uint160(uint256(_recipient))), amount);
            if (_composeMsg.length != 0) {
                // We call hopCompose to the recipient on the local chain
                (uint32 _srcEid, bytes32 _srcAddress, bytes memory _composeMsg2) = abi.decode(_composeMsg, (uint32, bytes32, bytes));
                IHopComposer(address(uint160(uint256(_recipient)))).hopCompose(_srcEid, _srcAddress, __oft, amount, _composeMsg2);
            }
        } else {
            SafeERC20.forceApprove(IERC20(IOFT(_oft).token()), _oft, amount);
            bytes memory _composeMsg2;
            bytes32 _to;
            if (_composeMsg.length > 0) {
                _composeMsg2 = abi.encode(_recipient,_composeMsg);
                _to = remoteHop[_dstEid];
            } else {
                _to = _recipient;
            }
            // We send the tokens to the remote hop
            _send({ _oft: address(__oft), _dstEid: _dstEid, _to: _to, _amountLD: amount, _composeGas: _composeGas, _composeMsg: _composeMsg2 });
        }
        emit Hop(__oft, srcEid, _dstEid, _recipient, amount);
    }

    function _send(address _oft, uint32 _dstEid, bytes32 _to, uint256 _amountLD, uint128 _composeGas, bytes memory _composeMsg) internal {
        // generate arguments
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: removeDust(_oft, _amountLD),
            _composeGas: _composeGas,
            _composeMsg: _composeMsg
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        // Send the oft
        IOFT(_oft).send{ value: fee.nativeFee }(sendParam, fee, address(this));
    }

    function _generateSendParam(
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint128 _composeGas,
        bytes memory _composeMsg
    ) internal pure returns (SendParam memory sendParam) {
        bytes memory options = OptionsBuilder.newOptions();
        sendParam.dstEid = _dstEid;
        sendParam.to = _to;
        sendParam.amountLD = _amountLD;
        sendParam.minAmountLD = _minAmountLD;
        if (_composeMsg.length > 0) {
            options = OptionsBuilder.addExecutorLzComposeOption(options, 0, _composeGas, 0);
            sendParam.composeMsg = _composeMsg;
            sendParam.extraOptions = options;
        }
    }


    function _quote(
        address oft,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint128 _composeGas,
        bytes memory _composeMsg
    ) internal view returns (MessagingFee memory fee) {
        uint256 _minAmountLD = removeDust(oft, _amountLD);
        SendParam memory sendParam = _generateSendParam({
            _dstEid: _dstEid,
            _to: _to,
            _amountLD: _amountLD,
            _minAmountLD: _minAmountLD,
            _composeGas: _composeGas,
            _composeMsg: _composeMsg
        });
        fee = IOFT(oft).quoteSend(sendParam, false);
    }

    function quote(
        address oft,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint128 _composeGas,
        bytes memory _composeMsg
    ) public view returns (MessagingFee memory fee) {
        bytes memory _composeMsg2;
        if (_composeMsg.length > 0) _composeMsg2 = abi.encode(_to,abi.encode(uint32(30255),msg.sender,_composeMsg));
        fee = _quote(oft, _dstEid, remoteHop[_dstEid], _amountLD, _composeGas, _composeMsg2);
    }    

    function removeDust(address oft, uint256 _amountLD) internal view returns (uint256) {
        uint256 decimalConversionRate = IOFT2(oft).decimalConversionRate();
        return (_amountLD / decimalConversionRate) * decimalConversionRate;
    }

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable {
        sendOFT(_oft, _dstEid, _recipient, _amountLD, 0, "");
    }    

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD, uint128 _composeGas, bytes memory _composeMsg) public payable {
        if (paused) revert HopPaused();
        if (!approvedOft[_oft]) revert InvalidOFT();
        if (remoteHop[_dstEid] == bytes32(0)) revert InvalidDestinationChain();
        _amountLD = removeDust(_oft, _amountLD);
        SafeERC20.safeTransferFrom(IERC20(IOFT(_oft).token()), msg.sender, address(this), _amountLD);
        SafeERC20.forceApprove(IERC20(IOFT(_oft).token()), _oft, _amountLD);
        if (_composeMsg.length == 0) { // No Hop compose, send directly to recipient
            MessagingFee memory fee = _quote(_oft, _dstEid, _recipient, _amountLD, 0, "");
            if (fee.nativeFee > msg.value) revert InsufficientFee();
            _send({ _oft: address(_oft), _dstEid: _dstEid, _to: _recipient, _amountLD: _amountLD, _composeGas: 0, _composeMsg: "" });
        } else {
            // We send the tokens to the remote hop with hop compose
            bytes memory _composeMsg2 = abi.encode(_recipient,abi.encode(uint32(30255),msg.sender,_composeMsg));
            MessagingFee memory fee = _quote(_oft, _dstEid, remoteHop[_dstEid], _amountLD, _composeGas, _composeMsg2);
            if (fee.nativeFee > msg.value) revert InsufficientFee();
            _send({ _oft: address(_oft), _dstEid: _dstEid, _to: remoteHop[_dstEid], _amountLD: _amountLD, _composeGas: _composeGas, _composeMsg: _composeMsg2 });
            emit SendOFT(_oft, msg.sender, _dstEid, _recipient, _amountLD);
        }
    }

    // Owner functions
    function setMessageProcessed(address oft, uint32 srcEid, uint64 nonce, bytes32 composeFrom) external onlyOwner {
        bytes32 messageHash = keccak256(abi.encodePacked(oft, srcEid, nonce, composeFrom));
        emit MessageHash(oft, srcEid, nonce, composeFrom);
        messageProcessed[messageHash] = true;
    }    
}
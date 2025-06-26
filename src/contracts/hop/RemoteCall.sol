// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== RemoteCall =============================
// ====================================================================

/// @author Frax Finance: https://github.com/FraxFinance
contract RemoteCall is Ownable2Step, IOAppComposer {
    address public constant ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address public immutable OFT;

    bool public paused = false;
    mapping(uint32 => bytes32) public remoteAddress;
    mapping(bytes32 => bool) public messageProcessed;

    uint32 public callerEid = 1;
    bytes32 public callerAddress = bytes32(uint256(1));

    error InvalidOFT();
    error RemoteCallPaused();
    error NotEndpoint();
    error InvalidSourceChain();
    error InvalidSourceAddress();
    error CallFailed();
    error RefundFailed();
    error InsufficientFee();

    event MessageHash(address oft, uint32 indexed srcEid, uint64 indexed nonce, bytes32 indexed composeFrom);

    constructor(address _OFT) Ownable(msg.sender) {
        OFT = _OFT;
    }

    // receive gastoken
    receive() external payable {}

    // Owner functions
    function setMessageProcessed(address oft, uint32 srcEid, uint64 nonce, bytes32 composeFrom) external onlyOwner {
        bytes32 messageHash = keccak256(abi.encodePacked(oft, srcEid, nonce, composeFrom));
        emit MessageHash(oft, srcEid, nonce, composeFrom);
        messageProcessed[messageHash] = true;
    }

    function setRemoteAddress(uint32 _eid, address _remoteAddress) external {
        setRemoteAddress(_eid, bytes32(uint256(uint160(_remoteAddress))));
    }

    function setRemoteAddress(uint32 _eid, bytes32 _remoteAddress) public onlyOwner {
        remoteAddress[_eid] = _remoteAddress;
    }

    function pause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /// @notice Handles incoming composed messages from LayerZero.
    /// @dev Decodes the message payload to perform a call to a target address with the specified data and value.
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
        if (paused) revert RemoteCallPaused();
        if (_oft != OFT) revert InvalidOFT();

        uint32 srcEid = OFTComposeMsgCodec.srcEid(_message);
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
        if (remoteAddress[srcEid] == bytes32(0)) revert InvalidSourceChain();
        if (remoteAddress[srcEid] != composeFrom) revert InvalidSourceAddress();

        // Extract the composed message from the delivered message using the MsgCodec
        (address target, uint256 _value, bytes memory data) = abi.decode(
            OFTComposeMsgCodec.composeMsg(_message),
            (address, uint256, bytes)
        );

        // Set the caller context
        callerEid = srcEid;
        callerAddress = composeFrom;

        // Execute the target call
        (bool success, ) = target.call{ value: _value }(data);
        if (!success) revert CallFailed();

        // Reset the caller context
        callerEid = 1;
        callerAddress = bytes32(uint256(1));
    }

    function getCaller() external view returns (uint32, bytes32) {
        return (callerEid, callerAddress);
    }

    function remoteCall(
        uint32 _dstEid,
        address _target,
        uint128 _gas,
        uint128 _value,
        bytes calldata _data
    ) external payable {
        remoteCall({
            _dstEid: _dstEid,
            _target: bytes32(uint256(uint160(_target))),
            _gas: _gas,
            _value: _value,
            _data: _data
        });
    }

    function remoteCall(
        uint32 _dstEid,
        bytes32 _target,
        uint128 _gas,
        uint128 _value,
        bytes calldata _data
    ) public payable {
        if (paused) revert RemoteCallPaused();
        // generate arguments
        SendParam memory sendParam = generateSendParam({
            _dstEid: _dstEid,
            _target: _target,
            _gas: _gas,
            _value: _value,
            _data: _data
        });
        MessagingFee memory fee = IOFT(OFT).quoteSend(sendParam, false);
        if (fee.nativeFee > msg.value) revert InsufficientFee();

        // Send the oft (amountLD is 0 for remote calls)
        IOFT(OFT).send{ value: fee.nativeFee }(sendParam, fee, address(this));

        // Refund the excess
        if (msg.value > fee.nativeFee) {
            (bool success, ) = address(msg.sender).call{ value: msg.value - fee.nativeFee }("");
            if (!success) revert RefundFailed();
        }
    }

    function generateSendParam(
        uint32 _dstEid,
        bytes32 _target,
        uint128 _gas,
        uint128 _value,
        bytes calldata _data
    ) public view returns (SendParam memory sendParam) {
        bytes memory options = OptionsBuilder.newOptions();
        options = OptionsBuilder.addExecutorLzComposeOption(options, 0, _gas, _value);
        sendParam.dstEid = _dstEid;
        sendParam.to = remoteAddress[_dstEid];
        sendParam.amountLD = 0;
        sendParam.minAmountLD = 0;
        sendParam.extraOptions = options;
        sendParam.composeMsg = abi.encode(_target, _value, _data);
    }

    function quote(
        uint32 _dstEid,
        address _target,
        uint128 _gas,
        uint128 _value,
        bytes calldata _data
    ) public view returns (uint256 fee) {
        fee = quote({
            _dstEid: _dstEid,
            _target: bytes32(uint256(uint160(_target))),
            _gas: _gas,
            _value: _value,
            _data: _data
        });
    }

    function quote(
        uint32 _dstEid,
        bytes32 _target,
        uint128 _gas,
        uint128 _value,
        bytes calldata _data
    ) public view returns (uint256 fee) {
        SendParam memory sendParam = generateSendParam({
            _dstEid: _dstEid,
            _target: _target,
            _gas: _gas,
            _value: _value,
            _data: _data
        });
        fee = IOFT(OFT).quoteSend(sendParam, false).nativeFee;
    }
}

pragma solidity ^0.8.0;

import { IHopV2 } from "src/contracts/hop/interfaces/IHopV2.sol";
import { IHopComposer } from "src/contracts/hop/interfaces/IHopComposer.sol";

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

enum Direction {
    Outbound,
    Inbound
}

struct ReadMessage {
    Direction direction;
    ReadSharedMessage readSharedMessage;
    bytes message;
}

struct ReadSharedMessage {
    uint32 srcEid;
    uint32 targetEid;
    bytes32 srcAddress;
    bytes32 targetAddress;
    bytes32 dstAddress;
}

struct ReadHopMessage {
    uint32 dstEid;
    // uint128 targetGas; // does not need to be passed around
    uint128 dstGas;
    uint64 returnDataLen;
    bytes data;
}

struct ReadComposeMessage {
    bool success;
    uint64 readTimestamp;
    bytes data;
}

contract ReadHop is Ownable2Step, IHopComposer {

    address public immutable OFT;
    address public immutable HOP;
    uint32 public immutable EID;
    mapping(uint32 eid => bytes32 readHop) public readHops;

    error InvalidEID();
    error InvalidOFT();
    error NotReadHop();

    constructor(address _oft, address _hop, uint32 _eid) Ownable(msg.sender) {
        OFT = _oft;
        HOP = _hop;
        EID = _eid;
    }

    function readOFT(
        uint32 _targetEid,
        uint32 _dstEid,
        uint128 _targetGas,
        uint128 _dstGas,
        bytes32 _targetAddress,
        bytes32 _dstAddress,
        uint64 _returnDataLen,
        bytes memory _data
    ) external {
        if (readHops[_targetEid] == bytes32(0) || readHops[_dstEid] == bytes32(0)) revert InvalidEID();

        // Craft ReadMessage with ReadSharedMessage and ReadHopMessage
        ReadSharedMessage memory readSharedMessage = ReadSharedMessage({
            srcEid: EID,
            targetEid: _targetEid,
            srcAddress: bytes32(uint256(uint160(msg.sender))),
            targetAddress: _targetAddress,
            dstAddress: _dstAddress
        });
        ReadHopMessage memory readHopMessage = ReadHopMessage({
            dstEid: _dstEid,
            dstGas: _dstGas,
            returnDataLen: _returnDataLen,
            data: _data
        });

        ReadMessage memory readMessage = ReadMessage({
            direction: Direction.Outbound,
            readSharedMessage: readSharedMessage,
            message: abi.encode(readHopMessage)
        });

        // get quote of (src => target), (target => dst)

        // (src => target)
        uint256 fee = IHopV2(HOP).quote({
            _oft: OFT,
            _dstEid: _targetEid,
            _recipient: readHops[_targetEid],
            _amountLD: 0,
            _dstGas: _targetGas,
            _data: abi.encode(readMessage)
        });

        // (target => dst)
        // Craft mock ReadComposeMessage with returnDataLen (enforced on target ReadHop)
        bytes memory mockReturnData = new bytes(_returnDataLen);
        ReadComposeMessage memory mockReadComposeMessage = ReadComposeMessage({
            success: true,
            readTimestamp: type(uint64).max,
            data: mockReturnData
        });
        fee += IHopV2(HOP).quote({
            _oft: OFT,
            _dstEid: _dstEid,
            _recipient: readHops[_dstEid],
            _amountLD: 0,
            _dstGas: _dstGas,
            _data: abi.encode(
                ReadMessage({
                    direction: Direction.Inbound,
                    readSharedMessage: readSharedMessage,
                    message: abi.encode(mockReadComposeMessage)
                })
            )
        });

        // Send message
        IHopV2(HOP).sendOFT({
            _oft: OFT,
            _dstEid: _targetEid,
            _recipient: readHops[_targetEid],
            _amountLD: 0,
            _dstGas: _targetGas,
            _data: abi.encode(readMessage)
        });
    }

    function hopCompose(
        uint32 _srcEid,
        bytes32 _sender,
        address _oft,
        uint256 /* _amount */,
        bytes memory _data
    ) external {
        if (_oft != OFT) revert InvalidOFT();
        if (readHops[_srcEid] != _sender) revert NotReadHop();

        // TODO: decode into ReadHopMessage
        ReadMessage memory readMessage;

        if (uint8(readMessage.direction) == uint8(Direction.Outbound)) {
            _handleOutboundMessage(readMessage);
    } else if (uint8(readMessage.direction) == uint8(Direction.Inbound)) {
            _handleInboundMessage(readMessage);
        }
    }

    function _handleOutboundMessage(ReadMessage memory readMessage) internal {
        // decode into ReadHopMessage

        // call target with data

        // craft ReadComposeMessage

        // quote inbound sendOFT()

        // send message
    }

    function _handleInboundMessage(ReadMessage memory readMessage) internal {
        // decode into ReadComposeMessage

        // call dst with shared and compose message
    }

    function setReadHop(uint32 _eid, bytes32 _readHop) external onlyOwner {
        readHops[_eid] = _readHop;
    }
}
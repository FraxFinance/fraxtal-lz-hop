pragma solidity ^0.8.0;

import { IHopV2 } from "src/contracts/hop/interfaces/IHopV2.sol";
import { IHopComposer } from "src/contracts/hop/interfaces/IHopComposer.sol";
import { IReadComposer } from "src/contracts/hop/interfaces/IReadComposer.sol";

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { AddressConverter } from "src/contracts/hop/libs/AddressConverter.sol";

enum Direction {
    Outbound,
    Inbound
}

// TODO: is there a better convention around these ReadXMessage structs?

/// @dev Generic message passed from ReadHop to ReadHop where message is either an encoded
// ReadOutboundMessage or ReadInboundMessage
struct ReadMessage {
    Direction direction;
    uint32 srcEid;
    uint256 nonce;
    bytes32 srcAddress;
    bytes32 dstAddress;
    bytes message;
}

/// @dev Data to be used on the target chain
struct ReadOutboundMessage {
    uint32 dstEid;
    uint128 dstGas;
    uint64 returnDataLen;
    bytes32 targetAddress;
    bytes data;
}

/// @dev Data to be used on the destination chain
struct ReadInboundMessage {
    bool success;
    uint64 readTimestamp;
    bytes data;
}

contract ReadHop is AccessControlEnumerableUpgradeable, IHopComposer {
    using AddressConverter for address;
    using AddressConverter for bytes32;

    uint32 public constant FRAXTAL_EID = 30255;
    address public immutable self = address(this);

    struct ReadHopStorage {
        address oft;
        address hop;
        uint32 eid;
        mapping(uint32 eid => bytes32 readHop) readHops;
    }

    // keccak256(abi.encode(uint256(keccak256("frax.storage.ReadHop")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ReadHopStorageLocation =
        0x740984363260482c9834914734d02a6e1d7a3087c1a76dc9471ddd3aa894c900;

    function _getReadHopStorage() private pure returns (ReadHopStorage storage $) {
        assembly {
            $.slot := ReadHopStorageLocation
        }
    }

    error AccessDenied();
    error InsufficientFee();
    error InvalidEID();
    error InvalidOFT();
    error NotReadHop();
    error TooMuchDataReturned();
    error CannotSendToImplementation();
    error FailedRemoteSetCall();

    constructor() {
        _disableInitializers();
    }

    function initialize(address _oft, address _hop, uint32 _eid) external initializer {
        ReadHopStorage storage $ = _getReadHopStorage();
        $.oft = _oft;
        $.hop = _hop;
        $.eid = _eid;
        $.readHops[_eid] = address(this).toBytes32();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, address(this));
    }

    receive() external payable {
        // prevent sends to implementation, as the owner is set to address(0) and therefore unable to recover funds
        if (address(this) == self) revert CannotSendToImplementation();
    }

    function quoteReadOFT(
        uint32 _targetEid,
        uint32 _dstEid,
        uint128 _targetGas,
        uint128 _dstGas,
        uint256 _nonce,
        bytes32 _targetAddress,
        bytes32 _dstAddress,
        uint64 _returnDataLen,
        bytes memory _data
    ) external view returns (uint256 fee) {
        (fee, ) = _quoteReadOFT(
            _targetEid,
            _dstEid,
            _targetGas,
            _dstGas,
            _nonce,
            _targetAddress,
            _dstAddress,
            _returnDataLen,
            _data
        );
    }

    function _quoteReadOFT(
        uint32 _targetEid,
        uint32 _dstEid,
        uint128 _targetGas,
        uint128 _dstGas,
        uint256 _nonce,
        bytes32 _targetAddress,
        bytes32 _dstAddress,
        uint64 _returnDataLen,
        bytes memory _data
    ) internal view returns (uint256 fee, ReadMessage memory readMsg) {
        // Craft ReadMessage with ReadOutboundMessage
        ReadOutboundMessage memory readOutboundMsg = ReadOutboundMessage({
            dstEid: _dstEid,
            dstGas: _dstGas,
            returnDataLen: _returnDataLen,
            targetAddress: _targetAddress,
            data: _data
        });

        readMsg = ReadMessage({
            direction: Direction.Outbound,
            srcEid: eid(),
            nonce: _nonce,
            srcAddress: msg.sender.toBytes32(),
            dstAddress: _dstAddress,
            message: abi.encode(readOutboundMsg)
        });

        // get quote of (src => target), (target => dst)

        // (src => target)
        fee = IHopV2(hop()).quote({
            _oft: oft(),
            _dstEid: _targetEid,
            _recipient: readHops(_targetEid),
            _amountLD: 0,
            _dstGas: _targetGas,
            _data: abi.encode(readMsg)
        });

        // (target => dst)
        // Craft mock ReadInboundMessage with returnDataLen (enforced on target ReadHop)
        bytes memory mockReturnData = new bytes(_returnDataLen);
        ReadInboundMessage memory mockReadInboundMsg = ReadInboundMessage({
            success: true,
            readTimestamp: type(uint64).max,
            data: mockReturnData
        });
        fee += IHopV2(hop()).quote({
            _oft: oft(),
            _dstEid: _dstEid,
            _recipient: readHops(_dstEid),
            _amountLD: 0,
            _dstGas: _dstGas,
            _data: abi.encode(
                ReadMessage({
                    direction: Direction.Inbound,
                    srcEid: eid(),
                    nonce: _nonce,
                    srcAddress: msg.sender.toBytes32(),
                    dstAddress: _dstAddress,
                    message: abi.encode(mockReadInboundMsg)
                })
            )
        });
    }

    function readOFT(
        uint32 _targetEid,
        uint32 _dstEid,
        uint128 _targetGas,
        uint128 _dstGas,
        uint256 _nonce,
        bytes32 _targetAddress,
        bytes32 _dstAddress,
        uint64 _returnDataLen,
        bytes memory _data
    ) external payable {
        if (readHops(_targetEid) == bytes32(0)) revert InvalidEID();

        (uint256 fee, ReadMessage memory readMsg) = _quoteReadOFT(
            _targetEid,
            _dstEid,
            _targetGas,
            _dstGas,
            _nonce,
            _targetAddress,
            _dstAddress,
            _returnDataLen,
            _data
        );

        if (msg.value < fee) revert InsufficientFee();

        // Send message
        // Note that fees accrue in the ReadHop similar to RemoteHop.  User pays the target chain hopCompose() and destination chain readCompose()
        // in advance in the source chain token, and on the target and destination chain, there is an equivalent amount of gas available within
        // the ReadHop to execute the hopCompose()/readCompose()
        IHopV2(hop()).sendOFT{ value: fee }({
            _oft: oft(),
            _dstEid: _targetEid,
            _recipient: readHops(_targetEid),
            _amountLD: 0,
            _dstGas: _targetGas,
            _data: abi.encode(readMsg)
        });

        // refund excess fee
        if (msg.value > fee) {
            (bool success, ) = msg.sender.call{ value: msg.value - fee }("");
            require(success, "Refund failed");
        }
    }

    function hopCompose(
        uint32 _srcEid,
        bytes32 _sender,
        address _oft,
        uint256 /* _amount */,
        bytes memory _data
    ) external {
        if (_oft != oft()) revert InvalidOFT();

        // if sender is admin, call self (allows remote-setting of readHops)
        if (_srcEid == FRAXTAL_EID && hasRole(DEFAULT_ADMIN_ROLE, _sender.toAddress())) {
            if (msg.sender != hop()) revert AccessDenied();
            (bool success, ) = address(this).call(_data);
            if (!success) revert FailedRemoteSetCall();
            return;
        }

        if (readHops(_srcEid) != _sender) revert NotReadHop();

        // Decode into read message
        ReadMessage memory readMsg;
        (readMsg) = abi.decode(_data, (ReadMessage));

        if (uint8(readMsg.direction) == uint8(Direction.Outbound)) {
            _handleOutboundMessage(readMsg);
        } else if (uint8(readMsg.direction) == uint8(Direction.Inbound)) {
            _handleInboundMessage(readMsg);
        }
    }

    /// @dev Read the target contract and send the data to the destination
    function _handleOutboundMessage(ReadMessage memory readMsg) internal {
        // decode into ReadOutboundMessage
        ReadOutboundMessage memory readOutboundMsg;
        (readOutboundMsg) = abi.decode(readMsg.message, (ReadOutboundMessage));

        // call target with data
        (bool success, bytes memory data) = readOutboundMsg.targetAddress.toAddress().call(readOutboundMsg.data);

        // ensure data fits params
        if (data.length > readOutboundMsg.returnDataLen) revert TooMuchDataReturned();

        // craft ReadInboundMessage
        ReadInboundMessage memory readInboundMsg = ReadInboundMessage({
            success: success,
            readTimestamp: uint64(block.timestamp),
            data: data
        });

        // update ReadMessage
        readMsg.direction = Direction.Inbound;
        readMsg.message = abi.encode(readInboundMsg);

        // quote inbound sendOFT()
        uint256 fee = IHopV2(hop()).quote({
            _oft: oft(),
            _dstEid: readOutboundMsg.dstEid,
            _recipient: readHops(readOutboundMsg.dstEid),
            _amountLD: 0,
            _dstGas: readOutboundMsg.dstGas,
            _data: abi.encode(readMsg)
        });

        // send message
        IHopV2(hop()).sendOFT{ value: fee }({
            _oft: oft(),
            _dstEid: readOutboundMsg.dstEid,
            _recipient: readHops(readOutboundMsg.dstEid),
            _amountLD: 0,
            _dstGas: readOutboundMsg.dstGas,
            _data: abi.encode(readMsg)
        });
    }

    /// @dev push the read data to the recipient
    function _handleInboundMessage(ReadMessage memory readMsg) internal {
        ReadInboundMessage memory readInboundMsg;
        (readInboundMsg) = abi.decode(readMsg.message, (ReadInboundMessage));

        // call dst with shared and compose message
        IReadComposer(readMsg.dstAddress.toAddress()).readCompose({
            _srcEid: readMsg.srcEid,
            _srcAddress: readMsg.srcAddress,
            _nonce: readMsg.nonce,
            _readTimestamp: readInboundMsg.readTimestamp,
            _success: readInboundMsg.success,
            _data: readInboundMsg.data
        });
    }

    function setReadHop(uint32 _eid, bytes32 _readHop) public onlyRole(DEFAULT_ADMIN_ROLE) {
        ReadHopStorage storage $ = _getReadHopStorage();
        $.readHops[_eid] = _readHop;
    }

    function oft() public view returns (address) {
        ReadHopStorage storage $ = _getReadHopStorage();
        return $.oft;
    }

    function hop() public view returns (address) {
        ReadHopStorage storage $ = _getReadHopStorage();
        return $.hop;
    }

    function eid() public view returns (uint32) {
        ReadHopStorage storage $ = _getReadHopStorage();
        return $.eid;
    }

    function readHops(uint32 _eid) public view returns (bytes32) {
        ReadHopStorage storage $ = _getReadHopStorage();
        return $.readHops[_eid];
    }
}

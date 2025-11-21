pragma solidity ^0.8.0;

import { IHopV2 } from "src/contracts/hop/interfaces/IHopV2.sol";
import { IHopComposer } from "src/contracts/hop/interfaces/IHopComposer.sol";
import { IReadComposer } from "src/contracts/hop/interfaces/IReadComposer.sol";
import { IReadHop, ReadParam } from "src/contracts/hop/interfaces/IReadHop.sol";

import { AccessControlEnumerableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { AddressConverter } from "src/contracts/hop/libs/AddressConverter.sol";

enum Direction {
    Outbound,
    Inbound
}

/// @dev Generic message passed from ReadHop to ReadHop where message is either an encoded
// ReadOutboundMessage or ReadInboundMessage
struct ReadMessage {
    Direction direction;
    uint32 srcEid;
    uint256 nonce;
    bytes32 srcAddress;
    bytes32 targetAddress;
    bytes message;
}

/// @dev Data to be used on the target chain
struct ReadOutboundMessage {
    uint128 srcGas;
    uint64 returnDataLen;
    bytes data;
}

/// @dev Data to be used on the destination chain
struct ReadInboundMessage {
    bool success;
    uint64 readTimestamp;
    bytes data;
}

contract ReadHop is AccessControlEnumerableUpgradeable, IHopComposer, IReadHop {
    using AddressConverter for address;
    using AddressConverter for bytes32;

    uint32 public constant FRAXTAL_EID = 30255;
    address public immutable self = address(this);

    struct ReadHopStorage {
        address frxUsdOft;
        address hop;
        uint32 localEid;
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

    function initialize(address _frxUsdOft, address _hop, uint32 _localEid) external initializer {
        ReadHopStorage storage $ = _getReadHopStorage();
        $.frxUsdOft = _frxUsdOft;
        $.hop = _hop;
        $.localEid = _localEid;
        $.readHops[_localEid] = address(this).toBytes32();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    receive() external payable {
        // prevent sends to implementation, as the owner is set to address(0) and therefore unable to recover funds
        if (address(this) == self) revert CannotSendToImplementation();
    }

    function quoteReadOFT(ReadParam calldata _param) external view returns (uint256 fee) {
        (fee, ) = _quoteReadOFT(_param);
    }

    function _quoteReadOFT(ReadParam memory _param) internal view returns (uint256 fee, ReadMessage memory readMsg) {
        // Craft ReadMessage with ReadOutboundMessage
        ReadOutboundMessage memory readOutboundMsg = ReadOutboundMessage({
            srcGas: _param.srcGas,
            returnDataLen: _param.returnDataLen,
            data: _param.data
        });

        readMsg = ReadMessage({
            direction: Direction.Outbound,
            srcEid: localEid(),
            nonce: _param.nonce,
            srcAddress: msg.sender.toBytes32(),
            targetAddress: _param.targetAddress,
            message: abi.encode(readOutboundMsg)
        });

        // get cumulative cost of (src => target) + quote() + (target => dst)

        // (src => target)
        fee = IHopV2(hop()).quote({
            _oft: frxUsdOft(),
            _dstEid: _param.targetEid,
            _recipient: readHops(_param.targetEid),
            _amountLD: 0,
            _dstGas: _param.targetGas,
            _data: abi.encode(readMsg)
        });

        // quote() - called in ReadHop before sending consumes 250k gas as determined by `forge t --gas-report`
        // TODO: how to charge in destination gas price? ie. charge Ethereum gas price when sending to Ethereum
        fee += 250_000 * tx.gasprice;

        // (target => dst)
        // Craft mock ReadInboundMessage with returnDataLen (enforced on target ReadHop)
        bytes memory mockReturnData = new bytes(_param.returnDataLen);
        ReadInboundMessage memory mockReadInboundMsg = ReadInboundMessage({
            success: true,
            readTimestamp: type(uint64).max,
            data: mockReturnData
        });
        fee += IHopV2(hop()).quote({
            _oft: frxUsdOft(),
            _dstEid: localEid(),
            _recipient: address(this).toBytes32(),
            _amountLD: 0,
            _dstGas: _param.srcGas,
            _data: abi.encode(
                ReadMessage({
                    direction: Direction.Inbound,
                    srcEid: localEid(),
                    nonce: _param.nonce,
                    srcAddress: msg.sender.toBytes32(),
                    targetAddress: _param.targetAddress,
                    message: abi.encode(mockReadInboundMsg)
                })
            )
        });
    }

    function readOFT(ReadParam calldata _param) external payable {
        if (readHops(_param.targetEid) == bytes32(0)) revert InvalidEID();

        (uint256 fee, ReadMessage memory readMsg) = _quoteReadOFT(_param);

        if (msg.value < fee) revert InsufficientFee();

        // Send message
        // Note that fees accrue in the ReadHop similar to RemoteHop.  User pays the target chain hopCompose() and destination chain readCompose()
        // in advance in the source chain token, and on the target and destination chain, there is an equivalent amount of gas available within
        // the ReadHop to execute the hopCompose()/readCompose()
        IHopV2(hop()).sendOFT{ value: fee }({
            _oft: frxUsdOft(),
            _dstEid: _param.targetEid,
            _recipient: readHops(_param.targetEid),
            _amountLD: 0,
            _dstGas: _param.targetGas,
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
        if (_oft != frxUsdOft()) revert InvalidOFT();
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
        (bool success, bytes memory data) = readMsg.targetAddress.toAddress().staticcall(readOutboundMsg.data);

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
            _oft: frxUsdOft(),
            _dstEid: readMsg.srcEid,
            _recipient: readHops(readMsg.srcEid),
            _amountLD: 0,
            _dstGas: readOutboundMsg.srcGas,
            _data: abi.encode(readMsg)
        });

        // send message
        IHopV2(hop()).sendOFT{ value: fee }({
            _oft: frxUsdOft(),
            _dstEid: readMsg.srcEid,
            _recipient: readHops(readMsg.srcEid),
            _amountLD: 0,
            _dstGas: readOutboundMsg.srcGas,
            _data: abi.encode(readMsg)
        });
    }

    /// @dev push the read data to the recipient
    function _handleInboundMessage(ReadMessage memory readMsg) internal {
        ReadInboundMessage memory readInboundMsg;
        (readInboundMsg) = abi.decode(readMsg.message, (ReadInboundMessage));

        // call dst with shared and compose message
        IReadComposer(readMsg.srcAddress.toAddress()).readCompose({
            _targetAddress: readMsg.targetAddress,
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

    function frxUsdOft() public view returns (address) {
        ReadHopStorage storage $ = _getReadHopStorage();
        return $.frxUsdOft;
    }

    function hop() public view returns (address) {
        ReadHopStorage storage $ = _getReadHopStorage();
        return $.hop;
    }

    function localEid() public view returns (uint32) {
        ReadHopStorage storage $ = _getReadHopStorage();
        return $.localEid;
    }

    function readHops(uint32 _eid) public view returns (bytes32) {
        ReadHopStorage storage $ = _getReadHopStorage();
        return $.readHops[_eid];
    }
}

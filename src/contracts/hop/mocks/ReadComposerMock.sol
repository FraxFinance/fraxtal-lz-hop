pragma solidity ^0.8.0;

import { IReadComposer } from "src/contracts/hop/interfaces/IReadComposer.sol";

contract ReadComposerMock is IReadComposer {
    // decoded nonce fields
    bool public deposit;
    uint64 public amount;
    address public recipient;

    // readCompose params
    bytes32 public targetAddress;
    uint256 public nonce;
    uint64 public readTimestamp;
    bool public success;
    bytes public data;

    // stored variables

    function readCompose(
        bytes32 _targetAddress,
        uint256 _nonce,
        uint64 _readTimestamp,
        bool _success,
        bytes memory _data
    ) external override {
        targetAddress = _targetAddress;
        nonce = _nonce;
        readTimestamp = _readTimestamp;
        success = _success;
        data = _data;

        // decode nonce
        bytes memory nonceAsBytes = abi.encodePacked(_nonce);
        uint32 depositAsUint;
        uint64 amountCached;

        // https://github.com/GNSPS/solidity-bytes-utils/blob/fc502455bb2a7e26a743378df042612dd50d1eb9/contracts/BytesLib.sol#L334-L354
        assembly {
            amountCached := mload(add(add(nonceAsBytes, 0x8), 0))
            depositAsUint := mload(add(add(nonceAsBytes, 0x4), 0x8))
        }

        amount = amountCached;
        deposit = depositAsUint == 1;
        recipient = address(uint160(nonce));
    }
}

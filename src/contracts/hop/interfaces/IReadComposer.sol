pragma solidity ^0.8.0;

interface IReadComposer {
    function readCompose(
        bytes32 _targetAddress,
        uint256 _nonce,
        uint64 _readTimestamp,
        bool _success,
        bytes memory _data
    ) external;
}

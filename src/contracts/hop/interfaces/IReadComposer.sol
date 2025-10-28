pragma solidity ^0.8.0;

import { Direction, ReadMessage, ReadHopMessage, ReadComposeMessage } from "src/contracts/hop/ReadHop.sol";

interface IReadComposer {
    function readCompose(
        uint32 _srcEid,
        bytes32 _srcAddress,
        uint256 _nonce,
        uint64 _readTimestamp,
        bool _success,
        bytes memory _data
    ) external;
}
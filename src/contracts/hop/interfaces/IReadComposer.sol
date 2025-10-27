pragma solidity ^0.8.0;

import { Direction, ReadMessage, ReadHopMessage, ReadComposeMessage } from "src/contracts/hop/ReadHop.sol";

interface IReadComposer {
    function readCompose(uint256 _id, bool _success, uint64 _readTimestamp, bytes memory _data) external;
}
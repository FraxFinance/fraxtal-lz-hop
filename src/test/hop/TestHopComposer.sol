// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import { IHopComposer } from "src/contracts/hop/interfaces/IHopComposer.sol";

contract TestHopComposer is IHopComposer {
    event Composed(bool isTrustedHopMessage, uint32 srcEid, bytes32 srcAddress, address oft, uint256 amount, bytes composeMsg);

    function hopCompose(bool _isTrustedHopMessage, uint32 _srcEid, bytes32 _srcAddress, address _oft, uint256 _amount, bytes memory _data) external override {
        emit Composed(_isTrustedHopMessage, _srcEid, _srcAddress, _oft, _amount, _data);
    }
}
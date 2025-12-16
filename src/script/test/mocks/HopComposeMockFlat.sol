pragma solidity ^0.8.0;

// src/contracts/hop/interfaces/IHopComposer.sol

interface IHopComposer {
    function hopCompose(uint32 _srcEid, bytes32 _sender, address _oft, uint256 _amount, bytes memory _data) external;
}

// src/script/test/mocks/HopComposeMock.sol

contract HopComposeMock is IHopComposer {
    bytes public lastMessageData;
    event HopComposed(bytes data);

    function hopCompose(
        uint32 _srcEid,
        bytes32 _sender,
        address _oft,
        uint256 _amount,
        bytes memory _data
    ) external {
        lastMessageData = _data;
        emit HopComposed(_data);
    }

}


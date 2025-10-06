pragma solidity ^0.8.0;

struct HopMessage {
    uint32 srcEid;
    uint32 dstEid;
    uint128 dstGas;
    bytes32 sender;
    bytes32 recipient;
    bytes data;
}

interface IHopV2 {
    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable;

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD, uint128 _composeGas, bytes memory _composeMsg) external payable;

    function quote(
        address oft,
        uint32 _dstEid,
        bytes32 _to,
        uint256 _amountLD,
        uint128 _composeGas,
        bytes memory _composeMsg
    ) external view returns (uint256 fee);
}
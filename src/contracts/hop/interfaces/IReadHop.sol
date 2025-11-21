pragma solidity ^0.8.0;

/// @dev parameters to pass into readOFT()
struct ReadParam {
    uint32 returnDataLen;
    uint32 targetEid;
    uint128 targetGas;
    uint128 srcGas;
    uint256 nonce;
    bytes32 targetAddress;
    bytes data;
}

interface IReadHop {
    function readOFT(ReadParam memory _param) external payable;

    function quoteReadOFT(ReadParam memory _param) external view returns (uint256 fee);

    function setReadHop(uint32 _eid, bytes32 _readHop) external;
    function frxUsdOft() external view returns (address);
    function hop() external view returns (address);
    function localEid() external view returns (uint32);
    function readHops(uint32 _eid) external view returns (bytes32);
}

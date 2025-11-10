pragma solidity ^0.8.0;

interface IHopRead {
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
    ) external payable;

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
    ) external view returns (uint256 fee);

    function setReadHop(uint32 _eid, bytes32 _readHop) external;
    function oft() external view returns (address);
    function hop() external view returns (address);
    function eid() external view returns (uint32);
    function readHops(uint32 _eid) external view returns (bytes32);
}
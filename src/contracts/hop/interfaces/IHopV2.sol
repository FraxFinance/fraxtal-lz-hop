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
    // Mutable funcs

    function sendOFT(address _oft, uint32 _dstEid, bytes32 _recipient, uint256 _amountLD) external payable;

    function sendOFT(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external payable;

    // views

    function quote(
        address _oft,
        uint32 _dstEid,
        bytes32 _recipient,
        uint256 _amountLD,
        uint128 _dstGas,
        bytes memory _data
    ) external view returns (uint256 fee);

    function quoteHop(uint32 _dstEid, uint128 _dstGas, bytes memory _data) view external returns (uint256 fee);

    // Admin

    function pause(bool _paused) external;
    function setApprovedOft(address _oft, bool _isApproved) external;
    function setRemoteHop(uint32 _eid, address _remoteHop) external;
    function setRemoteHop(uint32 _eid, bytes32 _remoteHop) external;
    function recoverERC20(address tokenAddress, address recipient, uint256 tokenAmount) external;
    function setMessageProcessed(address _oft, uint32 _srcEid, uint64 _nonce, bytes32 _composeFrom) external;

    // Storage views
    function localEid() external view returns (uint32);
    function endpoint() external view returns (address);
    function paused() external view returns (bool);
    function approvedOft(address oft) external view returns (bool isApproved);
    function messageProcessed(bytes32 message) external view returns (bool isProcessed);
    function remoteHop(uint32 eid) external view returns (bytes32 hop);
}

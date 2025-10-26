pragma solidity ^0.8.0;

import { IHopV2 } from "src/contracts/hop/interfaces/IHopV2.sol";

interface IRemoteHopV2 is IHopV2 {
    // admin
    function setNumDVNs(uint32 _numDVNs) external;
    function setHopFee(uint256 _hopFee) external;
    function setExecutorOptions(uint32 eid, bytes memory _options) external;

    // State views
    function numDVNs() external view returns (uint32);
    function hopFee() external view returns (uint256);
    function executorOptions(uint32 eid) external view returns (bytes memory);
    function EXECUTOR() external view returns (address);
    function DVN() external view returns (address);
    function TREASURY() external view returns (address);
}
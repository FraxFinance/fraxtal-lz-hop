// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface IHopRegistry {
   function getRegistryEntry(uint32 eid, uint96 no, bytes32 key) external view returns (bytes memory);

   function hopV2() external view returns (address);
   function oft() external view returns (address);

}
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IHopApp } from "./IHopApp.sol";
import { IHopRegistry } from "./IHopRegistry.sol";
import { IHopV2 } from "../interfaces/IHopV2.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ============================ HopApp ================================
// ====================================================================

contract HopApp is IHopApp {
   IHopV2 public hopV2;
   IHopRegistry public registry;
   uint32 public appEid;
   uint96 public appNo;

   function initializeHopApp(address _registry, uint32 _appEid, uint96 _appNo) external override{
      registry = IHopRegistry(_registry);
      hopV2 = IHopV2(IHopRegistry(_registry).hopV2());
      appEid = _appEid;
      appNo = _appNo;
      require (remoteApp(appEid) != bytes32(0), "Invalid app deployment");
   }

   function remoteApp(uint32 _eid) internal view returns (bytes32 _remoteApp) {
      bytes32 key = keccak256(abi.encodePacked(_eid));
      (_remoteApp) = abi.decode(registry.getRegistryEntry(appEid, appNo, key),(bytes32));
   }

   function hopCompose(uint32 _srcEid, bytes32 _sender, address _oft, uint256, bytes memory _data) virtual external {
      require(msg.sender == address(hopV2), "Only HopV2 can call");
      require(remoteApp(_srcEid) == _sender, "Invalid sender");
   }
}
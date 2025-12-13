// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IHopApp } from "./IHopApp.sol";
import { IHopV2 } from "../interfaces/IHopV2.sol";
import { IHopRegistry } from "./IHopRegistry.sol";

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// =========================== HopDeploy ==============================
// ====================================================================

contract HopDeploy is Ownable {
   address public hopV2;
   address public registry;
   uint96 public hopDeployApp;
   uint32 public localEID;

   constructor(address admin) Ownable(admin) {
   }

   function initialize(address _registry, uint96 _hopDeployApp) external onlyOwner {
      registry = _registry;
      hopDeployApp = _hopDeployApp;
      hopV2 = IHopRegistry(_registry).hopV2();
      localEID = IHopV2(hopV2).localEid();
   }

   function deploy(uint32 _appEid, uint96 _appNo, bytes memory code) public {
      address addr;
      bytes32 salt = keccak256(abi.encodePacked(_appEid, _appNo));
      assembly {
         addr := create2(0, add(code, 0x20), mload(code), salt)
         if iszero(extcodesize(addr)) {
            revert(0, 0)
         }
      }
      require(addr != address(0), "Deployment failed");
      IHopApp(addr).initializeHopApp(registry, _appEid, _appNo);
      emit Deployed(addr);
   }

   function getRemoteHopReploy(uint32 eid) public view returns (bytes32) {
      bytes32 key = keccak256(abi.encodePacked(eid));
      return abi.decode(IHopRegistry(registry).getRegistryEntry(localEID, hopDeployApp, key),(bytes32));
   }

   function remoteDeploy(uint32 _remoteEid, uint32 _appEid, uint96 _appNo, bytes memory code, uint128 gas) external payable {
      IHopV2 hop = IHopV2(hopV2);
      hop.sendOFT{value: msg.value}(
         IHopRegistry(registry).oft(),
         _remoteEid,
         getRemoteHopReploy(_remoteEid),
         0,
         gas,
         abi.encode(_appEid, _appNo, code)
      );
      // Refund any excess gas
      if(payable(address(this)).balance > 0) {
         payable(msg.sender).transfer(payable(address(this)).balance);
      }
   }

   function hopCompose(uint32, bytes32, address, uint256, bytes memory _data) external {
      (uint32 _appEid, uint96 _appNo, bytes memory code) = abi.decode(_data, (uint32, uint96, bytes));
      deploy(_appEid, _appNo, code);
   } 

   event Deployed(address addr);
}

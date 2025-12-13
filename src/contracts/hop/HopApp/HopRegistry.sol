// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
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
// ========================= HopRegistry ==============================
// ====================================================================

contract HopRegistry is Ownable, IHopRegistry {
   bytes32 public constant OWNER_KEY = keccak256("HopRegistry:Owner");
   address public hopV2;
   uint32 public localEID;
   uint128 public constant BROADCASTGAS = 200000;
   address public oft;
   uint96 public registryCounter;
   mapping(uint32 => bytes32) public remoteRegistry;
   mapping(bytes32 => bytes) public registry;

   event RemoteRegistrySet(uint32 eid, bytes32 remoteRegistry);
   event RegistryCreated(uint96 no, address owner);
   event RegistryEntrySet(uint32 eid, uint96 no, bytes32 key);

   constructor(address admin) Ownable(admin) {
   }

   receive() external payable {}

   function initialize(address _hopV2, address _oft) external onlyOwner {
      hopV2 = _hopV2;
      localEID = IHopV2(hopV2).localEid();
      oft = _oft;
   }

   function setRemoteRegistry(uint32 eid, bytes32 _remoteRegistry) external onlyOwner {
      remoteRegistry[eid] = _remoteRegistry;
      emit RemoteRegistrySet(eid, _remoteRegistry);
   }

   function createRegistry() public returns (uint96 no) {
      no = registryCounter++;
      registry[_lookupKey(localEID, no, OWNER_KEY)] = abi.encode(msg.sender);
      emit RegistryCreated(no, msg.sender);
   }

   function registryOwner(uint96 no) public view returns (address) {
      bytes memory ownerData = getRegistryEntry(localEID, no, OWNER_KEY);
      return ownerData.length == 0 ? address(0) : abi.decode(ownerData, (address));
   }

   function setRegistryEntry(uint96 no, bytes32 key, bytes memory value) external {
      require(registryOwner(no) == msg.sender, "Not registry owner");
      registry[_lookupKey(localEID, no, key)] = value;
      emit RegistryEntrySet(localEID, no, key);
   }

   function _lookupKey(uint32 eid, uint96 no, bytes32 key) internal view returns (bytes32) {
      return keccak256(abi.encodePacked(eid, no, key));
   }

   function getRegistryEntry(uint32 eid, uint96 no, bytes32 key) public view returns (bytes memory) {
      return registry[_lookupKey(eid, no, key)];
   }

   function getRegistryEntry(uint32 eid, uint96 no, string memory key) public view returns (bytes memory) {
      return registry[_lookupKey(eid, no, keccak256(abi.encodePacked(key)))];
   }

   function broadcastRegistryEntry(uint96 no, bytes32 key, uint32 remoteEid) external payable {
      require(registryOwner(no) == msg.sender, "Not registry owner");
      bytes32 remoteReg = remoteRegistry[remoteEid];
      require(remoteReg != bytes32(0), "Remote registry not set");

      _sendRegistryEntry(no, key, remoteEid);

      // Refund any excess gas
      if(payable(address(this)).balance > 0) {
         payable(msg.sender).transfer(payable(address(this)).balance);
      }
   }

   function _sendRegistryEntry(uint96 no, bytes32 key, uint32 remoteEid) internal {
      bytes memory _data = abi.encode(no, key, getRegistryEntry(localEID, no, key));

      IHopV2(hopV2).sendOFT{value: payable(address(this)).balance}(
         oft,
         remoteEid,
         remoteRegistry[remoteEid],
         0,
         BROADCASTGAS,
         _data
      );
   }

   function hopCompose(uint32 _srcEid, bytes32 _sender, address _oft, uint256, bytes memory _data) external {
      require(msg.sender == hopV2, "Only HopV2 can call");
      require(remoteRegistry[_srcEid] == _sender, "Invalid sender");
      (uint96 no, bytes32 key, bytes memory value) = abi.decode(_data, (uint96, bytes32, bytes));
      registry[_lookupKey(_srcEid, no, key)] = value;
      emit RegistryEntrySet(_srcEid, no, key);
   }
}
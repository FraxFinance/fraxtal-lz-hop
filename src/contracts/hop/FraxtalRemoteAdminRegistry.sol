pragma solidity 0.8.23;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract FraxtalRemoteAdminRegistry is Ownable2Step {
    mapping (uint32 eid => address remoteAdmin) public remoteAdmins;

    constructor() Ownable(msg.sender) {}

    function setRemoteAdmin(uint32 _eid, address _remoteAdmin) external onlyOwner {
        remoteAdmins[_eid] = _remoteAdmin;
    }
}
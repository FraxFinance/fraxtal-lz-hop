pragma solidity ^0.8.0;

import { BaseScript } from "frax-std/BaseScript.sol";
import { HopComposeMock } from "src/script/test/mocks/HopComposeMock.sol";

// forge script src/script/test/DeployHopComposeMock.s.sol
contract DeployHopComposeMock is BaseScript {
    uint256 public configDeployerPK = vm.envUint("PK_CONFIG_DEPLOYER");

    function run() public {
        vm.startBroadcast(configDeployerPK);
        new HopComposeMock();
        vm.stopBroadcast();
    }
}
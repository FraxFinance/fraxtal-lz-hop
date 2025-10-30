pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { FraxUpgradeableProxy } from "frax-std/FraxUpgradeableProxy.sol";

import { HopSetter } from "src/contracts/hop/HopSetter.sol";

contract DeployHopSetter is BaseScript {
    function run() public broadcaster {
        address hopSetter = deployHopSetter(
            0x223a681fc5c5522c85C96157c0efA18cd6c5405c,
            address(2), // todo
            0x96A394058E2b84A89bac9667B19661Ed003cF5D4 // fraxtal frxUsd lockbox
        );
    }
}

function deployHopSetter(address _proxyAdmin, address _fraxtalHop, address _frxUsdOft) returns (address payable) {
    bytes memory initializeArgs = abi.encodeCall(HopSetter.initialize, (_fraxtalHop, _frxUsdOft));

    address implementation = address(new HopSetter());
    FraxUpgradeableProxy proxy = new FraxUpgradeableProxy(implementation, _proxyAdmin, initializeArgs);

    return payable(address(proxy));
}

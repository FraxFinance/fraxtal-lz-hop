pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { FraxUpgradeableProxy } from "frax-std/FraxUpgradeableProxy.sol";

import { HopSetter } from "src/contracts/hop/HopSetter.sol";

// forge script src/script/hop/HopSetter/DeployHopSetter.s.sol --rpc-url https://rpc.frax.com --broadcast --verify --verifier etherscan --etherscan-api-key $TODO
contract DeployHopSetter is BaseScript {
    function run() public broadcaster {
        address hopSetter = deployHopSetter(
            0x223a681fc5c5522c85C96157c0efA18cd6c5405c,
            0xC87D7e85aFCc8D51056D8B2dB95a89045BbE60DC,
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

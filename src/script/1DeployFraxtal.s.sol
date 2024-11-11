// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { FraxtalLZCurveComposer } from "../contracts/composers/FraxtalLZCurveComposer.sol";
import { FraxtalLZCurveAMO } from "../contracts/amos/FraxtalLZCurveAMO.sol";
import { FraxProxy } from "../contracts/FraxProxy.sol";

// Run this with source .env && forge script --broadcast --rpc-url $MAINNET_URL DeployFraxtalLZCurveComposer.s.sol
contract DeployFraxtalLZCurveComposer is BaseScript {
    address endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // fraxtal endpoint v2
    address multisig = address(0); // TODO

    function run() public broadcaster {
        // deploy FraxtalLzCurveComposer
        address implementation = address(new FraxtalLZCurveComposer());
        FraxProxy proxy = new FraxProxy(
            implementation,
            multisig,
            abi.encodeCall(FraxtalLZCurveComposer.initialize, (endpoint))
        );
        console.log("FraxtalLZCurveComposer @ ", address(proxy));

        // deploy FraxtalLZCurveAmo
        implementation = address(new FraxtalLZCurveAMO());
        proxy = new FraxProxy(implementation, multisig, abi.encodeCall(FraxtalLZCurveAMO.initialize, (deployer)));
        console.log("FraxtalLZCurveAMO @ ", address(proxy));
    }
}

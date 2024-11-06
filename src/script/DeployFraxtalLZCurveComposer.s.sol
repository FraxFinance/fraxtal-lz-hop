// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { FraxtalLZCurveComposer } from "../contracts/composers/FraxtalLZCurveComposer.sol";
import { FraxProxy } from "../contracts/FraxProxy.sol";

// Run this with source .env && forge script --broadcast --rpc-url $MAINNET_URL DeployFraxtalLZCurveComposer.s.sol
contract DeployFraxtalLZCurveComposer is BaseScript {
    address endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // fraxtal endpoint v2

    function run() public broadcaster {
        address implementation = address(new FraxtalLZCurveComposer());
        new FraxProxy(implementation, msg.sender, abi.encodeCall(FraxtalLZCurveComposer.initialize, (endpoint)));
    }
}

// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { RemoteCall } from "../contracts/hop/RemoteCall.sol";

// Run this with source .env && forge script --broadcast --rpc-url $MAINNET_URL DeployRemoteCall.s.sol
contract DeployRemoteCall is BaseScript {

    function run() public broadcaster {
        // deploy RemoteCall
        //RemoteCall remoteCall = new RemoteCall(0x96A394058E2b84A89bac9667B19661Ed003cF5D4); // Fraxtal
        RemoteCall remoteCall = new RemoteCall(0x80Eede496655FB9047dd39d9f418d5483ED600df); // Arbitrum
        console.log("remoteCall:", address(remoteCall));
    }
}
// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { MockReceiver } from "../contracts/MockReceiver.sol";

// Run this with source .env && forge script --broadcast --rpc-url $MAINNET_URL DeployCounter.s.sol
contract DeployMockReceiver is BaseScript {

    address endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // fraxtal endpoint v2
    address oApp = 0x80Eede496655FB9047dd39d9f418d5483ED600df; // fraxtal FRAX OFT

    function run() public broadcaster {
        new MockReceiver(endpoint, oApp);
    }
}

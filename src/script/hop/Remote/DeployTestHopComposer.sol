// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { TestHopComposer } from "src/test/hop/TestHopComposer.sol";
import "src/Constants.sol" as Constants;

contract DeployTestHopComposer is BaseScript {

    function run() public broadcaster {
        TestHopComposer hopComposer = new TestHopComposer();
        console.log("TestHopComposer deployed at:", address(hopComposer));
    }
}
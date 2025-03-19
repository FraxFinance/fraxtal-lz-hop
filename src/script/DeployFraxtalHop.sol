// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { FraxtalHop } from "src/contracts/hop/FraxtalHop.sol";
import "src/Constants.sol" as Constants;

contract DeployFraxtalHop is BaseScript {
    function run() public broadcaster { 
        FraxtalHop hop = new FraxtalHop();
        console.log("FraxtalHop deployed at:", address(hop));
        
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { TestnetFraxtalHop } from "src/contracts/hop/TestnetFraxtalHop.sol";
import "src/Constants.sol" as Constants;

// forge script src/script/hop/Fraxtal/DeployTestnetFraxtalHop.sol --rpc-url https://rpc.testnet.frax.com --broadcast --verifier custom --verifier-url https://api-holesky.fraxscan.com/api --verifier-api-key $FRAXSCAN_API_KEY
contract DeployTestnetFraxtalHop is BaseScript {
    address constant frxUsdLockbox = 0x7C9DF6704Ec6E18c5E656A2db542c23ab73CB24d;
    address[] approvedOfts;

    function run() public broadcaster {
        approvedOfts.push(frxUsdLockbox);

        TestnetFraxtalHop hop = new TestnetFraxtalHop(approvedOfts);
        console.log("TestnetFraxtalHop deployed at:", address(hop));
    }
}

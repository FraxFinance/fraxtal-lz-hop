// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { FraxtalHop } from "src/contracts/hop/FraxtalHop.sol";
import { FraxtalMintRedeemHop } from "src/contracts/hop/FraxtalMintRedeemHop.sol";
import "src/Constants.sol" as Constants;

// forge script src/script/hop/Fraxtal/DeployTestnetFraxtalHop.sol --rpc-url https://rpc.testnet.frax.com --broadcast
contract DeployTestnetFraxtalHop is BaseScript {
    address constant frxUsdLockbox = 0x7C9DF6704Ec6E18c5E656A2db542c23ab73CB24d;
    address[] approvedOfts;

    function run() public broadcaster {
        approvedOfts.push(frxUsdLockbox);

        FraxtalHop hop = new FraxtalHop(approvedOfts);
        console.log("TestnetFraxtalHop deployed at:", address(hop));
    }
}

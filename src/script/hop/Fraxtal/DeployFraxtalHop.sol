// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { FraxtalHop } from "src/contracts/hop/FraxtalHop.sol";
import { FraxtalMintRedeemHop } from "src/contracts/hop/FraxtalMintRedeemHop.sol";
import "src/Constants.sol" as Constants;

contract DeployFraxtalHop is BaseScript {
    address public constant frxUsdLockbox = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    address public constant sfrxUsdLockbox = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
    address public constant frxEthLockbox = 0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604;
    address public constant sfrxEthLockbox = 0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168;
    address public constant fxsLockbox = 0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A;
    address public constant fpiLockbox = 0x75c38D46001b0F8108c4136216bd2694982C20FC;
    address[] public approvedOfts;

    function run() public broadcaster {
        approvedOfts.push(frxUsdLockbox);
        approvedOfts.push(sfrxUsdLockbox);
        approvedOfts.push(frxEthLockbox);
        approvedOfts.push(sfrxEthLockbox);
        approvedOfts.push(fxsLockbox);
        approvedOfts.push(fpiLockbox);

        FraxtalHop hop = new FraxtalHop(approvedOfts);
        console.log("FraxtalHop deployed at:", address(hop));

        FraxtalMintRedeemHop mintRedeemHop = new FraxtalMintRedeemHop();
        console.log("FraxtalMintRedeemHop deployed at:", address(mintRedeemHop));
    }
}

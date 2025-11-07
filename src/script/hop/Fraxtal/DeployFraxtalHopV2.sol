// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { FraxtalHopV2 } from "src/contracts/hop/FraxtalHopV2.sol";

import { FraxUpgradeableProxy } from "frax-std/FraxUpgradeableProxy.sol";

import "src/Constants.sol" as Constants;

contract DeployFraxtalHopV2 is BaseScript {
    address constant proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;

    address constant frxUsdLockbox = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    address constant sfrxUsdLockbox = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
    address constant frxEthLockbox = 0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604;
    address constant sfrxEthLockbox = 0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168;
    address constant fxsLockbox = 0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A;
    address constant fpiLockbox = 0x75c38D46001b0F8108c4136216bd2694982C20FC;
    address[] approvedOfts;

    function run() public broadcaster {
        approvedOfts.push(frxUsdLockbox);
        approvedOfts.push(sfrxUsdLockbox);
        approvedOfts.push(frxEthLockbox);
        approvedOfts.push(sfrxEthLockbox);
        approvedOfts.push(fxsLockbox);
        approvedOfts.push(fpiLockbox);

        address hop = deployFraxtalHopV2(proxyAdmin, 0x1a44076050125825900e736c501f859c50fE728c, approvedOfts);
        console.log("FraxtalHopV2 deployed at:", hop);
    }
}

function deployFraxtalHopV2(
    address _proxyAdmin,
    address _endpoint,
    address[] memory _approvedOfts
) returns (address payable) {
    bytes memory initializeArgs = abi.encodeCall(FraxtalHopV2.initialize, (_endpoint, _approvedOfts));

    address implementation = address(new FraxtalHopV2());
    FraxUpgradeableProxy proxy = new FraxUpgradeableProxy(implementation, _proxyAdmin, initializeArgs);
    return payable(address(proxy));
}

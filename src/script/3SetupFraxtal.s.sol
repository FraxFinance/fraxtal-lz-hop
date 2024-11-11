// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { FraxtalLZCurveAMO } from "../contracts/amos/FraxtalLZCurveAMO.sol";
import { FraxProxy } from "../contracts/FraxProxy.sol";

// Run this with source .env && forge script --broadcast --rpc-url $MAINNET_URL DeployFraxtalL.s.sol
contract SetupFraxtal is BaseScript {
    FraxtalLZCurveAMO fraxtalLzCurveAmo = FraxtalLZCurveAMO(address(0)); // TODO
    address ethereumComposer = address(0); // TODO
    address ethereumLzSenderAmo = address(0); // TODO
    address multisig = address(0); // TODO

    bytes32 DEFAULT_ADMIN_ROLE = 0x00;

    function run() public broadcaster {
        fraxtalLzCurveAmo.setStorage({
            _ethereumComposer: ethereumComposer,
            _ethereumLzSenderAmo: ethereumLzSenderAmo
        });
        fraxtalLzCurveAmo.grantRole(DEFAULT_ADMIN_ROLE, multisig);
        fraxtalLzCurveAmo.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
    }
}

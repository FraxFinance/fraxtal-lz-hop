// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { EthereumNativeBridgeComposer } from "../contracts/composers/EthereumNativeBridgeComposer.sol";
import { EthereumLZSenderAMO } from "../contracts/amos/EthereumLZSenderAMO.sol";
import { FraxProxy } from "../contracts/FraxProxy.sol";

// Run this with source .env && forge script --broadcast --rpc-url $MAINNET_URL DeployFraxtalL.s.sol
contract DeployFraxtalL is BaseScript {
    address multisig = address(0); // TODO

    address endpoint = 0x1a44076050125825900e736c501f859c50fE728c;
    address l1Bridge = 0x34C0bD5877A5Ee7099D0f5688D65F4bB9158BDE2;
    address fraxtalLzCurveAmo = address(0); // TODO

    address fraxOft = 0x909DBdE1eBE906Af95660033e478D59EFe831fED;
    address sFraxOft = 0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E;
    address sFrxEthOft = 0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A;
    address fxsOft = 0x23432452B720C80553458496D4D9d7C5003280d0;
    address fpiOft = 0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d;

    function run() public broadcaster {
        // deploy EthereumNativeBridgeComposer
        address implementation = address(new EthereumNativeBridgeComposer());
        FraxProxy proxy = new FraxProxy(
            implementation,
            multisig,
            abi.encodeCall(EthereumNativeBridgeComposer.initialize, (endpoint, l1Bridge, fraxtalLzCurveAmo))
        );
        console.log("EthereumNativeBridgeComposer @ ", address(proxy));

        // Deploy EthereumLZSenderAMO
        implementation = address(new EthereumLZSenderAMO());
        proxy = new FraxProxy(
            implementation,
            multisig,
            abi.encodeCall(
                EthereumLZSenderAMO.initialize,
                (deployer, fraxtalLzCurveAmo, fraxOft, sFraxOft, sFrxEthOft, fxsOft, fpiOft)
            )
        );
        console.log("EthereumLZSenderAMO @ ", address(proxy));
    }
}

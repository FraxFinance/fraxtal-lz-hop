// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/FraxTest.sol";
import { LZCurveComposer } from "../contracts/LZCurveComposer.sol";
import { FraxProxy } from "../contracts/FraxProxy.sol";

// Run this with source .env && forge script --broadcast --rpc-url $MAINNET_URL DeployLZCurveComposer.s.sol
contract DeployLZCurveComposer is BaseScript {
    address endpoint = 0x1a44076050125825900e736c501f859c50fE728c; // fraxtal endpoint v2

    // All OFTs can be referenced at https://github.com/FraxFinance/frax-oft-upgradeable?tab=readme-ov-file#proxy-upgradeable-ofts
    address fraxOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
    address sFraxOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
    address frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
    address sFrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
    address fxsOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
    address fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;

    // Note: each curve pool is "native" token / "layerzero" token with "a" factor of 1400
    address fraxCurve = 0x53f8F4e154F68C2D29a0D06BD50f82bCf1bd95dB;
    address sFraxCurve = 0xd2866eF5A94E741Ec8EDE5FF8e3A1f9C59c5e298;
    address frxEthCurve = 0x50842664DfBD876249D0113671d72dB168FBE4d0;
    address sFrxEthCurve = 0xe5F61df936d50302962d5B914537Ff3cB63b3526;
    address fxsCurve = 0xBc383485068Ffd275D7262Bef65005eE7a5A1870;
    address fpiCurve = 0x7FaA69f8fEbe38bBfFbAE3252DE7D1491F0c6157;

    function run() public broadcaster {
        address implementation = address(new LZCurveComposer());
        FraxProxy proxy = new FraxProxy(
            implementation,
            msg.sender,
            abi.encodeCall(
                LZCurveComposer.initialize,
                (endpoint, fraxOft, sFraxOft, frxEthOft, sFrxEthOft, fxsOft, fpiOft)
            )
        );

        LZCurveComposer(payable(proxy)).initialize2({
            _fraxCurve: fraxCurve,
            _sFraxCurve: sFraxCurve,
            _frxEthCurve: frxEthCurve,
            _sFrxEthCurve: sFrxEthCurve,
            _fxsCurve: fxsCurve,
            _fpiCurve: fpiCurve
        });
    }
}

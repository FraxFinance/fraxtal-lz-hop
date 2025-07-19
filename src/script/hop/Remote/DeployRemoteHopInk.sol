// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopInk.sol --rpc-url https://rpc-gel.inkonchain.com --broadcast --verify --verifier blockscout --verifier-url https://explorer.inkonchain.com/api/
contract DeployRemoteHopInk is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0xFEbCF17b11376C724AB5a5229803C6e838b6eAe5;
        DVN = 0x174F2bA26f8ADeAfA82663bcf908288d5DbCa649;
        SEND_LIBRARY = 0x76111DE813F83AAAdBD62773Bf41247634e2319a;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        wFraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

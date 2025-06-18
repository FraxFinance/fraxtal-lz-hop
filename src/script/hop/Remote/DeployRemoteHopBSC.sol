// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopBSC.sol --rpc-url https://bsc-mainnet.public.blastapi.io --broadcast --verify --verifier etherscan --etherscan-api-key $BSC_SCAN_API_KEY
contract DeployRemoteHopBSC is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x3ebD570ed38B1b3b4BC886999fcF507e9D584859;
        DVN = 0xfD6865c841c2d64565562fCc7e05e619A30615f0;
        TREASURY = 0x4BA6dF2CdB28820B4f007EF7A81E806f81b2c5dC;
        EID = 30102;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        wFraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

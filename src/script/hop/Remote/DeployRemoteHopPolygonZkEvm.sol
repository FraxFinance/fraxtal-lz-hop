// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopPolygonZkEvm.sol --rpc-url https://zkevm-rpc.com --broadcast --verify --verifier etherscan --etherscan-api-key $ZKPOLYGONSCAN_API_KEY
contract DeployRemoteHopPolygonZkEvm is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0xbE4fB271cfB7bcbB47EA9573321c7bfe309fc220;
        DVN = 0x488863D609F3A673875a914fBeE7508a1DE45eC6;
        TREASURY = 0x79858b17DB45F0a1b927e30377E06b81ed25226A;
        EID = 30158;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        wFraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopArbitrum.sol --rpc-url https://arb1.arbitrum.io/rpc --broadcast --verify --verifier etherscan --etherscan-api-key $ARBISCAN_API_KEY
contract DeployRemoteHopArbitrum is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x31CAe3B7fB82d847621859fb1585353c5720660D;
        DVN = 0x2f55C492897526677C5B68fb199ea31E2c126416;
        TREASURY = 0x532410B245eB41f24Ed1179BA0f6ffD94738AE70;
        EID = 30110;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        fxsOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

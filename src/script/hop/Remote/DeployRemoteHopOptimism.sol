// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopOptimism.sol --rpc-url https://optimism-mainnet.public.blastapi.io --broadcast --verify --verifier etherscan --etherscan-api-key $OPTIMISM_API_KEY
contract DeployRemoteHopOptimism is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x2D2ea0697bdbede3F01553D2Ae4B8d0c486B666e;
        DVN = 0x6A02D83e8d433304bba74EF1c427913958187142;
        TREASURY = 0x6c26c61a97006888ea9E4FA36584c7df57Cd9dA3;
        EID = 30111;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        fxsOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopAvalanche.sol --rpc-url https://api.avax.network/ext/bc/C/rpc --broadcast --verify --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/43114/etherscan' --etherscan-api-key "verifyContract" --verifier etherscan
contract DeployRemoteHopAvalanche is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x90E595783E43eb89fF07f63d27B8430e6B44bD9c;
        DVN = 0x962F502A63F5FBeB44DC9ab932122648E8352959;
        TREASURY = 0xe4DD168822767C4342e54e6241f0b91DE0d3c241;
        EID = 30106;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        fxsOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

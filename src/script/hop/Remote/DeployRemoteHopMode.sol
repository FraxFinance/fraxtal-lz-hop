// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopMode.sol --rpc-url https://mainnet.mode.network --broadcast --verify --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/34443/etherscan' --etherscan-api-key "verifyContract" --verifier etherscan
contract DeployRemoteHopMode is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b;
        DVN = 0xce8358bc28dd8296Ce8cAF1CD2b44787abd65887;
        TREASURY = 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;
        EID = 30260;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        wFraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

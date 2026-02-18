// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopStable.sol --rpc-url https://rpc.stable.xyz --broadcast --with-gas-price 0gwei --block-base-fee-per-gas=0 --gas-price=0 --priority-gas-price=0 --slow --verify --verifier blockscout --verifier-url https://partners-explorer.stable.xyz/api/
contract DeployRemoteHopStable is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b;
        DVN = 0x9C061c9A4782294eeF65ef28Cb88233A987F4bdD;
        SEND_LIBRARY = 0x37aaaf95887624a363effB7762D489E3C05c2a02;

        owner = 0x0C46f54BF9EF8fd58e2D294b8cEA488204EcB3D8;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        wFraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

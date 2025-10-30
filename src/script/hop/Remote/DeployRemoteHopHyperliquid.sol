// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopHyperliquid.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast --verify --verifier etherscan --etherscan-api-key $HYPEREVMSCAN_API_KEY --chain-id 999 --verifier-url https://api.etherscan.io/v2/api
contract DeployRemoteHopHyperliquid is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x41Bdb4aa4A63a5b2Efc531858d3118392B1A1C3d;
        DVN = 0xc097ab8CD7b053326DFe9fB3E3a31a0CCe3B526f;
        SEND_LIBRARY = 0xfd76d9CB0Bac839725aB79127E7411fe71b1e3CA;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        wFraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

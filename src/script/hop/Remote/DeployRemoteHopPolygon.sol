// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopPolygon.sol --rpc-url https://polygon-rpc.com --broadcast --verify --verifier etherscan --etherscan-api-key $POLYGONSCAN_API_KEY
contract DeployRemoteHopPolygon is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0xCd3F213AD101472e1713C72B1697E727C803885b;
        DVN = 0x23DE2FE932d9043291f870324B74F820e11dc81A;
        TREASURY = 0xECEE8B581960634aF89f467AE624Ff468a9Db14B;
        EID = 30109;

        frxUsdOft = 0x80Eede496655FB9047dd39d9f418d5483ED600df;
        sfrxUsdOft = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0;
        frxEthOft = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050;
        sfrxEthOft = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45;
        wFraxOft = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a;
        fpiOft = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;
    }
}

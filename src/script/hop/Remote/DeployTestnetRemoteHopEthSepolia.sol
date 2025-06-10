// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployTestnetRemoteHop } from "./DeployTestnetRemoteHop.sol";

// forge script src/script/hop/Remote/DeployTestnetRemoteHopEthSepolia.sol --rpc-url https://eth-sepolia.public.blastapi.io  --broadcast --verify --verifier custom --verifier-url https://api-sepolia.etherscan.io/api --verifier-api-key $ETHERSCAN_API_KEY
contract DeployTestnetRemoteHopEthSepolia is DeployTestnetRemoteHop {
    constructor() {
        EXECUTOR = 0x718B92b5CB0a5552039B593faF724D182A881eDA;
        DVN = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193;
        TREASURY = 0xBE1471B322a52786C81c5de5fc12EA40E3e52624;
        EID = 40161;

        frxUsdOft = 0x29a5134D3B22F47AD52e0A22A63247363e9F35c2;
    }
}

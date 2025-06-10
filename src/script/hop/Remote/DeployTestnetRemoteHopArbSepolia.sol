// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployTestnetRemoteHop } from "./DeployTestnetRemoteHop.sol";

// forge script src/script/hop/Remote/DeployTestnetRemoteHopArbSepolia.sol --rpc-url https://arbitrum-sepolia-rpc.publicnode.com  --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployTestnetRemoteHopArbSepolia is DeployTestnetRemoteHop {
    constructor() {
        EXECUTOR = 0x5Df3a1cEbBD9c8BA7F8dF51Fd632A9aef8308897;
        DVN = 0x53f488E93b4f1b60E8E83aa374dBe1780A1EE8a8;
        TREASURY = 0x1352E658A305e9f94303F9A93aD436027E3cFD43;
        EID = 40231;

        frxUsdOft = 0x0768C16445B41137F98Ab68CA545C0afD65A7513;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopMonad.sol --rpc-url https://rpc.monad.xyz --broadcast --verify --verifier etherscan --etherscan-api-key $MONADSCAN_API_KEY --chain-id 143 --verifier-url --verifier-url "https://api.etherscan.io/v2/api?chainid=143"
contract DeployRemoteHopMonad is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b;
        DVN = 0x282b3386571f7f794450d5789911a9804FA346b4;
        SEND_LIBRARY = 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7;

        owner = 0x47FF5bBAB981Ff022743AA4281D4d6Dd7Fb1a4D0;

        frxUsdOft = 0x58E3ee6accd124642dDB5d3f91928816Be8D8ed3;
        sfrxUsdOft = 0x137643F7b2C189173867b3391f6629caB46F0F1a;
        frxEthOft = 0x288F9D76019469bfEb56BB77d86aFa2bF563B75B;
        sfrxEthOft = 0x3B4cf37A3335F21c945a40088404c715525fCb29;
        wFraxOft = 0x29aCC7c504665A5EA95344796f784095f0cfcC58;
        fpiOft = 0xBa554F7A47f0792b9fa41A1256d4cf628Bb1D028;
    }
}

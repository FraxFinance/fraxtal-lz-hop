// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopScroll.sol --rpc-url https://rpc.scroll.io --broadcast --verify --verifier etherscan --etherscan-api-key $SCROLLSCAN_API_KEY
contract DeployRemoteHopScroll is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x581b26F362AD383f7B51eF8A165Efa13DDe398a4;
        DVN = 0xbe0d08a85EeBFCC6eDA0A843521f7CBB1180D2e2;
        SEND_LIBRARY = 0x9BbEb2B2184B9313Cf5ed4a4DDFEa2ef62a2a03B;

        frxUsdOft = 0x397F939C3b91A74C321ea7129396492bA9Cdce82;
        sfrxUsdOft = 0xC6B2BE25d65760B826D0C852FD35F364250619c2;
        frxEthOft = 0x0097Cf8Ee15800d4f80da8A6cE4dF360D9449Ed5;
        sfrxEthOft = 0x73382eb28F35d80Df8C3fe04A3EED71b1aFce5dE;
        wFraxOft = 0x879BA0EFE1AB0119FefA745A21585Fa205B07907;
        fpiOft = 0x93cDc5d29293Cb6983f059Fec6e4FFEb656b6a62;
    }
}

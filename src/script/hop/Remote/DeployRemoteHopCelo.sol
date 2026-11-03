// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// @dev `--evm-version shanghai` is required: the OFTs on this chain contain PUSH0, which the repo's
//      default `paris` fork EVM rejects with `NotActivated` during simulation.
// @dev FPI was retired before Celo joined the mesh, so there is no FPI OFT on this chain.
//
// Dry run:  forge script src/script/hop/Remote/DeployRemoteHopCelo.sol --rpc-url https://forno.celo.org --evm-version shanghai --gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc
// Broadcast: forge script src/script/hop/Remote/DeployRemoteHopCelo.sol --rpc-url https://forno.celo.org --evm-version shanghai --gcp --sender 0x54f9b12743a7deec0ea48721683cbebedc6e17bc --broadcast
//
// Deployed: 0x3Fe759e54D619a655650ac64622aCE94BD6b6394 (Celoscan verified; Sourcify v2: creation + runtime match)
contract DeployRemoteHopCelo is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x1dDbaF8b75F2291A97C22428afEf411b7bB19e28;
        DVN = 0x75b073994560A5c03Cd970414d9170be0C6e5c36;
        SEND_LIBRARY = 0x42b4E9C6495B4cFDaE024B1eC32E09F28027620e;

        owner = 0xFfdBB6221390d05366df8F6733E586c8CE92103C;

        // Fraxtal -> Celo (eid 30125) opens only with all 5 required DVNs, Frax DVN included
        numDVNs = 5;

        frxUsdOft = 0x00000000D61733e7A393A10A5B48c311AbE8f1E5;
        sfrxUsdOft = 0x00000000fD8C4B8A413A06821456801295921a71;
        frxEthOft = 0x000000008c3930dCA540bB9B3A5D0ee78FcA9A4c;
        sfrxEthOft = 0x00000000883279097A49dB1f2af954EAd0C77E3c;
        wFraxOft = 0x00000000E9CE0f293D1Ce552768b187eBA8a56D4;
    }
}

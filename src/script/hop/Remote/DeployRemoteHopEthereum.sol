// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopEthereum.sol --rpc-url https://ethereum-rpc.publicnode.com --broadcast --verify --verifier etherscan --etherscan-api-key $ETHERSCAN_API_KEY
contract DeployRemoteHopEthereum is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
        DVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
        TREASURY = 0x5ebB3f2feaA15271101a927869B3A56837e73056;
        EID = 30101;

        frxUsdOft = 0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0;
        sfrxUsdOft = 0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126;
        frxEthOft = 0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6;
        sfrxEthOft = 0xbBc424e58ED38dd911309611ae2d7A23014Bd960;
        wFraxOft = 0xC6F59a4fD50cAc677B51558489E03138Ac1784EC;
        fpiOft = 0x9033BAD7aA130a2466060A2dA71fAe2219781B4b;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { DeployRemoteHop } from "./DeployRemoteHop.sol";

// forge script src/script/hop/Remote/DeployRemoteHopAbstract.sol --rpc-url https://api.mainnet.abs.xyz --zksync --broadcast --verify --verifier etherscan --etherscan-api-key $ABSTRACT_ETHERSCAN_API_KEY
contract DeployRemoteHopAbstract is DeployRemoteHop {
    constructor() {
        EXECUTOR = 0x643E1471f37c4680Df30cF0C540Cd379a0fF58A5;
        DVN = 0xF4DA94b4EE9D8e209e3bf9f469221CE2731A7112;
        TREASURY = 0x54f1DEB345306F326096a2dce26c0DD05e7B595A;
        EID = 30324;

        frxUsdOft = 0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d;
        sfrxUsdOft = 0x9F87fbb47C33Cd0614E43500b9511018116F79eE;
        frxEthOft = 0xc7Ab797019156b543B7a3fBF5A99ECDab9eb4440;
        sfrxEthOft = 0xFD78FD3667DeF2F1097Ed221ec503AE477155394;
        wFraxOft = 0xAf01aE13Fb67AD2bb2D76f29A83961069a5F245F;
        fpiOft = 0x580F2ee1476eDF4B1760bd68f6AaBaD57dec420E;
    }
}

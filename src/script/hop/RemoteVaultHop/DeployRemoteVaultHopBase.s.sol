pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteVaultHop } from "src/contracts/hop/RemoteVaultHop.sol";
import { DeployRemoteVaultHop } from "./DeployRemoteVaultHop.s.sol";

contract DeployRemoteVaultHopBase is DeployRemoteVaultHop {
    constructor() {
        frxUSD = 0xe5020A6d073a794B6E7f05678707dE47986Fb0b6;
        frxUsdOft = 0xe5020A6d073a794B6E7f05678707dE47986Fb0b6;
        HOPV2 = 0x10f2773F54CA36d456d6513806aA24f5169D6765;
        EID = 30184;
    }
}

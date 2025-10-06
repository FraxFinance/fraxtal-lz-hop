pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteVaultHop } from "src/contracts/hop/RemoteVaultHop.sol";
import { DeployRemoteVaultHop } from  "./DeployRemoteVaultHop.sol";

contract DeployRemoteVaultHopFraxtal is DeployRemoteVaultHop {
    constructor() {
        frxUSD = 0xFc00000000000000000000000000000000000001;
        frxUsdOft = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
        HOPV2 = 0xB0f86D71568047B80bc105D77C63F8a6c5AEB5a8;
        EID = 30255; // Fraxtal Mainnet
    }
}
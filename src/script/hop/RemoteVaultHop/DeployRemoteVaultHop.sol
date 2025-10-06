pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteVaultHop } from "src/contracts/hop/RemoteVaultHop.sol";

abstract contract DeployRemoteVaultHop is BaseScript {
    address frxUSD;
    address frxUsdOft;
    address HOPV2;
    uint32 EID;
    

    function run() public broadcaster {
        RemoteVaultHop vaultHop = new RemoteVaultHop(frxUSD, frxUsdOft, HOPV2, EID);
        console.log("RemoteVaultHop deployed at:", address(vaultHop));
        if (EID==30255) {
            vaultHop.addLocalVault(0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2,0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2);
        } else {
            vaultHop.setRemoteVaultHop(30255, 0x68Ca8194c743E9b00806C6D32D16152BA5368Eee);
            vaultHop.addRemoteVault(30255, 0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2, "Remote Fraxtal Fraxlend frxUSD (WFRAX)","rffrxUSD(WFRAX)");
        }
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteHop } from "src/contracts/hop/RemoteHop.sol";
import { RemoteMintRedeemHop } from "src/contracts/hop/RemoteMintRedeemHop.sol";
import "src/Constants.sol" as Constants;

contract DeployRemoteHopLinea is BaseScript {
    address constant FRAXTAL_HOP = 0xFF43a3A07fC421d2f0A675B5b8764Fc012523600;
    address constant FRAXTAL_MINTREDEEM_HOP = 0x763a253d9C1CB4E57DbE2564e97D555bba0D83f0;
    address constant EXECUTOR = 0x0408804C5dcD9796F22558464E6fE5bDdF16A7c7;
    address constant DVN = 0x129Ee430Cb2Ff2708CCADDBDb408a88Fe4FFd480;
    address constant TREASURY = 0xf463B0E147D99763136374E6A22a0Ba9bBb9ed09;
    uint32 constant EID = 30183;

    function run() public broadcaster {
        RemoteHop remoteHop = new RemoteHop(bytes32(uint256(uint160(FRAXTAL_HOP))), 2, EXECUTOR, DVN, TREASURY);
        console.log("RemoteHop deployed at:", address(remoteHop));

        RemoteMintRedeemHop remoteMintRedeemHop = new RemoteMintRedeemHop(
            bytes32(uint256(uint160(FRAXTAL_MINTREDEEM_HOP))),
            2,
            EXECUTOR,
            DVN,
            TREASURY,
            EID
        );
        console.log("RemoteMintRedeemHop deployed at:", address(remoteMintRedeemHop));
    }
}

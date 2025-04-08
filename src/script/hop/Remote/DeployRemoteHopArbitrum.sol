// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteHop } from "src/contracts/hop/RemoteHop.sol";
import { RemoteMintRedeemHop } from "src/contracts/hop/RemoteMintRedeemHop.sol";
import "src/Constants.sol" as Constants;

contract DeployRemoteHopArbitrum is BaseScript {
    address constant FRAXTAL_HOP = 0xFF43a3A07fC421d2f0A675B5b8764Fc012523600;
    address constant FRAXTAL_MINTREDEEM_HOP = 0x763a253d9C1CB4E57DbE2564e97D555bba0D83f0;
    address constant EXECUTOR = 0x31CAe3B7fB82d847621859fb1585353c5720660D;
    address constant DVN = 0x2f55C492897526677C5B68fb199ea31E2c126416;
    address constant TREASURY = 0x532410B245eB41f24Ed1179BA0f6ffD94738AE70;
    uint32 constant EID = 30110;

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

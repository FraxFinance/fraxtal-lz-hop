// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteHop } from "src/contracts/hop/RemoteHop.sol";
import { RemoteMintRedeemHop } from "src/contracts/hop/RemoteMintRedeemHop.sol";
import "src/Constants.sol" as Constants;

contract DeployRemoteHopSei is BaseScript {
    address constant FRAXTAL_HOP = 0xFF43a3A07fC421d2f0A675B5b8764Fc012523600;
    address constant FRAXTAL_MINTREDEEM_HOP = 0x763a253d9C1CB4E57DbE2564e97D555bba0D83f0;
    address constant EXECUTOR = 0xc097ab8CD7b053326DFe9fB3E3a31a0CCe3B526f;
    address constant DVN = 0x6788f52439ACA6BFF597d3eeC2DC9a44B8FEE842;
    address constant TREASURY = 0x4514FC667a944752ee8A29F544c1B20b1A315f25;
    uint32 constant EID = 30280;

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

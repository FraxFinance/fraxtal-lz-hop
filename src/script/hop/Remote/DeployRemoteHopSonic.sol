// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteHop } from "src/contracts/hop/RemoteHop.sol";
import { RemoteMintRedeemHop } from "src/contracts/hop/RemoteMintRedeemHop.sol";
import "src/Constants.sol" as Constants;

contract DeployRemoteHopSonic is BaseScript {
    address constant FRAXTAL_HOP = 0xEE30e79b54e9a341dcD5621AF1799e2af799b9B0;
    address constant FRAXTAL_MINTREDEEM_HOP = 0xf8b29272Db8B482459596C60b37BBF0B8F86E892;
    address constant EXECUTOR = 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b;
    address constant DVN = 0x282b3386571f7f794450d5789911a9804FA346b4;
    address constant TREASURY = 0x4514FC667a944752ee8A29F544c1B20b1A315f25;
    uint32 constant EID = 30332;

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

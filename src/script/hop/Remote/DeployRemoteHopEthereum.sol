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
    address constant EXECUTOR = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
    address constant DVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address constant TREASURY = 0x5ebB3f2feaA15271101a927869B3A56837e73056;
    uint32 constant EID = 30101;

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

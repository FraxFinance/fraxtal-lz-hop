pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteHop } from "src/contracts/hop/RemoteHop.sol";
import { RemoteMintRedeemHop } from "src/contracts/hop/RemoteMintRedeemHop.sol";

abstract contract DeployRemoteHop is BaseScript {
    address constant FRAXTAL_HOP = 0xEE30e79b54e9a341dcD5621AF1799e2af799b9B0;
    address constant FRAXTAL_MINTREDEEM_HOP = 0xf8b29272Db8B482459596C60b37BBF0B8F86E892;

    address EXECUTOR;
    address DVN;
    address TREASURY;
    uint32 EID;
    address frxUsdOft;
    address sfrxUsdOft;
    address frxEthOft;
    address sfrxEthOft;
    address fxsOft;
    address fpiOft;
    address[] approvedOfts;

    function run() public broadcaster {
        approvedOfts.push(frxUsdOft);
        approvedOfts.push(sfrxUsdOft);
        approvedOfts.push(frxEthOft);
        approvedOfts.push(sfrxEthOft);
        approvedOfts.push(fxsOft);
        approvedOfts.push(fpiOft);

        RemoteHop remoteHop = new RemoteHop({
            _fraxtalHop: bytes32(uint256(uint160(FRAXTAL_HOP))),
            _numDVNs: 2,
            _EXECUTOR: EXECUTOR,
            _DVN: DVN,
            _TREASURY: TREASURY,
            _approvedOfts: approvedOfts
        });
        console.log("RemoteHop deployed at:", address(remoteHop));

        RemoteMintRedeemHop remoteMintRedeemHop = new RemoteMintRedeemHop({
            _fraxtalHop: bytes32(uint256(uint160(FRAXTAL_MINTREDEEM_HOP))),
            _numDVNs: 2,
            _EXECUTOR: EXECUTOR,
            _DVN: DVN,
            _TREASURY: TREASURY,
            _EID: EID,
            _frxUsdOft: frxUsdOft,
            _sfrxUsdOft: sfrxUsdOft
        });
        console.log("RemoteMintRedeemHop deployed at:", address(remoteMintRedeemHop));
    }
}

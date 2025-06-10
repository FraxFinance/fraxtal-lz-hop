pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { RemoteHop } from "src/contracts/hop/RemoteHop.sol";
import { RemoteMintRedeemHop } from "src/contracts/hop/RemoteMintRedeemHop.sol";

abstract contract DeployTestnetRemoteHop is BaseScript {
    address constant FRAXTAL_HOP = 0x45c6852A5188Ce1905567EA83454329bd4982007;

    address EXECUTOR;
    address DVN;
    address TREASURY;
    uint32 EID;
    address frxUsdOft;
    address[] approvedOfts;

    function run() public broadcaster {
        approvedOfts.push(frxUsdOft);

        RemoteHop remoteHop = new RemoteHop({
            _fraxtalHop: bytes32(uint256(uint160(FRAXTAL_HOP))),
            _numDVNs: 2,
            _EXECUTOR: EXECUTOR,
            _DVN: DVN,
            _TREASURY: TREASURY,
            _approvedOfts: approvedOfts
        });
        console.log("TestnetRemoteHop deployed at:", address(remoteHop));
    }
}

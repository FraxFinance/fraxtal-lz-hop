pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { TestnetRemoteHop } from "src/contracts/hop/TestnetRemoteHop.sol";

abstract contract DeployTestnetRemoteHop is BaseScript {
    address constant FRAXTAL_HOP = 0xd593Df4E2E3156C5707bB6AE4ba26fd4A9A04586;

    address EXECUTOR;
    address DVN;
    address TREASURY;
    uint32 EID;
    address frxUsdOft;
    address[] approvedOfts;

    function run() public broadcaster {
        approvedOfts.push(frxUsdOft);

        TestnetRemoteHop remoteHop = new TestnetRemoteHop({
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

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { BaseScript } from "frax-std/BaseScript.sol";
import { console } from "frax-std/BaseScript.sol";
import { FraxtalHopV2 } from "src/contracts/hop/FraxtalHopV2.sol";
import { HopV2 } from "src/contracts/hop/HopV2.sol";

import { FraxUpgradeableProxy } from "frax-std/FraxUpgradeableProxy.sol";

import "src/Constants.sol" as Constants;

// forge script src/script/hop/Fraxtal/DeployFraxtalHopV2.s.sol --rpc-url https://rpc.frax.com --broadcast --verify --verifier etherscan --etherscan-api-key $TODO
contract DeployFraxtalHopV2 is BaseScript {
    address constant proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;

    address constant frxUsdLockbox = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    address constant sfrxUsdLockbox = 0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361;
    address constant frxEthLockbox = 0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604;
    address constant sfrxEthLockbox = 0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168;
    address constant fxsLockbox = 0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A;
    address constant fpiLockbox = 0x75c38D46001b0F8108c4136216bd2694982C20FC;
    address[] approvedOfts;

    function run() public broadcaster {
        approvedOfts.push(frxUsdLockbox);
        approvedOfts.push(sfrxUsdLockbox);
        approvedOfts.push(frxEthLockbox);
        approvedOfts.push(sfrxEthLockbox);
        approvedOfts.push(fxsLockbox);
        approvedOfts.push(fpiLockbox);

        address hop = deployFraxtalHopV2(proxyAdmin, 0x1a44076050125825900e736c501f859c50fE728c, approvedOfts);
        console.log("FraxtalHopV2 deployed at:", hop);

        // grant Pauser roles to msig signers

        // carter
        HopV2(hop).grantRole(0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a, 0x13Fe84D36d7a507Bb4bdAC6dCaF13a10961fc470);
        // sam
        HopV2(hop).grantRole(0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a, 0x17e06ce6914E3969f7BD37D8b2a563890cA1c96e);
        // dhruvin
        HopV2(hop).grantRole(0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a, 0x8d8290d49e88D16d81C6aDf6C8774eD88762274A);
        // travis
        HopV2(hop).grantRole(0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a, 0xcbc616D595D38483e6AdC45C7E426f44bF230928);
        // thomas
        HopV2(hop).grantRole(0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a, 0x381e2495e683868F693AA5B1414F712f21d34b40);
        // nader
        HopV2(hop).grantRole(0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a, 0x6e74053a3798e0fC9a9775F7995316b27f21c4D2);

        // transfer admin role to fraxtal msig and renounce from deployer
        HopV2(hop).grantRole(bytes32(0), 0x5f25218ed9474b721d6a38c115107428E832fA2E);
        HopV2(hop).renounceRole(bytes32(0), vm.addr(privateKey));
    }
}

function deployFraxtalHopV2(
    address _proxyAdmin,
    address _endpoint,
    address[] memory _approvedOfts
) returns (address payable) {
    bytes memory initializeArgs = abi.encodeCall(FraxtalHopV2.initialize, (_endpoint, _approvedOfts));

    address implementation = address(new FraxtalHopV2());
    FraxUpgradeableProxy proxy = new FraxUpgradeableProxy(implementation, _proxyAdmin, initializeArgs);
    return payable(address(proxy));
}

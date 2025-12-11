pragma solidity ^0.8.0;

import { BaseScript } from "frax-std/BaseScript.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IHopV2 } from "src/contracts/hop/interfaces/IHopV2.sol";
import { SafeTxHelper, SafeTx } from "frax-std/SafeTxHelper.sol";

// forge script src/script/hop/RemoteAdmin/AddPauser.s.sol --rpc-url https://rpc.frax.com
contract AddPauserScript is BaseScript {
    /// @dev signer is the person we are adding role from
    address public signer1 = 0x13Fe84D36d7a507Bb4bdAC6dCaF13a10961fc470; // carter
    address public signer2 = 0xC6EF452b0de9E95Ccb153c2A5A7a90154aab3419; // dennis

    address public fraxtalMsig = 0x5f25218ed9474b721d6a38c115107428E832fA2E;
    address public fraxtalHop = 0xe8Cd13de17CeC6FCd9dD5E0a1465Da240f951536;
    address public frxUsdAdapter = 0x96A394058E2b84A89bac9667B19661Ed003cF5D4;
    uint128 public dstGas = 250_000;
    bytes32 public PAUSER_ROLE = 0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a; // keccak256("PAUSER_ROLE")

    struct HopData {
        uint32 eid;
        address hop;
        address remoteAdmin;
    }
    HopData[] public hopDatas;
    SafeTx[] public txs;

    constructor() {
        hopDatas.push(
            HopData({
                eid: 30255, // fraxtal
                hop: fraxtalHop,
                remoteAdmin: 0xDC3369C18Ff9C077B803C98b6260a186aDE9A426
            })
        );
        hopDatas.push(
            HopData({
                eid: 30110, // arbitrum
                hop: 0xf307Ad241E1035062Ed11F444740f108B8D036a6,
                remoteAdmin: 0x03047fA366900b4cBf5E8F9FEEce97553f20370e
            })
        );
        hopDatas.push(
            HopData({
                eid: 30184, // base
                hop: 0x22beDD55A0D29Eb31e75C70F54fADa7Ca94339B9,
                remoteAdmin: 0xF333d66C7e47053b96bC153Bfdfaa05c8BEe7307
            })
        );
    }

    function run() external {
        for (uint256 i = 0; i < hopDatas.length; i++) {
            HopData memory hopData = hopDatas[i];

            // add signer 1
            bytes memory remoteCall = abi.encodeCall(IAccessControl.grantRole, (PAUSER_ROLE, signer1));
            bytes memory data = abi.encode(hopData.hop, remoteCall);

            uint256 fee = IHopV2(fraxtalHop).quote({
                _oft: frxUsdAdapter,
                _dstEid: hopData.eid,
                _recipient: bytes32(uint256(uint160(hopData.remoteAdmin))),
                _amountLD: 0,
                _dstGas: dstGas,
                _data: data
            });
            // increase fee by 50% to be safe if gas increases between quote and send
            fee = (fee * 150) / 100;

            bytes memory localCall = abi.encodeWithSignature(
                "sendOFT(address,uint32,bytes32,uint256,uint128,bytes)",
                frxUsdAdapter, // _oft
                hopData.eid, // _dstEid
                bytes32(uint256(uint160(hopData.remoteAdmin))), // _recipient
                uint256(0), // _amountLD
                dstGas, // _dstGas
                data // _data
            );
            vm.prank(fraxtalMsig);
            (bool success, ) = fraxtalHop.call{ value: fee }(localCall);
            require(success, "sendOFT() failed");

            txs.push(SafeTx({ name: "sendOFT", to: fraxtalHop, value: fee, data: localCall }));

            // add signer 2
            remoteCall = abi.encodeCall(IAccessControl.grantRole, (PAUSER_ROLE, signer2));
            data = abi.encode(hopData.hop, remoteCall);

            localCall = abi.encodeWithSignature(
                "sendOFT(address,uint32,bytes32,uint256,uint128,bytes)",
                frxUsdAdapter, // _oft
                hopData.eid, // _dstEid
                bytes32(uint256(uint160(hopData.remoteAdmin))), // _recipient
                uint256(0), // _amountLD
                dstGas, // _dstGas
                data // _data
            );
            vm.prank(fraxtalMsig);
            (success, ) = fraxtalHop.call{ value: fee }(localCall);
            require(success, "sendOFT() failed");

            txs.push(SafeTx({ name: "sendOFT", to: fraxtalHop, value: fee, data: localCall }));
        }

        // save to file
        string memory root = vm.projectRoot();
        string memory filename = string(abi.encodePacked(root, "/src/script/hop/RemoteAdmin/txs/AddPauser.json"));
        new SafeTxHelper().writeTxs(txs, filename);
    }
}

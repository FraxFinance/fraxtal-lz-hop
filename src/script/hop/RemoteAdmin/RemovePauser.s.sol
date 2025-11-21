pragma solidity ^0.8.0;

import { BaseScript } from "frax-std/BaseScript.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IHopV2 } from "src/contracts/hop/interfaces/IHopV2.sol";
import { SafeTxHelper, SafeTx } from "frax-std/SafeTxHelper.sol";

// forge script src/script/hop/RemoteAdmin/RemovePauser.s.sol --rpc-url https://rpc.frax.com
contract RemovePauserScript is BaseScript {

    /// @dev signer is the person we are removing the role from
    address public signer = 0x13Fe84D36d7a507Bb4bdAC6dCaF13a10961fc470;
    address public fraxtalMsig = 0x5f25218ed9474b721d6a38c115107428E832fA2E;
    address public fraxtalHop = 0x1b93526eA567d59B7FD38126bb74D72818166C51;
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
                remoteAdmin: 0x5B9d0ad83b62159589a4CED620492EE099571CA8
            })
        );
        hopDatas.push(
            HopData({
                eid: 30110, // arbitrum
                hop: 0x3A5cDA3Ac66Aa80573402610c94B74eD6cdb2F23,
                remoteAdmin: 0xd593Df4E2E3156C5707bB6AE4ba26fd4A9A04586
            })
        );
        hopDatas.push(
            HopData({
                eid: 30184, // base
                hop: 0x56B75e191801614b5b84CcFe87cdDD76f57AaD64,
                remoteAdmin: 0xa9E4C0108c4d06d563d995a4B3487f81D8F5A053
            })
        );
    }

    function run() external {

        for (uint256 i=0; i < hopDatas.length; i++) {
            HopData memory hopData = hopDatas[i];
            
            bytes memory remoteCall = abi.encodeCall(
                IAccessControl.revokeRole,
                (
                    PAUSER_ROLE,
                    signer
                )
            );
            bytes memory data = abi.encode(hopData.hop, remoteCall);

            uint256 fee = IHopV2(fraxtalHop).quote({
                _oft: frxUsdAdapter,
                _dstEid: hopData.eid,
                _recipient: bytes32(uint256(uint160(hopData.remoteAdmin))),
                _amountLD: 0,
                _dstGas: dstGas,
                _data: data
            });
            // increase fee by 25% to be safe if gas increases between quote and send
            fee = (fee * 125) / 100;

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

            txs.push(SafeTx({
                name: "sendOFT",
                to: fraxtalHop,
                value: fee,
                data: localCall
            }));
        }

        // save to file
        string memory root = vm.projectRoot();
        string memory filename = string(
            abi.encodePacked(
                root,
                "/src/script/hop/RemoteAdmin/txs/RemovePauser.json"
            )
        );
        new SafeTxHelper().writeTxs(txs, filename);
    }
}
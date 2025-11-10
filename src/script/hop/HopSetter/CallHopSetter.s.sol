pragma solidity ^0.8.0;

import { IRemoteHopV2 } from "src/contracts/hop/interfaces/IRemoteHopV2.sol";
import { BaseScript } from "frax-std/BaseScript.sol";
import { SafeTxHelper, SafeTx } from "frax-std/SafeTxHelper.sol";
import { HopSetter } from "src/contracts/hop/HopSetter.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

// forge script src/script/hop/HopSetter/CallHopSetter.s.sol --rpc-url https://rpc.frax.com
contract CallHopSetter is BaseScript {
    using Strings for uint256;

    address public msig = 0x96EA834aa9c054982A41bd91bAFE917C0A3CAf1a;
    HopSetter public hopSetter = HopSetter(payable(0x24fe43E1667e8d139c61568C9bAf75EfBaE13502));
    uint32[] public eids;
    SafeTx[] public txs;

    function run() public {
        createTxs();
        saveTxs();
    }

    function createTxs() public {
        eids.push(30110); // arbitrum
        eids.push(30184); // base
        // TODO: add more supported EIDs here

        // Example: setExecutorOptions on Arbitrum, Base for Solana (30168) from Fraxtal
        uint128 dstGas = 250_000; // dev: converts to 3.2M
        bytes memory data = abi.encodeCall(
            IRemoteHopV2.setExecutorOptions,
            (30168, hex"0100210100000000000000000000000000030D40000000000000000000000000002DC6C0")
        );

        bytes memory encodedCall = abi.encodeCall(HopSetter.callRemoteHops, (eids, dstGas, data));

        vm.prank(msig);
        (bool success, ) = address(hopSetter).call(encodedCall);
        require(success, "callRemoteHops failed");

        txs.push(SafeTx({ name: "HopSetter.callRemoteHops", to: address(hopSetter), value: 0, data: encodedCall }));
    }

    function saveTxs() public {
        string memory root = vm.projectRoot();
        string memory filename = string(
            abi.encodePacked(root, "/src/script/hop/HopSetter/txs/CallHopSetter_", block.timestamp.toString(), ".json")
        );

        if (txs.length > 0) {
            new SafeTxHelper().writeTxs(txs, filename);
        } else {
            revert("No txs to save");
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { SafeTxHelper, SafeTx } from "frax-std/SafeTxHelper.sol";
import { HopConstants, LegacyHopTarget } from "src/script/hop/HopConstants.sol";

interface ILegacyHopNumDVNs {
    function setNumDVNs(uint256 _numDVNs) external;
}

// Generates direct local Safe transactions for legacy RemoteHop and
// RemoteMintRedeemHop setNumDVNs(). The two txs are batched per chain.
contract SetLegacyHopNumDVNsDirect is Script, HopConstants {
    function run() external {
        uint256 numDvns = vm.envOr("NUM_DVNS", uint256(5));
        string memory outputDir = vm.envOr("OUTPUT_DIR", string("src/script/hop/fix/generated/set-num-dvns"));
        LegacyHopTarget storage target = _legacyHopTargetFor(block.chainid);

        vm.createDir(outputDir, true);

        SafeTx[] memory txs = new SafeTx[](2);
        bytes memory data = abi.encodeCall(ILegacyHopNumDVNs.setNumDVNs, (numDvns));

        txs[0] = SafeTx({
            name: string.concat("Set ", target.name, " RemoteHop numDVNs"),
            to: target.remoteHop,
            value: 0,
            data: data
        });

        txs[1] = SafeTx({
            name: string.concat("Set ", target.name, " MintRedeemHop numDVNs"),
            to: target.mintRedeemHop,
            value: 0,
            data: data
        });

        string memory filename = string(
            abi.encodePacked(outputDir, "/", vm.toString(block.chainid), "-LegacyHop-", target.name, ".json")
        );
        new SafeTxHelper().writeTxs(txs, filename);
        console.log("Safe tx JSON written to:", filename);
    }
}

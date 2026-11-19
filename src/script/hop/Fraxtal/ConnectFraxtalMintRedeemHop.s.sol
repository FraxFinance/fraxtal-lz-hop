// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { console } from "forge-std/Script.sol";
import { SafeTxHelper, SafeTx } from "frax-std/SafeTxHelper.sol";

interface IFraxtalMintRedeemHop {
    function setRemoteHop(uint32 _eid, bytes32 _remoteHop) external;
    function remoteHop(uint32 _eid) external view returns (bytes32);
}

/// @notice Generates the Fraxtal Safe batch that registers freshly deployed `RemoteMintRedeemHop`s
///         on `FraxtalMintRedeemHop`. Without this the return leg reverts with `InvalidSourceChain`.
///
/// @dev The batch must be executed by the Fraxtal msig (`FRAXTAL_MSIG`), which owns the hop.
///
/// Usage:
///   REMOTE_EIDS=30380,30416 \
///   REMOTE_HOPS=0x...,0x... \
///   forge script src/script/hop/Fraxtal/ConnectFraxtalMintRedeemHop.s.sol --rpc-url https://rpc.frax.com
contract ConnectFraxtalMintRedeemHop is SafeTxHelper {
    address constant FRAXTAL_MINTREDEEM_HOP = 0x3e6a2cBaFD864e09e6DAb9Cf035a0AbEa32bc0BC;
    address constant FRAXTAL_MSIG = 0x5f25218ed9474b721d6a38c115107428E832fA2E;

    function run() external {
        require(block.chainid == 252, "run against Fraxtal");

        uint256[] memory eids = vm.envUint("REMOTE_EIDS", ",");
        address[] memory hops = vm.envAddress("REMOTE_HOPS", ",");
        require(eids.length == hops.length, "REMOTE_EIDS / REMOTE_HOPS length mismatch");
        require(eids.length > 0, "no remote hops given");

        string memory outputDir = vm.envOr("OUTPUT_DIR", string("src/script/hop/Fraxtal/generated"));
        vm.createDir(outputDir, true);

        // One file per eid set, so batches generated on different branches never share a path.
        string memory filename = string.concat(outputDir, "/252-ConnectMintRedeemHop");
        SafeTx[] memory txs = new SafeTx[](eids.length);
        for (uint256 i = 0; i < eids.length; ++i) {
            uint32 eid = uint32(eids[i]);
            require(hops[i] != address(0), "remote hop is zero");
            require(
                IFraxtalMintRedeemHop(FRAXTAL_MINTREDEEM_HOP).remoteHop(eid) == bytes32(0),
                "remoteHop already set for eid"
            );

            txs[i] = SafeTx({
                name: string.concat("setRemoteHop(", vm.toString(eids[i]), ")"),
                to: FRAXTAL_MINTREDEEM_HOP,
                value: 0,
                data: abi.encodeCall(IFraxtalMintRedeemHop.setRemoteHop, (eid, bytes32(uint256(uint160(hops[i])))))
            });
            console.log("queued setRemoteHop", eids[i], hops[i]);
            filename = string.concat(filename, "-", vm.toString(eids[i]));
        }

        filename = string.concat(filename, ".json");
        writeTxs(txs, filename);
        console.log("Safe tx JSON written to:", filename);
        console.log("Execute from Fraxtal msig:", FRAXTAL_MSIG);
    }
}

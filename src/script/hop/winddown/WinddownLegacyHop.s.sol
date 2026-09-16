// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SafeTxHelper, SafeTx } from "frax-std/SafeTxHelper.sol";
import { HopConstants, LegacyHopTarget } from "src/script/hop/HopConstants.sol";

interface ILegacyHop {
    // shared views
    function owner() external view returns (address);
    function paused() external view returns (bool);
    function approvedOft(address oft) external view returns (bool);
    // RemoteHop views
    function fraxtalHop() external view returns (bytes32);
    function numDVNs() external view returns (uint256);
    function hopFee() external view returns (uint256);
    function executorOptions(uint32 eid) external view returns (bytes memory);
    // FraxtalHop views
    function remoteHop(uint32 eid) external view returns (bytes32);
    // shared admin
    function toggleOFTApproval(address oft, bool approved) external;
    function recoverETH(address recipient, uint256 tokenAmount) external;
    function pause(bool paused) external;
    // RemoteHop admin
    function setExecutorOptions(uint32 eid, bytes memory options) external;
    function setFraxtalHop(bytes32 fraxtalHop) external;
    function setNumDVNs(uint256 numDVNs) external;
    function setHopFee(uint256 hopFee) external;
    // FraxtalHop admin
    function setRemoteHop(uint32 eid, bytes32 remoteHop) external;
}

/// @dev Mirror of an L0Config.json entry - same shape and alphabetical field order as
///      frax-oft-upgradeable/scripts/L0Constants.sol:L0Config (stdJson decodes object
///      keys alphabetically).
struct L0Config {
    string RPC;
    uint256 chainid;
    address delegate;
    address dvnHorizen;
    address dvnL0;
    uint256 eid;
    address endpoint;
    address proxyAdmin;
    address receiveLib302;
    address sendLib302;
}

// Winds down the legacy hop system: RemoteHop on every remote chain and FraxtalHop
// on Fraxtal (RemoteMintRedeemHop / FraxtalMintRedeemHop are intentionally NOT touched).
//
// ONE Safe Transaction Builder JSON batch is generated per chain for the owner msig,
// containing only the steps whose live on-chain state requires them (re-running after
// execution produces an empty batch):
//   1. toggleOFTApproval(oft, false)    for every currently-approved OFT
//   2. setExecutorOptions(eid, "")      for every dstEid with options set (RemoteHop only)
//   3. recoverETH(recipient, balance)   balance snapshot to RECOVER_ETH_RECIPIENT
//   4. setFraxtalHop(bytes32(0))        (RemoteHop only)
//   5. setNumDVNs(0)                    (RemoteHop only)
//   6. setHopFee(0)                     (RemoteHop only)
//   7. pause(true)
//   8. setRemoteHop(srcEid, bytes32(0)) for every srcEid registered (FraxtalHop only)
//
// Every generated transaction is SIMULATED node-side (eth_call with from = the owner
// msig) before the batch is written - frax-oft-upgradeable's simulate-as-delegate idiom
// (BaseL0Script.simulateAndWriteTxs), done via RPC instead of a fork because forge
// cannot fork Monad (NotActivated) or execute EraVM bytecode (ZkSync/Abstract) locally.
//
// ETH recovery: the DEPLOYED hops predate the repo source - recoverETH is transfer()
// (2300-gas stipend, reverts on failure), not the unchecked call in RemoteHop.sol /
// FraxtalHop.sol, so the owner Safe can never be the recipient. Recovery goes to the
// RECOVER_ETH_RECIPIENT EOA (default: Travis, msig member on all chains). The amount is
// an exact generation-time snapshot: RemoteHop balances only grow (hopFee accrual and LZ
// refunds - Berachain accrued 5.38 BERA in the six days after its batch executed), so the
// transfer always succeeds and a stale snapshot UNDER-sweeps rather than reverting; the
// residue is picked up by the RECOVER_ETH_ONLY pass below.
//
// TWO PENDING exact-amount recoverETH txs against the same hop is the one way this breaks:
// whichever executes first drops the balance below the other's hard-coded amount, and that
// second transfer() reverts - taking its whole batch with it. So the residual pass refuses
// any chain whose wind-down batch has not executed yet (see below). FraxtalHop SPENDS its balance
// forwarding in-flight hops, so generate/queue its batch only after all spokes are
// wound down and drained - a stale amount reverts the whole batch loudly at Safe
// simulation, never silently.
//
// EXECUTION ORDER ACROSS CHAINS IS A SAFETY CONSTRAINT: execute all 27 RemoteHop
// batches first, wait for in-flight hops to drain (LayerZeroScan: no pending
// messages/composes to FraxtalHop 0x2A2019b30C157dB6c1C01306b8025167dBe1803B), then
// REGENERATE and execute the Fraxtal batch last. Pausing / clearing the hub makes
// lzCompose revert and V1's setMessageProcessed is broken (abi.encodePacked vs
// abi.encode), so an in-flight compose caught by the hub batch can never be retired.
//
// RECOVER_ETH_ONLY=true builds the residual-sweep pass: the full wind-down batches above
// snapshot each balance at generation time, so hopFee accrued between generation and
// execution stays behind on the hop. This mode re-reads every hop's live balance and emits
// a single-tx batch (recoverETH -> recipient EOA) for the chains that still hold a non-zero
// balance; chains at zero produce no file at all. FraxtalHop (252) is excluded unless it is
// named explicitly in CHAIN_IDS - the hub spends its balance forwarding in-flight hops, so
// an exact-amount snapshot for it is only valid once the spokes are wound down and drained.
//
// RPC urls, chain ids, eids and the msig (`delegate`) come from L0Config.json, copied
// from frax-oft-upgradeable/scripts/L0Config.json (chain 10 + 43114 RPCs replaced with
// working public endpoints - the shipped ones reject eth_call). Legacy hop addresses
// and chain names come from HopConstants.sol.
//
// Usage (one JSON per chain into src/script/hop/winddown/generated):
//   FOUNDRY_PROFILE=script forge script src/script/hop/winddown/WinddownLegacyHop.s.sol \
//       --tc WinddownLegacyHop --ffi -vv
//
// Environment:
//   CHAIN_IDS=1,252                    only generate for these chain ids (default: all)
//   RECOVER_ETH_ONLY=true              emit ONLY recoverETH, and only for hops holding a
//                                      non-zero native balance (see below)
//   RPC_URL_<chainid>=...              override the L0Config RPC for one chain
//   RECOVER_ETH_RECIPIENT=0x...        recoverETH recipient (default: Travis EOA)
//   RECOVER_ETH_RECIPIENT_<chainid>=.. per-chain recipient override
//   OUTPUT_DIR=...                     output directory for the Safe JSON batches
//   STRICT=true                        revert at the end if any chain failed to generate
contract WinddownLegacyHop is Script, HopConstants {
    using stdJson for string;

    uint256 internal constant FRAXTAL_CHAINID = 252;
    string internal constant CONFIG_PATH = "src/script/hop/winddown/L0Config.json";

    L0Config[] internal targetConfigs;
    uint32[] internal candidateEids;

    string[] internal generatedFiles;
    uint256[] internal failedChains;

    function setUp() public virtual {
        loadJsonConfig();
    }

    function run() external {
        bool recoverEthOnly = vm.envOr("RECOVER_ETH_ONLY", false);
        string memory defaultDir = recoverEthOnly
            ? "src/script/hop/winddown/generated/recover-eth"
            : "src/script/hop/winddown/generated";
        string memory outputDir = vm.envOr("OUTPUT_DIR", defaultDir);
        vm.createDir(outputDir, true);

        // Safe JSON `createdAt` is stamped from block.timestamp (no fork => stale default)
        vm.warp(vm.unixTime() / 1000);

        // per-chain work lives in a worker contract so failures (bad RPC, dead chain, ...)
        // can be try/caught - foundry's script execution protection forbids self-calls
        WinddownWorker worker = new WinddownWorker(outputDir, candidateEids, recoverEthOnly);

        uint256[] memory onlyChains = vm.envOr("CHAIN_IDS", ",", new uint256[](0));

        // a CHAIN_IDS typo must surface as a failure, not be silently skipped
        for (uint256 j = 0; j < onlyChains.length; j++) {
            if (!_isTarget(onlyChains[j])) {
                console.log("FAILED chain %s: not a wind-down target (CHAIN_IDS typo?)", onlyChains[j]);
                failedChains.push(onlyChains[j]);
            }
        }

        for (uint256 i = 0; i < targetConfigs.length; i++) {
            L0Config memory config = targetConfigs[i];
            if (onlyChains.length > 0 && !_contains(onlyChains, config.chainid)) continue;

            // the hub's balance moves under it (in-flight forwards) - sweeping it is a
            // deliberate, last step, never part of a blanket residual pass
            if (recoverEthOnly && config.chainid == FRAXTAL_CHAINID && onlyChains.length == 0) {
                console.log("Skipping FraxtalHop (252): pass CHAIN_IDS=252 to sweep the hub");
                continue;
            }

            try worker.windDownChain(config) returns (string memory filename) {
                if (bytes(filename).length > 0) generatedFiles.push(filename);
            } catch Error(string memory reason) {
                console.log("FAILED chain %s: %s", config.chainid, reason);
                failedChains.push(config.chainid);
            } catch (bytes memory) {
                console.log("FAILED chain %s: (low-level revert)", config.chainid);
                failedChains.push(config.chainid);
            }
        }

        console.log("");
        console.log("Generated %s Safe batches:", generatedFiles.length);
        for (uint256 i = 0; i < generatedFiles.length; i++) {
            console.log("  %s", generatedFiles[i]);
        }
        if (failedChains.length > 0) {
            console.log("WARNING: %s chain(s) failed - rerun with CHAIN_IDS set to:", failedChains.length);
            for (uint256 i = 0; i < failedChains.length; i++) {
                console.log("  %s", failedChains[i]);
            }
            if (vm.envOr("STRICT", false)) revert("winddown generation incomplete");
        }
    }

    function loadJsonConfig() public virtual {
        string memory json = vm.readFile(CONFIG_PATH);

        L0Config[] memory legacyConfigs = abi.decode(json.parseRaw(".Legacy"), (L0Config[]));
        L0Config[] memory proxyConfigs = abi.decode(json.parseRaw(".Proxy"), (L0Config[]));

        for (uint256 i = 0; i < legacyConfigs.length; i++) _addConfig(legacyConfigs[i]);
        for (uint256 i = 0; i < proxyConfigs.length; i++) _addConfig(proxyConfigs[i]);

        // Non-EVM entries (Solana/Movement/Aptos) hold non-address fields, so only
        // their eids are read - they are clearing candidates, never wind-down targets.
        for (uint256 i = 0; ; i++) {
            string memory key = string.concat(".Non-EVM[", vm.toString(i), "].eid");
            try vm.parseJsonUint(json, key) returns (uint256 eid) {
                // forge-lint: disable-next-line(unsafe-typecast)
                _addCandidateEid(uint32(eid));
            } catch {
                break;
            }
        }

        require(targetConfigs.length > 0, "no wind-down targets loaded");
    }

    function _addConfig(L0Config memory config) internal {
        // forge-lint: disable-next-line(unsafe-typecast)
        _addCandidateEid(uint32(config.eid));

        // only chains with a legacy hop deployment are wind-down targets
        if (config.chainid != FRAXTAL_CHAINID && !legacyHopTargets[config.chainid].exists) return;

        // chains 1/8453/81457 appear in both the Legacy and Proxy sections
        for (uint256 i = 0; i < targetConfigs.length; i++) {
            if (targetConfigs[i].chainid == config.chainid) {
                require(targetConfigs[i].delegate == config.delegate, "duplicate chainid, conflicting delegate");
                return;
            }
        }
        targetConfigs.push(config);
    }

    function _addCandidateEid(uint32 eid) internal {
        for (uint256 i = 0; i < candidateEids.length; i++) {
            if (candidateEids[i] == eid) return;
        }
        candidateEids.push(eid);
    }

    function _isTarget(uint256 chainid) internal view returns (bool) {
        for (uint256 i = 0; i < targetConfigs.length; i++) {
            if (targetConfigs[i].chainid == chainid) return true;
        }
        return false;
    }

    function _contains(uint256[] memory array, uint256 value) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) return true;
        }
        return false;
    }
}

contract WinddownWorker is Script, HopConstants {
    address internal constant FRAXTAL_HOP = 0x2A2019b30C157dB6c1C01306b8025167dBe1803B;
    uint256 internal constant FRAXTAL_CHAINID = 252;
    /// @dev msig member on all chains; deployed recoverETH is transfer() so the
    ///      recipient must be receivable within the 2300-gas stipend (an EOA)
    address internal constant TRAVIS = 0xcbc616D595D38483e6AdC45C7E426f44bF230928;

    string internal outputDir;
    /// @dev emit only recoverETH, and only where the live balance is non-zero
    bool internal recoverEthOnly;
    // Union of every EID that may key executorOptions (RemoteHop) or remoteHop (FraxtalHop)
    uint32[] internal candidateEids;
    // Union of every OFT the legacy hops may have approved, checked live per chain.
    // Sourced from the per-chain DeployRemoteHop*.sol scripts and DeployFraxtalHop.sol.
    address[] internal candidateOfts;

    // per-chain scratch
    SafeTx[] internal txs;

    constructor(string memory _outputDir, uint32[] memory _candidateEids, bool _recoverEthOnly) {
        outputDir = _outputDir;
        candidateEids = _candidateEids;
        recoverEthOnly = _recoverEthOnly;
        _loadCandidateOfts();
    }

    /// @return filename of the written Safe batch, or "" when there is nothing to wind down
    function windDownChain(L0Config memory config) external returns (string memory filename) {
        delete txs;

        string memory rpc = vm.envOr(string.concat("RPC_URL_", vm.toString(config.chainid)), config.RPC);
        bool isFraxtal = config.chainid == FRAXTAL_CHAINID;

        address hop;
        string memory name;
        if (isFraxtal) {
            hop = FRAXTAL_HOP;
            name = "Fraxtal";
        } else {
            LegacyHopTarget storage target = _legacyHopTargetFor(config.chainid);
            hop = target.remoteHop;
            name = target.name;
        }

        // a swapped/misconfigured RPC would fail-open into an empty "already wound down"
        // batch (shared hop addresses across chains make that realistic) - verify identity
        require(_getChainId(rpc) == config.chainid, "RPC serves a different chain");
        require(_getCode(rpc, hop).length > 0, "no code at hop address");

        address hopOwner = abi.decode(_ethCall(rpc, hop, abi.encodeCall(ILegacyHop.owner, ())), (address));
        console.log("%s %s (chainid %s)", isFraxtal ? "FraxtalHop" : "RemoteHop", name, config.chainid);
        console.log("  hop %s owner %s", hop, hopOwner);
        // the batch is built for the delegate Safe; owner() alone comes from an untrusted
        // RPC, so a mismatch means stale config or a lying node - refuse either way
        require(hopOwner == config.delegate, "hop owner != L0Config delegate");

        if (recoverEthOnly) {
            // A hop that is still unpaused with fraxtalHop set has a wind-down batch sitting
            // in its Safe queue, and that batch already carries its own exact-amount
            // recoverETH. Queueing a second one guarantees whichever lands second reverts.
            if (!isFraxtal && !_isWoundDown(rpc, hop)) {
                console.log("  wind-down batch not executed yet - its own recoverETH covers this hop; skipping");
                return "";
            }

            _buildRecoverEth(rpc, hop, config.chainid, isFraxtal);
            if (txs.length == 0) {
                console.log("  zero native balance - no batch written");
                return "";
            }
            _simulateTxs(rpc, config.delegate);
            vm.chainId(config.chainid);
            filename = string.concat(outputDir, "/", vm.toString(config.chainid), "-RecoverETH-", name, ".json");
            new SafeTxHelper().writeTxs(txs, filename);
            console.log("  1 tx -> %s", filename);
            return filename;
        }

        // 1. revoke previously approved OFTs
        for (uint256 i = 0; i < candidateOfts.length; i++) {
            address oft = candidateOfts[i];
            bool approved = abi.decode(_ethCall(rpc, hop, abi.encodeCall(ILegacyHop.approvedOft, (oft))), (bool));
            if (approved) {
                _pushTx(
                    string.concat("Revoke OFT approval ", vm.toString(oft)),
                    hop,
                    abi.encodeCall(ILegacyHop.toggleOFTApproval, (oft, false))
                );
            }
        }

        if (!isFraxtal) _buildRemoteHopClearExecutorOptions(rpc, hop);

        // 3. recover ETH to the recipient EOA (see header: transfer() semantics)
        _buildRecoverEth(rpc, hop, config.chainid, isFraxtal);

        if (!isFraxtal) _buildRemoteHopClearConfig(rpc, hop);

        // 7. pause
        bool paused = abi.decode(_ethCall(rpc, hop, abi.encodeCall(ILegacyHop.paused, ())), (bool));
        if (!paused) {
            _pushTx("Pause hop", hop, abi.encodeCall(ILegacyHop.pause, (true)));
        }

        if (isFraxtal) _buildFraxtalHopClearRemoteHops(rpc, hop);

        if (txs.length == 0) {
            console.log("  nothing to wind down - no batch written");
            return "";
        }

        // frax-oft-upgradeable simulate-as-delegate idiom, forkless: prove every tx
        // executes from the owner msig before the batch is written
        _simulateTxs(rpc, config.delegate);

        if (isFraxtal) {
            console.log("  EXECUTE LAST: only after all RemoteHop batches ran and LayerZeroScan");
            console.log("  shows no pending messages/composes to FraxtalHop (see header)");
        }

        // SafeTxHelper stamps the batch with block.chainid - no fork is active, so set it
        vm.chainId(config.chainid);
        filename = string.concat(outputDir, "/", vm.toString(config.chainid), "-WinddownLegacyHop-", name, ".json");
        new SafeTxHelper().writeTxs(txs, filename);
        console.log("  %s txs -> %s", txs.length, filename);
    }

    // 2. clear executorOptions for any dstEid where they were set
    function _buildRemoteHopClearExecutorOptions(string memory rpc, address hop) internal {
        for (uint256 i = 0; i < candidateEids.length; i++) {
            uint32 eid = candidateEids[i];
            bytes memory options = abi.decode(
                _ethCall(rpc, hop, abi.encodeCall(ILegacyHop.executorOptions, (eid))),
                (bytes)
            );
            if (options.length > 0) {
                _pushTx(
                    string.concat("Clear executorOptions eid ", vm.toString(eid)),
                    hop,
                    abi.encodeCall(ILegacyHop.setExecutorOptions, (eid, bytes("")))
                );
            }
        }
    }

    /// @dev a RemoteHop is wound down once its batch has run: paused and fraxtalHop cleared
    function _isWoundDown(string memory rpc, address hop) internal returns (bool) {
        bool paused = abi.decode(_ethCall(rpc, hop, abi.encodeCall(ILegacyHop.paused, ())), (bool));
        bytes32 fraxtalHop = abi.decode(_ethCall(rpc, hop, abi.encodeCall(ILegacyHop.fraxtalHop, ())), (bytes32));
        return paused && fraxtalHop == bytes32(0);
    }

    // 3. recover the native balance snapshot
    function _buildRecoverEth(string memory rpc, address hop, uint256 chainid, bool isFraxtal) internal {
        uint256 balance = _getBalance(rpc, hop);
        if (balance == 0) return;

        address recipient = vm.envOr(
            string.concat("RECOVER_ETH_RECIPIENT_", vm.toString(chainid)),
            vm.envOr("RECOVER_ETH_RECIPIENT", TRAVIS)
        );

        console.log("  recovering native balance %s to %s", balance, recipient);
        if (isFraxtal) {
            console.log("  NOTE: FraxtalHop spends its balance on in-flight forwards - regenerate this");
            console.log("  batch right before queueing or the exact-amount recoverETH reverts the batch");
        }
        _pushTx(
            string.concat("Recover ETH to ", vm.toString(recipient)),
            hop,
            abi.encodeCall(ILegacyHop.recoverETH, (recipient, balance))
        );
    }

    // 4-6. clear fraxtalHop, numDVNs, hopFee
    function _buildRemoteHopClearConfig(string memory rpc, address hop) internal {
        bytes32 fraxtalHop = abi.decode(_ethCall(rpc, hop, abi.encodeCall(ILegacyHop.fraxtalHop, ())), (bytes32));
        if (fraxtalHop != bytes32(0)) {
            if (fraxtalHop != bytes32(uint256(uint160(FRAXTAL_HOP)))) {
                console.log("  NOTE: fraxtalHop points to unexpected address");
                console.logBytes32(fraxtalHop);
            }
            _pushTx("Clear fraxtalHop", hop, abi.encodeCall(ILegacyHop.setFraxtalHop, (bytes32(0))));
        }

        uint256 numDVNs = abi.decode(_ethCall(rpc, hop, abi.encodeCall(ILegacyHop.numDVNs, ())), (uint256));
        if (numDVNs != 0) {
            _pushTx("Clear numDVNs", hop, abi.encodeCall(ILegacyHop.setNumDVNs, (0)));
        }

        uint256 hopFee = abi.decode(_ethCall(rpc, hop, abi.encodeCall(ILegacyHop.hopFee, ())), (uint256));
        if (hopFee != 0) {
            _pushTx("Clear hopFee", hop, abi.encodeCall(ILegacyHop.setHopFee, (0)));
        }
    }

    // 8. clear remoteHop for any srcEid where a remote hop is registered
    function _buildFraxtalHopClearRemoteHops(string memory rpc, address hop) internal {
        for (uint256 i = 0; i < candidateEids.length; i++) {
            uint32 eid = candidateEids[i];
            bytes32 remoteHop = abi.decode(
                _ethCall(rpc, hop, abi.encodeCall(ILegacyHop.remoteHop, (eid))),
                (bytes32)
            );
            if (remoteHop != bytes32(0)) {
                _pushTx(
                    string.concat("Clear remoteHop eid ", vm.toString(eid)),
                    hop,
                    abi.encodeCall(ILegacyHop.setRemoteHop, (eid, bytes32(0)))
                );
            }
        }
    }

    function _pushTx(string memory name, address to, bytes memory data) internal {
        txs.push(SafeTx({ name: name, to: to, value: 0, data: data }));
    }

    /// @dev node-side dry-run of every generated tx as the owner msig; a tx that cannot
    ///      execute (diverged deployed bytecode, unreceivable recoverETH recipient, ...)
    ///      fails generation here instead of reverting the signed batch on-chain
    function _simulateTxs(string memory rpc, address delegate) internal {
        for (uint256 i = 0; i < txs.length; i++) {
            string memory params = string.concat(
                '[{"from":"',
                vm.toString(delegate),
                '","to":"',
                vm.toString(txs[i].to),
                '","data":"',
                vm.toString(txs[i].data),
                '"},"latest"]'
            );
            try vm.rpc(rpc, "eth_call", params) {}
            catch {
                revert(string.concat("simulation failed: ", txs[i].name));
            }
        }
    }

    // ----------------------------- RPC helpers -----------------------------

    function _ethCall(string memory rpc, address to, bytes memory data) internal returns (bytes memory result) {
        string memory params = string.concat(
            '[{"to":"',
            vm.toString(to),
            '","data":"',
            vm.toString(data),
            '"},"latest"]'
        );
        result = vm.rpc(rpc, "eth_call", params);
        require(result.length >= 32, "empty eth_call result");
    }

    function _getBalance(string memory rpc, address account) internal returns (uint256) {
        return _quantity(vm.rpc(rpc, "eth_getBalance", string.concat('["', vm.toString(account), '","latest"]')));
    }

    function _getCode(string memory rpc, address account) internal returns (bytes memory) {
        return vm.rpc(rpc, "eth_getCode", string.concat('["', vm.toString(account), '","latest"]'));
    }

    function _getChainId(string memory rpc) internal returns (uint256) {
        return _quantity(vm.rpc(rpc, "eth_chainId", "[]"));
    }

    function _quantity(bytes memory raw) internal pure returns (uint256 value) {
        // quantities come back as big-endian bytes with leading zeros trimmed
        require(raw.length <= 32, "quantity overflow");
        for (uint256 i = 0; i < raw.length; i++) {
            value = (value << 8) | uint8(raw[i]);
        }
    }

    function _loadCandidateOfts() internal {
        // standard proxy OFTs (most chains) - DeployRemoteHop{Arbitrum,...}.sol
        candidateOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // frxUSD
        candidateOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sfrxUSD
        candidateOfts.push(0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050); // frxETH
        candidateOfts.push(0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45); // sfrxETH
        candidateOfts.push(0x64445f0aecC51E94aD52d8AC56b7190e764E561a); // WFRAX
        candidateOfts.push(0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927); // FPI

        // Ethereum lockboxes - DeployRemoteHopEthereum.sol
        candidateOfts.push(0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0); // frxUSD
        candidateOfts.push(0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126); // sfrxUSD
        candidateOfts.push(0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6); // frxETH
        candidateOfts.push(0xbBc424e58ED38dd911309611ae2d7A23014Bd960); // sfrxETH
        candidateOfts.push(0xC6F59a4fD50cAc677B51558489E03138Ac1784EC); // deprecated FXS lockbox
        candidateOfts.push(0x9033BAD7aA130a2466060A2dA71fAe2219781B4b); // FPI
        candidateOfts.push(0x04ACaF8D2865c0714F79da09645C13FD2888977f); // WFRAX (FXS successor)

        // Base - DeployRemoteHopBase.sol
        candidateOfts.push(0xe5020A6d073a794B6E7f05678707dE47986Fb0b6); // frxUSD
        candidateOfts.push(0x91A3f8a8d7a881fBDfcfEcd7A2Dc92a46DCfa14e); // sfrxUSD
        candidateOfts.push(0x7eb8d1E4E2D0C8b9bEDA7a97b305cF49F3eeE8dA); // frxETH
        candidateOfts.push(0x192e0C7Cc9B263D93fa6d472De47bBefe1Fb12bA); // sfrxETH
        candidateOfts.push(0x0CEAC003B0d2479BebeC9f4b2EBAd0a803759bbf); // WFRAX
        candidateOfts.push(0xEEdd3A0DDDF977462A97C1F0eBb89C3fbe8D084B); // FPI

        // Linea - DeployRemoteHopLinea.sol
        candidateOfts.push(0xC7346783f5e645aa998B106Ef9E7f499528673D8); // frxUSD
        candidateOfts.push(0x592a48c0FB9c7f8BF1701cB0136b90DEa2A5B7B6); // sfrxUSD
        candidateOfts.push(0xB1aFD04774c02AE84692619448B08BA79F19b1ff); // frxETH
        candidateOfts.push(0x383Eac7CcaA89684b8277cBabC25BCa8b13B7Aa2); // sfrxETH
        candidateOfts.push(0x5217Ab28ECE654Aab2C68efedb6A22739df6C3D5); // WFRAX
        candidateOfts.push(0xDaF72Aa849d3C4FAA8A9c8c99f240Cf33dA02fc4); // FPI

        // Monad - DeployRemoteHopMonad.sol
        candidateOfts.push(0x58E3ee6accd124642dDB5d3f91928816Be8D8ed3); // frxUSD
        candidateOfts.push(0x137643F7b2C189173867b3391f6629caB46F0F1a); // sfrxUSD
        candidateOfts.push(0x288F9D76019469bfEb56BB77d86aFa2bF563B75B); // frxETH
        candidateOfts.push(0x3B4cf37A3335F21c945a40088404c715525fCb29); // sfrxETH
        candidateOfts.push(0x29aCC7c504665A5EA95344796f784095f0cfcC58); // WFRAX
        candidateOfts.push(0xBa554F7A47f0792b9fa41A1256d4cf628Bb1D028); // FPI

        // Scroll - DeployRemoteHopScroll.sol
        candidateOfts.push(0x397F939C3b91A74C321ea7129396492bA9Cdce82); // frxUSD
        candidateOfts.push(0xC6B2BE25d65760B826D0C852FD35F364250619c2); // sfrxUSD
        candidateOfts.push(0x0097Cf8Ee15800d4f80da8A6cE4dF360D9449Ed5); // frxETH
        candidateOfts.push(0x73382eb28F35d80Df8C3fe04A3EED71b1aFce5dE); // sfrxETH
        candidateOfts.push(0x879BA0EFE1AB0119FefA745A21585Fa205B07907); // WFRAX
        candidateOfts.push(0x93cDc5d29293Cb6983f059Fec6e4FFEb656b6a62); // FPI

        // ZkSync / Abstract - DeployRemoteHop{ZkSync,Abstract}.sol
        candidateOfts.push(0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d); // frxUSD
        candidateOfts.push(0x9F87fbb47C33Cd0614E43500b9511018116F79eE); // sfrxUSD
        candidateOfts.push(0xc7Ab797019156b543B7a3fBF5A99ECDab9eb4440); // frxETH
        candidateOfts.push(0xFD78FD3667DeF2F1097Ed221ec503AE477155394); // sfrxETH
        candidateOfts.push(0xAf01aE13Fb67AD2bb2D76f29A83961069a5F245F); // WFRAX
        candidateOfts.push(0x580F2ee1476eDF4B1760bd68f6AaBaD57dec420E); // FPI

        // Fraxtal lockboxes - DeployFraxtalHop.sol
        candidateOfts.push(0x96A394058E2b84A89bac9667B19661Ed003cF5D4); // frxUSD
        candidateOfts.push(0x88Aa7854D3b2dAA5e37E7Ce73A1F39669623a361); // sfrxUSD
        candidateOfts.push(0x9aBFE1F8a999B0011ecD6116649AEe8D575F5604); // frxETH
        candidateOfts.push(0x999dfAbe3b1cc2EF66eB032Eea42FeA329bBa168); // sfrxETH
        candidateOfts.push(0xd86fBBd0c8715d2C1f40e451e5C3514e65E7576A); // FXS
        candidateOfts.push(0x75c38D46001b0F8108c4136216bd2694982C20FC); // FPI
    }
}

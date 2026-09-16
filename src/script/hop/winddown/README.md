# Legacy Hop Wind-Down

Generate Safe transaction batches to retire the legacy (V1) Frax LayerZero Hop system.

## Architecture

- **Data source:** `L0Config.json` (chains, RPCs, msigs, EIDs)
- **Generation:** `WinddownLegacyHop.s.sol` (Solidity script, reads L0Config, emits Safe batches)
- **Dependencies:** `HopConstants.sol` (RemoteHop addresses from the codebase)
- **Orchestration:** `run.sh` (minimal shell wrapper)

## Usage

```bash
./run.sh
```

Output: One Safe transaction batch JSON per chain in `generated/` directory.

### ETH recovery only

```bash
RECOVER_ETH_ONLY=true forge script WinddownLegacyHop.s.sol --tc WinddownLegacyHop --ffi -vv
```

Emits a single-tx `recoverETH(recipient, liveBalance)` batch into `generated/recover-eth/`,
**only** for hops whose native balance is currently non-zero — chains at zero produce no
file. Use this to sweep residual gas after the main batches, or standalone. FraxtalHop (252)
is excluded unless named in `CHAIN_IDS`: the hub spends its balance forwarding in-flight
hops, so an exact-amount snapshot is only valid once the spokes are drained.

## Environment

- `CHAIN_IDS=1,252` — Generate only for specific chain IDs (default: all)
- `RECOVER_ETH_ONLY=true` — Only emit recoverETH, only for non-zero balances
- `OUTPUT_DIR=...` — Output directory (default: `generated/`)
- `RECOVER_ETH_RECIPIENT=0x...` — ETH recovery recipient (default: Travis EOA)
- `RECOVER_ETH_RECIPIENT_<chainid>=...` — Per-chain override
- `RPC_URL_<chainid>=...` — Override L0Config RPC for one chain
- `STRICT=true` — Revert if any chain fails

## Files

| File | Purpose |
|------|---------|
| `WinddownLegacyHop.s.sol` | Solidity script: reads L0Config, emits Safe batches |
| `L0Config.json` | Single source of truth: RPC URLs, chain IDs, EIDs, msig addresses |
| `run.sh` | Minimal shell wrapper: runs Solidity script with `--ffi` |
| `generated/` | Output: Safe batch JSONs (one per chain) |

## Notes

- **Idempotent:** Re-running after execution produces empty batches (state-driven)
- **Forkless:** Uses `vm.rpc()` to read state, works on all chains including EraVM
- **Simulation:** Every transaction is simulated node-side before batch creation
- **Order matters:** Execute all RemoteHops first, then Fraxtal hub last (depends on drain window)

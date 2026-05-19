## Relay Smoke Tests

This directory contains two scripts that implement a chained relay round-trip across supported chains. One script executes a single step, and the shell runner sequences steps with confirmation pauses.

### TestRemoteHop.s.sol

File: `src/script/hop/TestRemoteHop.s.sol`

Sends all 6 Frax OFT assets (`frxUSD`, `sfrxUSD`, `frxETH`, `sfrxETH`, `WFRAX`, `FPI`) from the deployer EOA on the current chain to the deployer EOA on the destination chain, using RemoteHop v1.

Test amount: `1e13`

#### Required env vars

| Variable | Description |
| --- | --- |
| `PK` | Deployer private key (must hold source-chain OFTs) |
| `DST_EID` | Destination LayerZero EID |

#### Per-OFT execution flow

1. `IERC20(token).approve(hopAddress, TEST_AMOUNT)`
2. `hop.sendOFT{value: fee.nativeFee}(oft, dstEid, deployerB32, TEST_AMOUNT)`

Fraxtal uses `FraxtalHop` at `0x2A2019b30C157dB6c1C01306b8025167dBe1803B`.
Spoke chains use their chain-specific `RemoteHop` address.

Note: On Fraxtal, `IOFT.token()` returns the lockbox underlying ERC20; approve that token.

#### Example

```bash
# Fraxtal -> Arbitrum
PK=$PK DST_EID=30110 \
  forge script src/script/hop/TestRemoteHop.s.sol \
  --rpc-url https://rpc.frax.com --broadcast

# Arbitrum -> Base
PK=$PK DST_EID=30184 \
  forge script src/script/hop/TestRemoteHop.s.sol \
  --rpc-url https://arb1.arbitrum.io/rpc --broadcast

# ZkSync
PK=$PK DST_EID=30324 \
  forge script src/script/hop/TestRemoteHop.s.sol \
  --rpc-url https://mainnet.era.zksync.io --broadcast --zksync
```

### test_remote_hop.sh

File: `src/script/hop/test_remote_hop.sh`

Runs a full round-trip sequence and pauses between hops for verification.

#### Usage

```bash
# Full run
bash src/script/hop/test_remote_hop.sh

# Resume from step index
START_STEP=3 bash src/script/hop/test_remote_hop.sh
```

#### Optional env vars

| Variable | Default | Description |
| --- | --- | --- |
| `DRY_RUN` | unset | Set `1` to skip broadcast |
| `START_STEP` | `0` | Start from step index |
| `CONFIRM` | interactive | Set `auto` to skip prompts |
| `RPC_<CHAIN>` | public RPC | Override chain RPC |

#### Notes

- Script prompts between hops to allow LZ delivery checks.
- ZkSync/Abstract steps are handled with `--zksync`.

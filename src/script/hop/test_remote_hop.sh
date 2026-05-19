#!/usr/bin/env bash
# =============================================================================
# test_remote_hop.sh — RemoteHop v1 chained relay smoke test
# =============================================================================
#
# Sends all 6 FraxOFTs through every chain in a round-trip relay using
# RemoteHop v1 (fraxtal-lz-hop):
#
#   Fraxtal(252) → Arbitrum(42161) → Base(8453) → Optimism(10) → BSC(56) →
#   Unichain(130) → Sonic(146) → Worldchain(480) → ZkSync(324) → Abstract(2741) →
#   Mode(34443) → Ink(57073) → Linea(59144) → Scroll(534352) → XLayer(196) →
#   Avalanche(43114) → Berachain(80094) → Sei(1329) → Aurora(1313161554) →
#   Polygon(137) → Monad(143) → Plume(98866) →
#   Katana(747474) → Hyperliquid(999) → Ethereum(1) → Fraxtal(252)
#
# SETUP:
#   export PK=<deployer-private-key-hex>
#   Fund the deployer EOA on Fraxtal with each of the 6 OFTs
#   (>= 0.00001 ether = 1e13 per OFT x 25 steps = 2.5e14 per OFT total).
#
# USAGE (from fraxtal-lz-hop project root):
#   bash src/script/hop/test_remote_hop.sh
#   # or to skip to a specific step:
#   START_STEP=3 bash src/script/hop/test_remote_hop.sh
#
# OPTIONAL ENV OVERRIDES:
#   DRY_RUN=1       — omit --broadcast (simulate only)
#   START_STEP=N    — skip to step N (0-indexed)
#   CONFIRM=auto    — skip interactive confirmation between steps
# =============================================================================

set -euo pipefail

# ── RPC URLs ─────────────────────────────────────────────────────────────────
RPC_FRAXTAL="${RPC_FRAXTAL:-https://rpc.frax.com}"
RPC_ARBITRUM="${RPC_ARBITRUM:-https://arb1.arbitrum.io/rpc}"
RPC_BASE="${RPC_BASE:-https://mainnet.base.org}"
RPC_OPTIMISM="${RPC_OPTIMISM:-https://mainnet.optimism.io}"
RPC_BSC="${RPC_BSC:-https://bsc-dataseed.binance.org}"
RPC_UNICHAIN="${RPC_UNICHAIN:-https://mainnet.unichain.org}"
RPC_SONIC="${RPC_SONIC:-https://rpc.soniclabs.com}"
RPC_WORLDCHAIN="${RPC_WORLDCHAIN:-https://worldchain-mainnet.g.alchemy.com/public}"
RPC_ZKSYNC="${RPC_ZKSYNC:-https://mainnet.era.zksync.io}"
RPC_ABSTRACT="${RPC_ABSTRACT:-https://api.mainnet.abs.xyz}"
RPC_MODE="${RPC_MODE:-https://mainnet.mode.network}"
RPC_INK="${RPC_INK:-https://rpc-gel.inkonchain.com}"
RPC_LINEA="${RPC_LINEA:-https://rpc.linea.build}"
RPC_SCROLL="${RPC_SCROLL:-https://rpc.scroll.io}"
RPC_XLAYER="${RPC_XLAYER:-https://rpc.xlayer.tech}"
RPC_AVALANCHE="${RPC_AVALANCHE:-https://api.avax.network/ext/bc/C/rpc}"
RPC_BERACHAIN="${RPC_BERACHAIN:-https://rpc.berachain.com}"
RPC_SEI="${RPC_SEI:-https://evm-rpc.sei-apis.com}"
RPC_AURORA="${RPC_AURORA:-https://mainnet.aurora.dev}"
RPC_POLYGON="${RPC_POLYGON:-https://polygon-rpc.com}"
RPC_MONAD="${RPC_MONAD:-https://rpc.monad.xyz}"
RPC_PLUME="${RPC_PLUME:-https://rpc.plume.org}"
RPC_KATANA="${RPC_KATANA:-https://rpc.katanarpc.com}"
RPC_HYPERLIQUID="${RPC_HYPERLIQUID:-https://rpc.hyperliquid.xyz/evm}"
RPC_ETHEREUM="${RPC_ETHEREUM:-https://eth.llamarpc.com}"

# ── Relay sequence ────────────────────────────────────────────────────────────
# Each entry: "SRC_NAME|SRC_CHAIN_ID|SRC_RPC|DST_NAME|DST_CHAIN_ID|DST_EID|DST_RPC"
STEPS=(
  "Fraxtal|252|${RPC_FRAXTAL}|Arbitrum|42161|30110|${RPC_ARBITRUM}"
  "Arbitrum|42161|${RPC_ARBITRUM}|Base|8453|30184|${RPC_BASE}"
  "Base|8453|${RPC_BASE}|Optimism|10|30111|${RPC_OPTIMISM}"
  "Optimism|10|${RPC_OPTIMISM}|BSC|56|30102|${RPC_BSC}"
  "BSC|56|${RPC_BSC}|Unichain|130|30320|${RPC_UNICHAIN}"
  "Unichain|130|${RPC_UNICHAIN}|Sonic|146|30332|${RPC_SONIC}"
  "Sonic|146|${RPC_SONIC}|Worldchain|480|30319|${RPC_WORLDCHAIN}"
  "Worldchain|480|${RPC_WORLDCHAIN}|ZkSync|324|30165|${RPC_ZKSYNC}"
  "ZkSync|324|${RPC_ZKSYNC}|Abstract|2741|30324|${RPC_ABSTRACT}"
  "Abstract|2741|${RPC_ABSTRACT}|Mode|34443|30260|${RPC_MODE}"
  "Mode|34443|${RPC_MODE}|Ink|57073|30339|${RPC_INK}"
  "Ink|57073|${RPC_INK}|Linea|59144|30183|${RPC_LINEA}"
  "Linea|59144|${RPC_LINEA}|Scroll|534352|30214|${RPC_SCROLL}"
  "Scroll|534352|${RPC_SCROLL}|XLayer|196|30274|${RPC_XLAYER}"
  "XLayer|196|${RPC_XLAYER}|Avalanche|43114|30106|${RPC_AVALANCHE}"
  "Avalanche|43114|${RPC_AVALANCHE}|Berachain|80094|30362|${RPC_BERACHAIN}"
  "Berachain|80094|${RPC_BERACHAIN}|Sei|1329|30280|${RPC_SEI}"
  "Sei|1329|${RPC_SEI}|Aurora|1313161554|30211|${RPC_AURORA}"
  "Aurora|1313161554|${RPC_AURORA}|Polygon|137|30109|${RPC_POLYGON}"
  "Polygon|137|${RPC_POLYGON}|Monad|143|30390|${RPC_MONAD}"
  "Monad|143|${RPC_MONAD}|Plume|98866|30370|${RPC_PLUME}"
  "Plume|98866|${RPC_PLUME}|Katana|747474|30375|${RPC_KATANA}"
  "Katana|747474|${RPC_KATANA}|Hyperliquid|999|30367|${RPC_HYPERLIQUID}"
  "Hyperliquid|999|${RPC_HYPERLIQUID}|Ethereum|1|30101|${RPC_ETHEREUM}"
  "Ethereum|1|${RPC_ETHEREUM}|Fraxtal|252|30255|${RPC_FRAXTAL}"
)

TOTAL=${#STEPS[@]}
START_STEP="${START_STEP:-0}"
DRY_RUN="${DRY_RUN:-}"
CONFIRM="${CONFIRM:-}"
SCRIPT="src/script/hop/TestRemoteHop.s.sol"

# ── Helpers ───────────────────────────────────────────────────────────────────
log_step() { echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  STEP $1/$TOTAL  $2"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
pause_for_lz() {
  local dst_name="$1"
  if [[ "${CONFIRM}" == "auto" ]]; then
    echo "[auto] Skipping confirmation — assuming tokens arrived on ${dst_name}"
    return
  fi
  echo ""
  echo "⏳  Waiting for LayerZero delivery to ${dst_name}."
  echo "    Check the destination wallet balance, then press Enter to continue."
  read -r -p "    Press Enter when ready... "
}

# ── Preflight ─────────────────────────────────────────────────────────────────
if [[ -z "${PK:-}" ]]; then
  echo "ERROR: PK env var not set (deployer private key)"
  exit 1
fi

BROADCAST_FLAG="--broadcast"
[[ -n "${DRY_RUN}" ]] && BROADCAST_FLAG="" && echo "[DRY_RUN mode — no broadcast]"

echo "RemoteHop v1 chained relay smoke test"
echo "Total steps : ${TOTAL}"
echo "Start step  : ${START_STEP}"
echo "DRY_RUN     : ${DRY_RUN:-no}"
echo ""

# ── Main loop ─────────────────────────────────────────────────────────────────
for ((i=START_STEP; i<TOTAL; i++)); do
  IFS='|' read -r SRC_NAME SRC_CHAIN_ID SRC_RPC DST_NAME DST_CHAIN_ID DST_EID DST_RPC <<< "${STEPS[$i]}"

  STEP_NUM=$((i+1))
  log_step "${STEP_NUM}" "${SRC_NAME}(${SRC_CHAIN_ID}) → ${DST_NAME}(${DST_CHAIN_ID})  [EID ${DST_EID}]"

  echo "  Forge script: ${SCRIPT}"
  echo "  RPC: ${SRC_RPC}"
  echo ""

  PK="${PK}" \
  DST_EID="${DST_EID}" \
  forge script "${SCRIPT}" \
    --rpc-url "${SRC_RPC}" \
    --evm-version shanghai \
    ${BROADCAST_FLAG} \
    -vvv

  if [[ $i -lt $((TOTAL-1)) ]]; then
    pause_for_lz "${DST_NAME}"
  fi
done

echo ""
echo "✓ All ${TOTAL} relay steps submitted."
echo "  Final destination: Fraxtal — verify deployer EOA balances for all 6 OFTs."

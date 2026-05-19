#!/usr/bin/env bash
# =============================================================================
# zksync_send.sh — Manual ZkSync/Abstract relay step via RemoteHop v1
# =============================================================================
# Bypasses `forge script --zksync` (which aborts in EraVM simulation with
# "Account validation error: Not enough balance for fee + value" even when the
# EOA is well-funded). Instead, calls RemoteHop.sendOFT(...) on the spoke chain
# directly with `cast send --zksync`, routing each OFT through the hop:
#   ZkSync/Abstract → Fraxtal → DST_EID
#
# USAGE:
#   PK=<hex> DST_EID=<lz-eid> RPC=<rpc-url> bash src/script/hop/zksync_send.sh
#
# Examples:
#   # ZkSync(324) → Abstract(2741)   — routes via Fraxtal
#   PK=$PK DST_EID=30324 RPC=https://mainnet.era.zksync.io \
#     bash src/script/hop/zksync_send.sh
#
#   # Abstract(2741) → Mode(34443)   — routes via Fraxtal
#   PK=$PK DST_EID=30260 RPC=https://api.mainnet.abs.xyz \
#     bash src/script/hop/zksync_send.sh
# =============================================================================

set -euo pipefail

: "${PK:?PK env var required}"
: "${DST_EID:?DST_EID env var required}"
RPC="${RPC:-https://mainnet.era.zksync.io}"
AMOUNT="${AMOUNT:-10000000000000}"   # 1e13

CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
echo "Chain ID: $CHAIN_ID"

# RemoteHop v1 (same address on ZkSync and Abstract)
case "$CHAIN_ID" in
  324)  HOP=0xc5e4A0cfef8D801278927C25fB51C1DB7b69dDFb ;;  # ZkSync
  2741) HOP=0xc5e4A0cfef8D801278927C25fB51C1DB7b69dDFb ;;  # Abstract
  *)    echo "ERROR: this script is only for ZkSync (324) or Abstract (2741)"; exit 1 ;;
esac
echo "Hop: $HOP"

DEPLOYER=$(cast wallet address --private-key "$PK")
TO_BYTES32=$(printf "0x000000000000000000000000%s\n" "${DEPLOYER#0x}" | tr 'A-F' 'a-f')
echo "Deployer: $DEPLOYER"
echo "To (bytes32): $TO_BYTES32"
echo "DST_EID: $DST_EID  Amount: $AMOUNT"

# OFT adapters on ZkSync/Abstract (same on both)
OFTS=(
  0xEa77c590Bb36c43ef7139cE649cFBCFD6163170d   # frxUSD
  0x9F87fbb47C33Cd0614E43500b9511018116F79eE   # sfrxUSD
  0xc7Ab797019156b543B7a3fBF5A99ECDab9eb4440   # frxETH
  0xFD78FD3667DeF2F1097Ed221ec503AE477155394   # sfrxETH
  0xAf01aE13Fb67AD2bb2D76f29A83961069a5F245F   # WFRAX
  0x580F2ee1476eDF4B1760bd68f6AaBaD57dec420E   # FPI
)
NAMES=(frxUSD sfrxUSD frxETH sfrxETH WFRAX FPI)

# RemoteHop v1 ABI:
#   quote(address oft, uint32 dstEid, bytes32 to, uint256 amountLD)
#       returns (MessagingFee{uint256 nativeFee, uint256 lzTokenFee})
#   sendOFT(address oft, uint32 dstEid, bytes32 to, uint256 amountLD)
QUOTE_FN='quote(address,uint32,bytes32,uint256)((uint256,uint256))'
SEND_FN='sendOFT(address,uint32,bytes32,uint256)'

for i in "${!OFTS[@]}"; do
  OFT="${OFTS[$i]}"
  NAME="${NAMES[$i]}"
  echo ""
  echo "─── ($((i+1))/6) ${NAME} (${OFT}) ───"

  # Resolve underlying token (RemoteHop pulls from msg.sender via SafeERC20)
  TOKEN=$(cast call "$OFT" "token()(address)" --rpc-url "$RPC")
  echo "Token: $TOKEN"

  # Quote LayerZero fee via the hop
  FEE_TUPLE=$(cast call "$HOP" "$QUOTE_FN" "$OFT" "$DST_EID" "$TO_BYTES32" "$AMOUNT" --rpc-url "$RPC")
  # parse "(nativeFee [scientific], lzTokenFee [scientific])" — strip [..] suffix
  NATIVE_FEE=$(echo "$FEE_TUPLE" | tr -d '()' | cut -d',' -f1 | sed 's/\[.*\]//' | xargs)
  echo "Native fee: $NATIVE_FEE wei"

  # Approve the hop to pull the token
  echo "Approving $HOP to spend $AMOUNT of $TOKEN…"
  cast send "$TOKEN" "approve(address,uint256)" "$HOP" "$AMOUNT" \
    --private-key "$PK" --rpc-url "$RPC" --zksync >/dev/null

  # Call RemoteHop.sendOFT — routes via Fraxtal hop
  echo "Calling RemoteHop.sendOFT…"
  cast send "$HOP" "$SEND_FN" "$OFT" "$DST_EID" "$TO_BYTES32" "$AMOUNT" \
    --value "$NATIVE_FEE" \
    --private-key "$PK" --rpc-url "$RPC" --zksync
done

echo ""
echo "✓ All 6 OFTs sent from chain $CHAIN_ID via hop $HOP to EID $DST_EID"

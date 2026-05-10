#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OUTPUT_DIR="src/script/hop/fix/generated/set-num-dvns"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120s}"
NUM_DVNS="${NUM_DVNS:-5}"
BLOCK_TIMESTAMP="${BLOCK_TIMESTAMP:-$(date +%s)}"
START_CHAIN="${START_CHAIN:-}"
START_CHAIN_SEEN=0

usage() {
  echo "Usage: $0 [fresh]"
  echo
  echo "Generate direct local Safe JSON batches for legacy Hop setNumDVNs(${NUM_DVNS}) into ${OUTPUT_DIR}."
  echo
  echo "Environment:"
  echo "  NUM_DVNS=5                 target numDVNs"
  echo "  BLOCK_TIMESTAMP=...        block timestamp used for Safe JSON createdAt"
  echo "  START_CHAIN=10             skip earlier chains and resume generation at this chain id"
  echo "  TIMEOUT_SECONDS=120s       per-forge-script timeout"
  echo
  echo "  fresh                      remove generated JSON from ${OUTPUT_DIR} before regenerating"
}

mkdir -p "${OUTPUT_DIR}"

case "${1:-}" in
  "")
    ;;
  "fresh")
    echo "Removing stale Safe JSON from ${OUTPUT_DIR}"
    find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "*.json" -delete
    ;;
  "-h"|"--help")
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

should_run_chain() {
  local chain_id="$1"

  if [[ -z "${START_CHAIN}" || "${START_CHAIN_SEEN}" == "1" ]]; then
    return 0
  fi

  if [[ "${chain_id}" == "${START_CHAIN}" ]]; then
    START_CHAIN_SEEN=1
    return 0
  fi

  return 1
}

run_legacy_chain() {
  local chain_id="$1"

  if ! should_run_chain "${chain_id}"; then
    return 0
  fi

  echo "SetLegacyHopNumDVNsDirect: ${chain_id}"
  find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "${chain_id}-LegacyHop-*.json" -delete

  OUTPUT_DIR="${OUTPUT_DIR}" \
  NUM_DVNS="${NUM_DVNS}" \
  FOUNDRY_PROFILE=script \
  RUST_LOG=error \
  timeout "${TIMEOUT_SECONDS}" \
    forge script src/script/hop/fix/SetLegacyHopNumDVNsDirect.s.sol \
      --chain "${chain_id}" \
      --block-timestamp "${BLOCK_TIMESTAMP}" \
      --ffi \
      --quiet \
      --disable-labels
}

CHAIN_IDS=(
  1
  10
  56
  130
  137
  143
  146
  196
  324
  480
  988
  999
  1101
  1329
  2741
  8453
  34443
  42161
  43114
  57073
  59144
  747474
  80094
  81457
  98866
  534352
  1313161554
)

for chain_id in "${CHAIN_IDS[@]}"; do
  run_legacy_chain "${chain_id}"
done

if [[ -n "${START_CHAIN}" && "${START_CHAIN_SEEN}" == "0" ]]; then
  echo "START_CHAIN ${START_CHAIN} was not found" >&2
  exit 1
fi

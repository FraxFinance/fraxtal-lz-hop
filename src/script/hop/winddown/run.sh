#!/bin/bash
# Minimal winddown script - generates Safe batches for legacy hop retirement
# Data source: L0Config.json (chains, RPCs, msigs)
# Generation: WinddownLegacyHop.s.sol (reads L0Config, emits txs)

set -e

cd "$(dirname "$0")"

echo "Generating legacy hop wind-down Safe batches..."
echo "  Script: WinddownLegacyHop.s.sol"
echo "  Config: L0Config.json"
echo "  Output: generated/"

forge script WinddownLegacyHop.s.sol --ffi

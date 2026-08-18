#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TARGET_ROOT="${ROOT}/target"

cargo build \
  --manifest-path "${ROOT}/Cargo.toml" \
  --target wasm32-unknown-unknown \
  --release

mkdir -p "${ROOT}/petal/solana-driver"
for route in transfer.stage.json transfer.assemble.json; do
  wasm-tools component new \
    "${TARGET_ROOT}/wasm32-unknown-unknown/release/bloom_solana_driver_petal.wasm" \
    -o "${ROOT}/petal/solana-driver/${route}.wasm"
  wasm-tools validate "${ROOT}/petal/solana-driver/${route}.wasm"
done

echo "built ${ROOT}/petal/solana-driver/{transfer.stage,transfer.assemble}.json.wasm"

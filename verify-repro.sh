#!/usr/bin/env bash
# Hermetic reproduction check for the solana-driver Petal package.
#
# Verifies that the committed, content-addressed metadata can be reproduced
# exactly: tool versions and build-input digests must match
# artifacts/reproducibility.json, and a rebuild in a fresh CARGO_TARGET_DIR
# from the committed git state must reproduce the committed
# artifacts/build-manifest.json (source_package_hash and every route
# artifact digest).
#
# Self-contained: uses scripts/package-hash (a native helper that mirrors
# bloom-petals' package hashing) — no dependency on the bloom workspace.
#
# No destructive operations: all scratch state lands in a mktemp directory.
set -euo pipefail

petal_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/solana-driver-repro.XXXXXX")"
trap 'true' EXIT

fail() { echo "repro FAILED: $*" >&2; exit 1; }

echo "==> toolchain assertions"
rustc_actual="$(rustc --version)"
wasm_tools_actual="$(wasm-tools --version)"
python3 - "$petal_root/artifacts/reproducibility.json" "$rustc_actual" "$wasm_tools_actual" <<'PY'
import json, sys, hashlib, os
meta = json.load(open(sys.argv[1]))
rustc, wasm_tools = sys.argv[2], sys.argv[3]
if meta["toolchain"]["rustc"] != rustc:
    sys.exit(f"rustc mismatch: recorded {meta['toolchain']['rustc']!r}, actual {rustc!r}")
if not wasm_tools.startswith(meta["toolchain"]["wasm-tools"]):
    sys.exit(f"wasm-tools mismatch: recorded {meta['toolchain']['wasm-tools']!r}, actual {wasm_tools!r}")
base = os.path.dirname(os.path.dirname(sys.argv[1]))  # repo root (artifacts/..)
for rel, want in sorted(meta["inputs"].items()):
    path = os.path.join(base, rel)
    try:
        got = hashlib.sha256(open(path, "rb").read()).hexdigest()
    except FileNotFoundError:
        sys.exit(f"input missing: {rel}")
    if got != want:
        sys.exit(f"input digest mismatch for {rel}: recorded {want}, actual {got}")
print("input digests ok")
PY
[ $? -eq 0 ] || fail "toolchain/input assertions"

echo "==> extracting committed tree"
git -C "$petal_root" archive HEAD | tar -x -C "$scratch"
extracted="$scratch"
[ -d "$extracted" ] || fail "archive extraction"

echo "==> rebuilding components in a fresh CARGO_TARGET_DIR"
(
  cd "$extracted"
  CARGO_TARGET_DIR="$scratch/target" \
    cargo build --locked --manifest-path Cargo.toml \
      --target wasm32-unknown-unknown --release --quiet
  mkdir -p petal/solana-driver
  for route in transfer.stage.json transfer.assemble.json; do
    wasm-tools component new \
      "$scratch/target/wasm32-unknown-unknown/release/bloom_solana_driver_petal.wasm" \
      -o "petal/solana-driver/${route}.wasm"
  done
)

echo "==> recomputing package digests"
helper="cargo run --quiet --manifest-path $extracted/scripts/package-hash/Cargo.toml --"
rebuilt_source="$($helper source "$extracted")"
committed_source="$(python3 -c "import json; print(json.load(open('$petal_root/artifacts/build-manifest.json'))['source_package_hash'])")"
if [ "$rebuilt_source" != "$committed_source" ]; then
  echo "route hashes (rebuilt):"
  for route in transfer.assemble.json transfer.stage.json; do
    echo "  $route: $($helper hash "$extracted/petal/solana-driver/$route.wasm")"
  done
  echo "extracted files:"
  ( cd "$extracted" && find . -type f -not -path '*/target/*' | sort | while read -r f; do
      echo "  $($helper sha256 "$f")  $f"
    done )
  fail "source_package_hash: rebuilt $rebuilt_source != committed $committed_source"
fi

for route in transfer.assemble.json transfer.stage.json; do
  rebuilt_hash="$($helper hash "$extracted/petal/solana-driver/$route.wasm")"
  committed_hash="$(python3 -c "
import json
m = json.load(open('$petal_root/artifacts/build-manifest.json'))
print([r['artifact_hash'] for r in m['routes'] if r['pattern'] == '$route'][0])
")"
  [ "$rebuilt_hash" = "$committed_hash" ] \
    || fail "route $route: rebuilt $rebuilt_hash != committed $committed_hash"
done

echo "repro OK: committed solana-driver artifacts are byte-identical to a fresh, toolchain-pinned rebuild"

#!/usr/bin/env bash
# Publishes a GitHub release for bloom-petal-solana with the built package
# artifacts. The release carries the built .wasm components and the pinning
# metadata; the repository itself never commits built .wasm files.
#
# Usage: TAG=v0.1.0 bash scripts/create-release.sh
# Requires `gh` authenticated to bloom-directory.
set -euo pipefail

REPO="bloom-directory/bloom-petal-solana"
TAG="${TAG:?set TAG, e.g. TAG=v0.1.0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/solana-driver-release.XXXXXX")"

echo "==> building package artifacts"
"${ROOT}/scripts/build.sh"

echo "==> computing digests"
source_package_hash="$(cd "$ROOT" && cargo run --quiet --manifest-path scripts/package-hash/Cargo.toml -- source "$ROOT")"
route_digest="$(cd "$ROOT" && cargo run --quiet --manifest-path scripts/package-hash/Cargo.toml -- hash "$ROOT/petal/solana-driver/transfer.stage.json.wasm")"

echo "==> staging release payload"
mkdir -p "$STAGING/pkg"
# The package tarball: source + built route components + pinning manifests.
tar -czf "$STAGING/bloom-petal-solana-${TAG}.tar.gz" \
  --exclude='.git' --exclude='target' --exclude='*/target' --exclude='test-ledger' \
  -C "$ROOT" .

cp "$ROOT/artifacts/build-manifest.json" "$STAGING/build-manifest.json"
cp "$ROOT/artifacts/reproducibility.json" "$STAGING/reproducibility.json"
cp "$ROOT/artifacts/verifier-corpus.json" "$STAGING/verifier-corpus.json"

cat > "$STAGING/release-notes.md" <<EOF
## solana driver petal ${TAG}

Verified native SOL transfer driver: constructs legacy single-signer System
Program transfers through Machine-mediated chain reads; never signs or
broadcasts itself.

- **source_package_hash** (blake3): \`${source_package_hash}\`
- **route artifact digest** (blake3): \`${route_digest}\`
- **reproducibility digest** (sha256): \`$(sha256sum "$ROOT/artifacts/reproducibility.json" | cut -d' ' -f1)\`
EOF

echo "==> creating release $TAG"
gh release create "$TAG" \
  --repo "$REPO" \
  --title "$TAG" \
  --notes-file "$STAGING/release-notes.md" \
  "$STAGING/bloom-petal-solana-${TAG}.tar.gz" \
  "$STAGING/build-manifest.json" \
  "$STAGING/reproducibility.json" \
  "$STAGING/verifier-corpus.json"

echo "release $TAG published: https://github.com/$REPO/releases/tag/$TAG"
echo "source_package_hash=$source_package_hash"
echo "route_digest=$route_digest"

#!/usr/bin/env bash
# Publishes a GitHub release for bloom-petal-solana with the built package
# artifacts. The release carries the built .wasm components and the pinning
# metadata; the repository itself never commits built .wasm files.
#
# Assets published, matching the shape bloom's PreinstalledPetal installer
# expects (crates/bloom/src/github_source.rs):
#   solana-driver-<TAG>.petal.tar.gz  - the installable package archive
#   petal-release.json                - bloom.petal.release.v1 manifest
#   SHA256SUMS                        - checksum of the archive
#   build-manifest.json / reproducibility.json / verifier-corpus.json
#
# Usage: TAG=v0.1.0 bash scripts/create-release.sh
# Requires `gh` authenticated to bloom-directory.
set -euo pipefail

REPO="bloom-directory/bloom-petal-solana"
TAG="${TAG:?set TAG, e.g. TAG=v0.1.0}"
PETAL_NAME="solana-driver"
TOOLING_REPOSITORY="bloom-directory/petal"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/solana-driver-release.XXXXXX")"
ARCHIVE_NAME="${PETAL_NAME}-${TAG}.petal.tar.gz"

SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
TOOLING_COMMIT="$(python3 -c "
import tomllib
with open('$ROOT/petal-build.toml', 'rb') as f:
    print(tomllib.load(f)['sdk']['rev'])
")"

echo "==> building package artifacts"
"${ROOT}/scripts/build.sh"

echo "==> computing digests"
source_package_hash="$(cd "$ROOT" && cargo run --quiet --manifest-path scripts/package-hash/Cargo.toml -- source "$ROOT")"
route_digest="$(cd "$ROOT" && cargo run --quiet --manifest-path scripts/package-hash/Cargo.toml -- hash "$ROOT/petal/solana-driver/transfer.stage.json.wasm")"

echo "==> staging release payload"
mkdir -p "$STAGING/pkg"
# The package tarball: source + built route components + pinning manifests.
# --owner/--group/--numeric-owner zero every entry's uid/gid: bloom-petals'
# archive reader (crates/bloom-petals/src/package.rs) rejects nonzero owner
# metadata as untrusted archive content, matching the ustar headers its own
# write_package_tar produces.
tar --owner=0 --group=0 --numeric-owner \
  -czf "$STAGING/${ARCHIVE_NAME}" \
  --exclude='.git' --exclude='target' --exclude='*/target' --exclude='test-ledger' \
  -C "$ROOT" .

archive_sha256="$(sha256sum "$STAGING/${ARCHIVE_NAME}" | cut -d' ' -f1)"
echo "${archive_sha256}  ${ARCHIVE_NAME}" > "$STAGING/SHA256SUMS"

cat > "$STAGING/petal-release.json" <<EOF
{
  "schema": "bloom.petal.release.v1",
  "petal_name": "${PETAL_NAME}",
  "source_repository": "${REPO}",
  "source_commit": "${SOURCE_COMMIT}",
  "release_tag": "${TAG}",
  "archive": "${ARCHIVE_NAME}",
  "archive_sha256": "${archive_sha256}",
  "package_hash": "${source_package_hash}",
  "tooling_repository": "${TOOLING_REPOSITORY}",
  "tooling_commit": "${TOOLING_COMMIT}"
}
EOF

cp "$ROOT/artifacts/build-manifest.json" "$STAGING/build-manifest.json"
cp "$ROOT/artifacts/reproducibility.json" "$STAGING/reproducibility.json"
cp "$ROOT/artifacts/verifier-corpus.json" "$STAGING/verifier-corpus.json"

cat > "$STAGING/release-notes.md" <<EOF
## solana driver petal ${TAG}

Verified native SOL transfer driver: constructs legacy single-signer System
Program transfers through Machine-mediated chain reads; never signs or
broadcasts itself.

- **source_package_hash / package_hash** (blake3): \`${source_package_hash}\`
- **route artifact digest** (blake3): \`${route_digest}\`
- **archive_sha256**: \`${archive_sha256}\`
- **source_commit**: \`${SOURCE_COMMIT}\`
- **tooling_commit**: \`${TOOLING_COMMIT}\`
- **reproducibility digest** (sha256): \`$(sha256sum "$ROOT/artifacts/reproducibility.json" | cut -d' ' -f1)\`
EOF

echo "==> creating release $TAG"
gh release create "$TAG" \
  --repo "$REPO" \
  --title "$TAG" \
  --notes-file "$STAGING/release-notes.md" \
  "$STAGING/${ARCHIVE_NAME}" \
  "$STAGING/petal-release.json" \
  "$STAGING/SHA256SUMS" \
  "$STAGING/build-manifest.json" \
  "$STAGING/reproducibility.json" \
  "$STAGING/verifier-corpus.json"

echo "release $TAG published: https://github.com/$REPO/releases/tag/$TAG"
echo "source_package_hash=$source_package_hash"
echo "route_digest=$route_digest"
echo "archive_sha256=$archive_sha256"
echo "source_commit=$SOURCE_COMMIT"
echo "tooling_commit=$TOOLING_COMMIT"

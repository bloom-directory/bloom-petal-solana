#!/usr/bin/env bash
# Release pipeline for bloom-petal-solana.
#
#  1. Hermetic reproduction gate (verify-repro.sh must pass).
#  2. Publish the GitHub release with the built package tarball and pinning
#     manifests (build-manifest.json, reproducibility.json, verifier-corpus.json).
#
# No signing secret is read from or written to this repository. The catalog
# signature is produced by bloom's release pipeline, not by this repo.
set -euo pipefail

petal_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "==> [1/2] hermetic reproduction gate"
"${petal_root}/verify-repro.sh"

echo "==> [2/2] publish GitHub release"
"${petal_root}/scripts/create-release.sh"

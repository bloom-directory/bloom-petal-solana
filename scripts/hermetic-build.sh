#!/usr/bin/env bash
# Hermetic component build, shared by build.sh, verify-repro.sh, and CI.
#
# Remaps the two machine-dependent path roots — the cargo registry and the
# checkout directory — to fixed virtual prefixes, and disables any wrapper or
# incremental machinery, so the emitted .wasm is byte-identical across
# machines (proven: zero /home/ or runner-specific paths in the component).
set -euo pipefail

# SRC_DIR is the crate root to build; TARGET_DIR is a fresh CARGO_TARGET_DIR.
SRC_DIR="${1:?usage: hermetic-build.sh <src_dir> <target_dir>}"
TARGET_DIR="${2:?usage: hermetic-build.sh <src_dir> <target_dir>}"

CARGO_HOME_DIR="${CARGO_HOME:-$HOME/.cargo}"

export RUSTFLAGS="--remap-path-prefix=${CARGO_HOME_DIR}=/cargo --remap-path-prefix=${SRC_DIR}=/build"
unset CARGO_INCREMENTAL RUSTC_WRAPPER
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

CARGO_TARGET_DIR="${TARGET_DIR}" \
  cargo build \
    --manifest-path "${SRC_DIR}/Cargo.toml" \
    --target wasm32-unknown-unknown \
    --release \
    --locked

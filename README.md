# solana-driver

> **Status: unused — kept for reference only.** This Petal is not shipped,
> preinstalled, or maintained as a product surface. Native Solana support in
> the main [`bloom`](https://github.com/bloom-directory/bloom) repository
> replaced the Petal-based approach. This repository now serves as a
> reference implementation of a standalone chain-driver Petal and as a
> fixture for the out-of-process triad integration harness.

A content-addressed chain driver Petal for native SOL transfers, built when
Solana support was explored as a Petal. The routes and capability design
below document how that experiment worked.

## Routes

- `transfer.stage.json` — constructs a canonical legacy, single-signer System
  Program transfer message from typed input (`fee_payer_base58`,
  `destination_base58`, `lamports`, optional `blockhash_hex`). Without an
  explicit blockhash it performs exactly one Machine-mediated
  `getLatestBlockhash` read on the named `chain_profile`. Returns the message
  bytes, SHA-256 payload commitment, and economic facts.
- `transfer.assemble.json` — assembles the complete signed transaction from
  the message bytes and an externally produced 64-byte Ed25519 signature.

## Capabilities

Imports `bloom:chain/read` (Machine-mediated; no endpoints or credentials are
visible to the guest) and `bloom:store` (result persistence). No network,
signing, key-derivation, or VFS authority. Signing happens through the triad
(Broker approval, Signer custody) outside this Petal; the independent
`solana-system-transfer-v1` verifier in `bloom-solana` re-parses every
message this driver constructs.

## Build

`scripts/build.sh` builds for `wasm32-unknown-unknown`, wraps each route as a
component, validates, and records content-addressed artifacts under
`artifacts/`.

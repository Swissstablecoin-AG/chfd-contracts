# CHFD Stellar Soroban Contracts

This directory contains the Soroban implementation of the CHFD token system for Stellar.

The canonical behavioral source of truth for this implementation is [SPEC.md](/Users/samkirton/Documents/repos/chfd-contracts/stellar/chfd/SPEC.md). This Stellar workspace applies the same compliance-first architecture using Soroban contracts, Soroban events, and Soroban-native upgrade flows.

## Overview

The workspace is organized into three Rust crates:

- `contracts/chfd`: the CHFD token contract
- `contracts/chfd-vasp`: the VASP registry and transfer validation contract
- `contracts/chfd-vasp-interface`: shared interface types and client bindings

The token contract delegates compliance checks to the VASP contract before minting and normal transfers, while administrative roles retain control over issuance, enforcement, pausing, and upgrades.

## Workspace Structure

```text
stellar/chfd
├── Cargo.toml
└── contracts
    ├── chfd
    ├── chfd-vasp
    └── chfd-vasp-interface
```

Primary sources:

- [contracts/chfd/src/lib.rs](/Users/samkirton/Documents/repos/chfd-contracts/stellar/chfd/contracts/chfd/src/lib.rs)
- [contracts/chfd-vasp/src/lib.rs](/Users/samkirton/Documents/repos/chfd-contracts/stellar/chfd/contracts/chfd-vasp/src/lib.rs)
- [contracts/chfd-vasp-interface/src/lib.rs](/Users/samkirton/Documents/repos/chfd-contracts/stellar/chfd/contracts/chfd-vasp-interface/src/lib.rs)

## Token Properties

- Name: `Swiss Stablecoin`
- Symbol: `CHFD`
- Decimals: `6`

## Contracts

### `chfd`

The token contract provides:

- balances and transfers
- minting and burning
- pausing and unpausing
- force transfers
- admin-gated contract upgrade
- role-gated updates to the configured VASP contract address

It emits Soroban events for:

- mint
- burn
- transfer with VASP context
- force transfer
- VASP contract address updates

### `chfd-vasp`

The VASP contract provides:

- VASP registration and status updates
- VASP admin membership management
- holder registration
- holder limit updates
- holder status updates
- transfer validation
- admin-gated contract upgrade

It stores:

- VASP status and admin count
- VASP-admin membership per VASP
- holder VASP assignment
- holder limit
- holder status
- VASP-owned flag

### `chfd-vasp-interface`

The shared interface crate defines:

- `VaspStatus`
- `HolderStatus`
- `HolderDetails`
- `TransferVaspIds`
- the generated client trait used by the token contract

## Roles

### `chfd`

- default admin: grant or revoke admin and worker roles, update contract wasm, set VASP contract address
- minter: mint CHFD
- burner: burn CHFD
- enforcement: pause, unpause, and force transfer

### `chfd-vasp`

- default admin: grant or revoke admin role, update contract wasm, manage update operators
- update operator: add VASPs, update VASP status, and manage holders and VASP admins through the contract entrypoints

Per-VASP admin membership is also maintained inside the VASP registry contract, with a maximum of `10` admins per VASP and a requirement that at least one admin remain.

## Compliance Model

For normal minting and transfers, the token contract asks the VASP contract to validate:

- holder existence
- holder active status
- VASP active status
- receiver post-transfer balance against holder limit

Enforcement and administrative paths remain distinct from normal validated transfer flows, matching the overall CHFD system design.

## Upgradeability

Both Soroban contracts expose explicit upgrade entrypoints that update the currently deployed wasm hash after admin authorization.

This repository keeps the token and VASP registry separate so they can evolve independently while preserving the contract-to-contract validation boundary.

## Development

Requirements:

- Rust toolchain
- Cargo
- Soroban-compatible toolchain for build and deployment workflows

From [stellar/chfd/Cargo.toml](/Users/samkirton/Documents/repos/chfd-contracts/stellar/chfd/Cargo.toml):

- workspace dependency: `soroban-sdk = 25.3.1`

Build:

```bash
cargo build --release
```

Test:

```bash
cargo test
```

Relevant test files:

- [contracts/chfd/src/test.rs](/Users/samkirton/Documents/repos/chfd-contracts/stellar/chfd/contracts/chfd/src/test.rs)
- [contracts/chfd-vasp/src/test.rs](/Users/samkirton/Documents/repos/chfd-contracts/stellar/chfd/contracts/chfd-vasp/src/test.rs)

## Addresses and Artifacts

No deployed contract IDs, wasm hashes, or release artifacts are documented in this directory today.

## Audits

No audit reports are included in this directory today.

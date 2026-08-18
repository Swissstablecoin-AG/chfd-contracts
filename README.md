# CHFD Contracts

This repository contains the smart contract implementations for `CHFD` ("Swiss Stablecoin") across the supported execution environments:

- `ethereum/chfd`: Solidity contracts for EVM networks
- `stellar/chfd`: Soroban contracts for Stellar

The implementation specifications for the CHFD system are:

- [ethereum/chfd/SPEC.md](./ethereum/chfd/SPEC.md) for the EVM implementation
- [stellar/chfd/SPEC.md](./stellar/chfd/SPEC.md) for the Soroban implementation

The READMEs in this repository summarize those specifications and point to the relevant implementation details.

## Overview

The CHFD system is organized around two core components:

- `CHFD`: the token contract responsible for balances, transfers, minting, burning, pausing, and enforcement actions
- `CHFD_VASP`: the compliance and registry contract responsible for VASP registration, holder registration, lifecycle statuses, transfer validation, and operator workflows

The design is compliance-first:

- transfers and minting are limited to registered holders
- holder and VASP statuses gate normal activity
- receiver limits are enforced on validated receipts
- enforcement workflows exist for regulated exceptions such as forced transfers and enforcement burns

## Repository Structure

```text
.
├── ethereum/chfd
│   ├── SPEC.md
│   ├── src/
│   ├── script/
│   └── test/
└── stellar/chfd
    ├── contracts/
    └── Cargo.toml
```

## Specification

The chain-specific specifications define the CHFD model for each implementation, including:

- contract responsibilities
- platform and worker roles
- VASP-local admin rules
- holder and VASP status models
- transfer validation requirements
- mint, burn, pause, and force-transfer behavior
- upgradeability and event expectations

If this README and either chain-specific specification diverge, the relevant specification should be treated as authoritative for that implementation.

## Implementations

### Ethereum

The EVM implementation uses Solidity `0.8.34`, OpenZeppelin upgradeable contracts, and Foundry.

Main contracts:

- [ethereum/chfd/src/CHFD.sol](./ethereum/chfd/src/CHFD.sol)
- [ethereum/chfd/src/CHFD_VASP.sol](./ethereum/chfd/src/CHFD_VASP.sol)

Highlights:

- UUPS-upgradeable proxy architecture
- EIP-712 signature workflows in `CHFD_VASP`
- ERC-20 permit support in `CHFD`
- Foundry unit, fuzz, invariant, and upgrade tests

See [ethereum/chfd/README.md](./ethereum/chfd/README.md) for environment-specific details.

### Stellar

The Stellar implementation uses Rust, Soroban SDK `25.3.1`, and a workspace containing the token, VASP registry, and shared interface crate.

Main contracts:

- [stellar/chfd/contracts/chfd/src/lib.rs](./stellar/chfd/contracts/chfd/src/lib.rs)
- [stellar/chfd/contracts/chfd-vasp/src/lib.rs](./stellar/chfd/contracts/chfd-vasp/src/lib.rs)
- [stellar/chfd/contracts/chfd-vasp-interface/src/lib.rs](./stellar/chfd/contracts/chfd-vasp-interface/src/lib.rs)

Highlights:

- role-based token and VASP registry contracts
- Soroban-native pause, upgrade, and event flows
- shared interface types for transfer validation and registry lookups

See [stellar/chfd/README.md](./stellar/chfd/README.md) for workspace-specific details.

## Upgradeability

Both implementations are designed for administrative upgrades:

- Ethereum uses UUPS-upgradeable contracts behind proxies
- Stellar exposes explicit contract upgrade entrypoints gated by admin role checks

Upgrade authorization remains separated from day-to-day mint, burn, enforcement, and VASP update workflows.

## Development

Ethereum:

```bash
cd ethereum/chfd
forge build
forge test
```

Stellar:

```bash
cd stellar/chfd
cargo test
```

## Audits

No audit reports or deployed contract addresses are documented in this repository today. If those artifacts are produced later, they should be added alongside the chain-specific READMEs.

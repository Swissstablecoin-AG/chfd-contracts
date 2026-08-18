# CHFD Ethereum Contracts

This directory contains the Ethereum implementation of the CHFD token system.

The behavioral source of truth for this implementation is [SPEC.md](./SPEC.md). This README follows the general structure used in `paxosglobal/pyusd-contract`, but the content below is specific to CHFD.

## Overview

The Ethereum CHFD system is split into two UUPS-upgradeable contracts:

- `CHFD`: the ERC-20 token contract for `Swiss Stablecoin` (`CHFD`)
- `CHFD_VASP`: the compliance and registry contract used to approve minting and transfers

The system is designed for regulated issuance and movement of CHFD:

- minting is limited to registered, active holders whose post-mint balance remains within limit
- normal transfers require active sender and receiver holders, active associated VASPs, and a compliant receiver post-transfer balance
- enforcement operators can pause transfers, execute force transfers, and burn independently of normal validation rules

## Contracts

Primary contracts:

- [src/CHFD.sol](./src/CHFD.sol)
- [src/CHFD_VASP.sol](./src/CHFD_VASP.sol)

Supporting modules:

- [src/Statuses.sol](./src/Statuses.sol)
- [src/Events.sol](./src/Events.sol)
- [src/Errors.sol](./src/Errors.sol)
- [src/ICHFDVasp.sol](./src/ICHFDVasp.sol)

Versioned upgrade targets in this repository:

- [src/CHFD_V2.sol](./src/CHFD_V2.sol)
- [src/CHFD_VASP_V2.sol](./src/CHFD_VASP_V2.sol)

## Token Properties

- Name: `Swiss Stablecoin`
- Symbol: `CHFD`
- Decimals: `6`
- Standard base: ERC-20 with ERC-2612 permit support

## Roles

### CHFD

- `DEFAULT_ADMIN_ROLE`: upgrades, role management, VASP contract address changes
- `MINTER_ROLE`: mint CHFD
- `BURNER_ROLE`: burn via `burnFromWithPermit`
- `ENFORCEMENT_ROLE`: pause, unpause, force transfer, and enforcement burn

### CHFD_VASP

- `DEFAULT_ADMIN_ROLE`: upgrades and role management
- `UPDATE_VASP_ROLE`: VASP registry updates and signature-based VASP workflows
- `VALIDATE_TRANSFER_ROLE`: permission to call `validateTransfer`

### VASP-local Administration

Each VASP maintains its own admin set inside `CHFD_VASP`.

- maximum admins per VASP: `10`
- at least one admin must remain
- VASP admins manage holders, limits, statuses, and additional VASP admins for their VASP

## Compliance Model

`CHFD_VASP` maintains:

- VASP lifecycle status
- holder lifecycle status
- holder-to-VASP association
- holder balance limits
- VASP-owned flag

Normal transfers and mints are validated through `validateTransfer`, which enforces the rules described in [SPEC.md](./ethereum/chfd/SPEC.md).

The Ethereum implementation also supports EIP-712 signature workflows for:

- `addVasp`
- `addVaspAdminWithSig`
- `removeVaspAdminWithSig`
- `addHolderWithSig`
- `setHolderLimitWithSig`
- `setHolderStatusWithSig`

## Upgradeability

Both `CHFD` and `CHFD_VASP` use UUPS upgradeability and are intended to be deployed behind ERC-1967 proxies.

The repository includes:

- the implementation contracts in [src](./ethereum/chfd/src)
- a deployment script in [script/DeployCHFD.s.sol](./script/DeployCHFD.s.sol)
- upgrade tests in [test/CHFDUpgrade.t.sol](./test/CHFDUpgrade.t.sol) and [test/CHFD_VASP_Upgrade.t.sol](./test/CHFD_VASP_Upgrade.t.sol)

## Deployment

The deployment flow in [script/DeployCHFD.s.sol](./script/DeployCHFD.s.sol) deploys:

1. `CHFD_VASP` implementation and proxy
2. `CHFD` implementation and proxy, initialized with the VASP proxy address
3. role assignments for admins and workers
4. `VALIDATE_TRANSFER_ROLE` for the CHFD proxy on the VASP contract
5. revocation of bootstrap roles from the deployer

Expected environment variables include:

- `DEPLOYER_PRIVATE_KEY`
- `MINTER_ROLE_ADDRESS`
- `BURNER_ROLE_ADDRESS`
- `ENFORCEMENT_ROLE_ADDRESS`
- `UPDATE_VASP_ROLE_ADDRESS`
- `DEFAULT_ADMIN_ROLE_ADDRESS`
- `DEFAULT_ADMIN_ROLE_FAILOVER_ADDRESS`

Successful deployments write [out/deployment.json](./out/deployment.json) when run locally.

## Development

Requirements:

- Foundry
- Solidity `0.8.34`

Build:

```bash
forge build
```

Test:

```bash
forge test
```

Useful test targets in this repository:

- [test/CHFD.t.sol](./test/CHFD.t.sol)
- [test/CHFDFuzz.t.sol](./test/CHFDFuzz.t.sol)
- [test/CHFDInvariants.t.sol](./test/CHFDInvariants.t.sol)
- [test/CHFDUpgrade.t.sol](./test/CHFDUpgrade.t.sol)
- [test/CHFD_VASP_Upgrade.t.sol](./test/CHFD_VASP_Upgrade.t.sol)

## Addresses and ABI

No deployed addresses or packaged ABI artifacts are committed in this directory today. For local deployment outputs, use the generated `out/` directory after running the deployment and build workflows.

## Audits

No audit reports are included in this directory today.

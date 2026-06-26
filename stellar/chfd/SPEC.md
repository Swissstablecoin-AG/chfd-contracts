# CHFD Stellar System Specification

## 1. Purpose

This document is the canonical technical specification for the Stellar Soroban implementation of the CHFD token system.

The system consists of:

- `chfd`: token, mint, burn, transfer, pause, force transfer, and role management logic
- `chfd-vasp`: compliance, registration, status management, and transfer validation logic
- `chfd-vasp-interface`: shared Soroban interface types and client bindings used by the token contract

Both primary contracts support admin-gated wasm upgrades.

## 2. Design Goals

| Goal | Description |
| --- | --- |
| Compliance-first operation | Transfers, burns, and minting are constrained by holder and VASP registration, status, and limits unless an enforcement-only path is used. |
| Operational control | Administrative, update-operator, mint, burn, and enforcement powers are explicit and role-gated. |
| Separation of concerns | Token accounting lives in `chfd`; compliance and registry logic live in `chfd-vasp`. |
| Soroban-native execution | Authorization uses Soroban account auth and role membership instead of EIP-712 signature relaying. |
| Auditability | Core actions emit events with operator, holder, and VASP context where applicable. |

## 3. Contract Topology

| Contract | Responsibility |
| --- | --- |
| `chfd` | Fungible token balances and allowance logic, minting, burning, transfers, force transfers, pausing, VASP contract reference management |
| `chfd-vasp` | VASP registry, holder registry, admin registry per VASP, status updates, transfer validation |
| `chfd-vasp-interface` | Shared types for statuses, holder details, transfer VASP IDs, and generated contract client bindings |

## 4. Roles

### 4.1 `chfd` Roles

| Role | Purpose |
| --- | --- |
| `default_admin` | Contract administration, wasm upgrades, VASP contract reference updates, role management |
| `minter` | Mint CHFD |
| `burner` | Burn through burner-authorized custom flows |
| `enforcement` | Pause, unpause, force transfer, and enforcement burn |

### 4.2 `chfd-vasp` Roles

| Role | Purpose |
| --- | --- |
| `default_admin` | Contract administration, wasm upgrades, role management |
| `update_operator` | Add VASPs and update VASP status; co-authorize VASP admin membership changes |

### 4.3 VASP-Local Admins

Each VASP maintains its own admin set.

| Property | Rule |
| --- | --- |
| Membership | Stored per VASP |
| Maximum size | `MAX_VASP_ADMINS = 10` |
| Minimum size | At least one admin must remain |
| Authority | Manage holders, holder limits, holder statuses, and co-authorize VASP admin membership changes |

## 5. Core Data Model

### 5.1 `chfd` State

| Field | Meaning |
| --- | --- |
| `VaspContract` | Soroban contract address used for compliance validation and VASP lookups |

### 5.2 VASP State

| Field | Meaning |
| --- | --- |
| `status` | Lifecycle status for the VASP |
| `admin_count` | Number of active admins |
| `VaspAdmin(vasp_id, admin)` | Membership flag for each VASP admin |

### 5.3 Holder State

| Field | Meaning |
| --- | --- |
| `vasp_id` | Permanent VASP association |
| `limit` | Maximum permitted balance for validated receipts |
| `status` | Holder lifecycle status |
| `vasp_owned` | VASP-owned flag as stored in the registry |

### 5.4 Existence Rules

| Entity | Existence rule |
| --- | --- |
| VASP | Exists if a `Vasp(vasp_id)` record is present |
| Holder | Exists if a `Holder(address)` record is present |

## 6. Status Model

### 6.1 VASP Status

VASPs use an enum-based lifecycle model including `Active` and restricted states such as `Blocked`, `Locked`, `Sanctioned`, and `Frozen`.

### 6.2 Holder Status

Holders use an enum-based lifecycle model including `Active` and restricted states such as `Blocked`, `Locked`, `Sanctioned`, and `Frozen`.

### 6.3 Status Effects

| Flow | Requires active holder/VASP status |
| --- | --- |
| Normal holder-to-holder transfer | Yes |
| Mint | Yes, for receiver and receiver VASP |
| Token-interface burn and burn-from | Yes, for source holder and source VASP |
| Burner-authorized custom burn | Yes, for source holder and source VASP |
| Enforcement burn | Yes, for source holder and source VASP |
| `add_holder` | Yes, VASP must be active |
| `add_vasp_admin` | No |
| `set_holder_limit` | Yes, VASP must be active |
| `set_holder_status` | Yes, VASP must be active |
| Force transfer | No |

## 7. External Interfaces

### 7.1 `chfd` Interface Summary

| Function | Access | Notes |
| --- | --- | --- |
| `__constructor(Address admin, Address admin_failover, Address vasp_contract)` | constructor auth | Sets token metadata, stores VASP contract, grants bootstrap roles to `admin`, and grants admin role to `admin_failover` |
| `upgrade(Address admin, BytesN<32> new_wasm_hash)` | `default_admin` | Updates current contract wasm |
| `set_vasp_contract_address(Address admin, Address vasp_contract)` | `default_admin` | Updates compliance contract reference |
| `grant_default_admin_role` / `revoke_default_admin_role` | `default_admin` | Manage contract admins |
| `grant_minter_role` / `revoke_minter_role` | `default_admin` | Manage minters |
| `grant_burner_role` / `revoke_burner_role` | `default_admin` | Manage burners |
| `grant_mint_burn_roles` / `revoke_mint_burn_roles` | `default_admin` | Manage combined mint and burn worker access |
| `grant_enforcement_role` / `revoke_enforcement_role` | `default_admin` | Manage enforcement workers |
| `mint(Address operator, Address to, i128 amount, BytesN<32> reference_id)` | `minter` | Validated through `chfd-vasp.validate_transfer(None, Some(to), target_balance)` |
| `burn_with_ref(Address from, i128 amount, Address operator, BytesN<32> reference_id)` | `burner` + holder auth | Burner flow with holder self-auth and reference ID |
| `burn_from_with_auth(Address operator, Address from, i128 amount, BytesN<32> reference_id)` | `burner` + holder auth | Equivalent burner-authorized custom burn path |
| `burner_burn_from(Address operator, Address from, i128 amount, BytesN<32> reference_id)` | `burner` | Burner-authorized burn without holder auth |
| `enforcement_burn_from(Address operator, Address from, i128 amount, BytesN<32> reference_id)` | `enforcement` | Enforcement burn |
| `force_transfer(Address operator, Address from, Address to, i128 amount, BytesN<32> reference_id)` | `enforcement` | Bypasses pause and VASP validation |
| `pause(Address caller)` | `enforcement` | Pauses normal token operations |
| `unpause(Address caller)` | `enforcement` | Unpauses normal token operations |
| `transfer` / `transfer_from` | standard auth | Normal validated transfers; `transfer` accepts `MuxedAddress` recipients |
| `burn` / `burn_from` | standard auth | Standard token-interface burns with status validation |

### 7.2 `chfd-vasp` Interface Summary

| Function | Access | Notes |
| --- | --- | --- |
| `__constructor(Address platform_admin, Address platform_admin_failover)` | constructor auth | Grants admin role to both initial admin addresses |
| `upgrade(Address admin, BytesN<32> new_wasm_hash)` | `default_admin` | Updates current contract wasm |
| `grant_default_admin_role` / `revoke_default_admin_role` | `default_admin` | Manage contract admins |
| `grant_update_operator` / `revoke_update_operator` | `default_admin` | Manage platform update operators |
| `add_vasp(Address operator, BytesN<32> vasp_id, Address vasp_admin, BytesN<32> reference_id)` | `update_operator` | Registers VASP, initial VASP admin, and initial holder record for the admin |
| `verify_vasp_admin(BytesN<32> vasp_id, Address vasp_admin, BytesN<32> reference_id)` | holder auth | Authentication helper that verifies admin authorization and returns `reference_id` |
| `set_vasp_status(Address operator, BytesN<32> vasp_id, VaspStatus status, BytesN<32> reference_id)` | `update_operator` | Updates VASP lifecycle status |
| `add_vasp_admin(Address operator, Address admin, BytesN<32> vasp_id, Address new_admin, BytesN<32> reference_id)` | `update_operator` + existing VASP admin auth | Adds VASP admin; creates a holder record if `new_admin` is not already a holder in the same VASP |
| `remove_vasp_admin(Address operator, Address admin, BytesN<32> vasp_id, Address admin_to_remove, BytesN<32> reference_id)` | `update_operator` + existing VASP admin auth | Cannot remove the last admin |
| `add_holder(Address admin, BytesN<32> vasp_id, Address holder_address, u128 holder_limit, u32 vasp_owned, BytesN<32> reference_id)` | existing VASP admin | VASP must be active |
| `set_holder_limit(Address admin, BytesN<32> vasp_id, Address holder_address, u128 holder_limit, BytesN<32> reference_id)` | existing VASP admin | Holder must belong to the VASP; VASP must be active |
| `set_holder_status(Address admin, BytesN<32> vasp_id, Address holder_address, HolderStatus status, BytesN<32> reference_id)` | existing VASP admin | Holder must belong to the VASP; VASP must be active |
| `validate_transfer(Option<Address> from, Option<Address> to, u128 target_amount)` | public | Compliance validation entry point used by the token contract |
| `get_vasp_details` / `get_vasp_admin_status` / `get_holder_details` / `get_holder_vasp_id` / `get_transfer_vasp_ids` | public view | Registry and transfer-context read helpers |

## 8. Authorization Model

### 8.1 Model

The Stellar implementation uses direct Soroban authorization and on-chain role checks rather than EIP-712 signatures.

### 8.2 Auth Preconditions

| Flow | Preconditions |
| --- | --- |
| `add_vasp` | `operator` must authorize and hold `update_operator` |
| `add_vasp_admin` / `remove_vasp_admin` | Both `operator` and the existing VASP admin must authorize |
| `add_holder` / `set_holder_limit` / `set_holder_status` | Calling VASP admin must authorize |
| `burn_with_ref` / `burn_from_with_auth` | Both `operator` and `from` must authorize |
| Standard `transfer` | `from` must authorize |
| Standard `transfer_from` | `spender` must authorize |

### 8.3 Bootstrap Administration

| Contract | Bootstrap rule |
| --- | --- |
| `chfd` | Constructor grants `default_admin`, `minter`, `burner`, and `enforcement` to `admin`, and `default_admin` to `admin_failover` |
| `chfd-vasp` | Constructor grants `default_admin` to `platform_admin` and `platform_admin_failover`; no update operator is granted automatically |

## 9. Transfer Validation Rules

### 9.1 Normal Transfer and Mint Rules

| Rule | Applies to |
| --- | --- |
| Sender must exist | Normal holder-to-holder transfers and token-interface burns |
| Receiver must exist | Normal transfers and mint |
| Sender holder must be active | Normal holder-to-holder transfers and token-interface burns |
| Receiver holder must be active | Normal transfers and mint |
| Associated VASP must be active | Normal transfers, mint, and validated burns |
| Receiver post-transfer balance must not exceed limit | Normal transfers and mint |

### 9.2 Target Amount Semantics

For validated receipts, `target_amount` represents the receiver's post-operation balance.

This is computed as:

- `balance(to) + amount` for mint
- `balance(to) + amount` for normal transfers

Unlike the Ethereum implementation, the Soroban token implementation does not introduce a self-transfer special case in the validation calculation.

## 10. Minting

| Property | Rule |
| --- | --- |
| Access | `minter` |
| Interface | `mint(Address operator, Address to, i128 amount, BytesN<32> reference_id)` |
| Pause interaction | Blocked while paused |
| Validation | Receiver existence, receiver active status, receiver VASP active status, receiver limit |
| Event | `MintEvent` |

## 11. Burning

### 11.1 Standard Token Burns

| Property | Rule |
| --- | --- |
| Functions | `burn`, `burn_from` |
| Access | Standard token auth and allowance rules |
| Pause interaction | Blocked while paused |
| Validation | Source holder existence, source holder active status, source VASP active status |
| Event | Standard Soroban fungible burn event only |

### 11.2 Burner-Authorized Burns

| Property | Rule |
| --- | --- |
| Functions | `burn_with_ref`, `burn_from_with_auth`, `burner_burn_from` |
| Access | `burner`; some flows also require holder auth |
| Pause interaction | Blocked while paused |
| Validation | Source holder existence, source holder active status, source VASP active status |
| Event | `BurnEvent` plus Soroban fungible burn event |

### 11.3 Enforcement Burn

| Property | Rule |
| --- | --- |
| Function | `enforcement_burn_from` |
| Access | `enforcement` |
| Pause interaction | Blocked while paused |
| Validation | Source holder existence, source holder active status, source VASP active status |
| Event | `BurnEvent` plus Soroban fungible burn event |

## 12. Pausing

| Property | Rule |
| --- | --- |
| Access | `enforcement` |
| Effect on normal transfers | Blocked |
| Effect on mint | Blocked |
| Effect on token-interface burns | Blocked |
| Effect on custom burner and enforcement burns | Blocked |
| Effect on force transfer | Not blocked |

## 13. Force Transfer

| Property | Rule |
| --- | --- |
| Access | `enforcement` |
| Validation bypass | Yes; no `validate_transfer` call is performed |
| Pause bypass | Yes |
| Recipient registration requirement | No explicit pre-check; balance update proceeds directly |
| Event | `ForceTransferEvent` and Soroban fungible transfer event |
| Transfer-with-VASP event | Not emitted on force transfer path |

## 14. Upgradeability

| Contract | Upgrade mechanism | Authorization |
| --- | --- | --- |
| `chfd` | `env.deployer().update_current_contract_wasm(new_wasm_hash)` | `default_admin` |
| `chfd-vasp` | `env.deployer().update_current_contract_wasm(new_wasm_hash)` | `default_admin` |

## 15. Events

### 15.1 `chfd` Events

- `MintEvent`
- `BurnEvent`
- `ChfdTransferEvent`
- `ForceTransferEvent`
- `VaspContractAddressUpdated`

The token contract also emits standard Soroban fungible token transfer and burn events.

### 15.2 `chfd-vasp` Events

- `AddVaspEvent`
- `AddVaspAdminEvent`
- `RemoveVaspAdminEvent`
- `AddHolderEvent`
- `SetVaspStatusEvent`
- `SetHolderLimitEvent`
- `SetHolderStatusEvent`

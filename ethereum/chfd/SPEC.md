# CHFD System Specification

## 1. Purpose

This document is the canonical technical specification for the CHFD token system.

The system consists of:

- `CHFD`: token, mint, burn, transfer, pause, and enforcement logic
- `CHFD_VASP`: compliance, registration, status management, and transfer validation logic

Both contracts are UUPS-upgradeable.

## 2. Design Goals

| Goal | Description |
| --- | --- |
| Compliance-first operation | Transfers and minting are constrained by holder and VASP registration, status, and limits. |
| Operational control | Administrative, updater, minter, burner, and enforcement powers are explicit and role-gated. |
| Separation of concerns | Token accounting lives in `CHFD`; compliance and registry logic live in `CHFD_VASP`. |
| Auditability | Core actions emit events with operator and VASP context where applicable. |
| Controlled exceptions | Enforcement flows may bypass normal validation under tightly scoped conditions. |

## 3. Contract Topology

| Contract | Responsibility |
| --- | --- |
| `CHFD` | ERC-20 balances and allowance logic, minting, burning, transfers, force transfers, pausing |
| `CHFD_VASP` | VASP registry, holder registry, admin registry per VASP, status updates, transfer validation, EIP-712 signature workflows |

## 4. Roles

### 4.1 CHFD Roles

| Role | Purpose |
| --- | --- |
| `DEFAULT_ADMIN_ROLE` | Contract administration, upgrades, VASP contract reference updates, role management |
| `MINTER_ROLE` | Mint tokens |
| `BURNER_ROLE` | Burn via `burnFromWithPermit` |
| `ENFORCEMENT_ROLE` | Pause, unpause, force transfer, and direct enforcement burn |

### 4.2 CHFD_VASP Roles

| Role | Purpose |
| --- | --- |
| `DEFAULT_ADMIN_ROLE` | Contract administration, upgrades, role management |
| `UPDATE_VASP_ROLE` | Execute signature-based VASP operations and update VASP status |
| `VALIDATE_TRANSFER_ROLE` | Call `validateTransfer` |

### 4.3 VASP-Local Admins

Each VASP maintains its own admin set.

| Property | Rule |
| --- | --- |
| Membership | Stored per VASP |
| Maximum size | `MAX_VASP_ADMINS = 10` |
| Minimum size | At least one admin must remain |
| Authority | Directly manage holders and VASP-local admin membership |

## 5. Core Data Model

### 5.1 VASP State

| Field | Meaning |
| --- | --- |
| `status` | Lifecycle status for the VASP |
| `admins` | Mapping of admin addresses |
| `adminCount` | Number of active admins |

### 5.2 Holder State

| Field | Meaning |
| --- | --- |
| `vaspId` | Permanent VASP association |
| `limit` | Maximum permitted balance for normal validated receipts |
| `status` | Holder lifecycle status |
| `vaspOwned` | VASP-owned flag as stored in the registry |

### 5.3 Existence Rules

| Entity | Existence rule |
| --- | --- |
| VASP | Exists if its status is not `VaspStatus.None` |
| Holder | Exists if its `vaspId` is non-zero |

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
| `addHolder` | Yes, VASP must be active |
| `addVaspAdmin` | Yes, VASP must be active |
| `setHolderLimit` | No |
| `setHolderStatus` | No |
| Enforcement burn | No |
| Force transfer | No, except recipient must already be a registered holder |

## 7. External Interfaces

### 7.1 CHFD Interface Summary

| Function | Access | Notes |
| --- | --- | --- |
| `initialize(address vaspMasterAddress)` | initializer | Sets token metadata, grants initial roles, stores VASP contract |
| `mint(address to, uint256 amount, bytes32 referenceId)` | `MINTER_ROLE` | Validated through `CHFD_VASP.validateTransfer(address(0), to, target)` |
| `burnFrom(address from, uint256 amount, bytes32 referenceId)` | `ENFORCEMENT_ROLE` | Direct enforcement burn, no allowance consumption |
| `burnFromWithPermit(address owner, uint256 amount, bytes32 referenceId, uint256 deadline, uint8 v, bytes32 r, bytes32 s)` | `BURNER_ROLE` | Permit-assisted burn with allowance consumption |
| `pause()` | `ENFORCEMENT_ROLE` | Pauses normal token updates |
| `unpause()` | `ENFORCEMENT_ROLE` | Unpauses normal token updates |
| `forceTransfer(address from, address to, uint256 amount, bytes32 referenceId)` | `ENFORCEMENT_ROLE` | Bypasses pause and status validation, but `to` must exist as a holder |
| `setVaspContractAddress(address vaspContractAddress)` | `DEFAULT_ADMIN_ROLE` | Updates compliance contract reference |
| `grantMintBurnRoles(address worker)` | `DEFAULT_ADMIN_ROLE` | Grants minter and burner roles |
| `revokeMintBurnRoles(address worker)` | `DEFAULT_ADMIN_ROLE` | Revokes minter and burner roles |

### 7.2 CHFD_VASP Interface Summary

| Function | Access | Notes |
| --- | --- | --- |
| `initialize()` | initializer | Grants initial admin and updater roles |
| `addVasp(...)` | `UPDATE_VASP_ROLE` | Requires signature from proposed VASP admin |
| `setVaspStatus(bytes32 vaspId, VaspStatus status, bytes32 referenceId)` | `UPDATE_VASP_ROLE` | Updates VASP lifecycle status |
| `removeHolder(bytes32 vaspId, address holderAddress, bytes32 referenceId)` | `UPDATE_VASP_ROLE` | Recovery-only removal; holder must belong to the VASP and must not still be a VASP admin |
| `addVaspAdmin(...)` | existing VASP admin | VASP must be active |
| `removeVaspAdmin(...)` | existing VASP admin | Cannot remove last admin |
| `addHolder(...)` | existing VASP admin | VASP must be active |
| `setHolderLimit(...)` | existing VASP admin | Can execute even if VASP is not active |
| `setHolderStatus(...)` | existing VASP admin | Can execute even if VASP is not active |
| `addVaspAdminWithSig(...)` | `UPDATE_VASP_ROLE` | Signature flow, VASP must be active |
| `removeVaspAdminWithSig(...)` | `UPDATE_VASP_ROLE` | Signature flow |
| `addHolderWithSig(...)` | `UPDATE_VASP_ROLE` | Signature flow, VASP must be active |
| `setHolderLimitWithSig(...)` | `UPDATE_VASP_ROLE` | Signature flow |
| `setHolderStatusWithSig(...)` | `UPDATE_VASP_ROLE` | Signature flow |
| `invalidateSignatureNonce(uint256 newNonce)` | signer self-service | Advances signer nonce to invalidate prior pending signatures |
| `validateTransfer(address from, address to, uint256 targetAmount)` | `VALIDATE_TRANSFER_ROLE` | Compliance validation entry point for token contract |
| `DOMAIN_SEPARATOR()` | public view | EIP-712 domain separator accessor |

For `CHFD`, the EIP-712 domain name is the ERC-20 name `Swiss Stablecoin`.

## 8. Signature Workflows

### 8.1 Model

`CHFD_VASP` supports EIP-712 signatures for:

- `addVasp`
- `addVaspAdminWithSig`
- `removeVaspAdminWithSig`
- `addHolderWithSig`
- `setHolderLimitWithSig`
- `setHolderStatusWithSig`

These flows are executed by an address with `UPDATE_VASP_ROLE`.

### 8.2 Replay Protection

| Property | Rule |
| --- | --- |
| Nonce storage | `mapping(address => uint256) public nonces` |
| Consumption | Nonce is consumed when a valid signature for the current value is processed |
| Monotonicity | Nonces only increase |
| Manual invalidation | Signer may call `invalidateSignatureNonce(newNonce)` with `newNonce > currentNonce` |

### 8.3 Signature Preconditions

| Flow | Preconditions |
| --- | --- |
| `addVasp` | Proposed admin must sign payload |
| `*WithSig` VASP admin flows | Signer must currently be an admin of the referenced VASP |
| `addVaspAdminWithSig` | Target admin address must be non-zero |
| `removeVaspAdminWithSig` | Target admin address must be non-zero |
| `addHolderWithSig` | Target holder address must be non-zero |
| All signature flows | Deadline must not be expired |

## 9. Transfer Validation Rules

### 9.1 Normal Transfer and Mint Rules

| Rule | Applies to |
| --- | --- |
| Sender must exist | Normal holder-to-holder transfers |
| Receiver must exist | Normal transfers and mint |
| Sender holder must be active | Normal holder-to-holder transfers |
| Receiver holder must be active | Normal transfers and mint |
| Associated VASP must be active | Normal transfers and mint |
| Receiver post-transfer balance must not exceed limit | Normal transfers and mint |

### 9.2 Target Amount Semantics

For validated receipts, `targetAmount` represents the receiver's post-operation balance.

Special case:

- For self-transfers, `targetAmount` is the current balance, not `balance + amount`, because the balance is unchanged

## 10. Minting

| Property | Rule |
| --- | --- |
| Access | `MINTER_ROLE` |
| Interface | `mint(address to, uint256 amount, bytes32 referenceId)` |
| Validation | Receiver existence, receiver active status, receiver VASP active status, receiver limit |
| Event | `MintEvent` |

## 11. Burning

### 11.1 Enforcement Burn

| Property | Rule |
| --- | --- |
| Function | `burnFrom` |
| Access | `ENFORCEMENT_ROLE` |
| Allowance consumption | None |
| Pause bypass | Yes |
| Holder/VASP status bypass | Yes |
| Event | `BurnEvent` |

### 11.2 Permit-Based Burn

| Property | Rule |
| --- | --- |
| Function | `burnFromWithPermit` |
| Access | `BURNER_ROLE` |
| Authorization model | Permit-assisted allowance spending |
| Allowance consumption | Via `_spendAllowance` |
| Front-run permit behavior | If allowance is already present, a front-run permit does not block burn execution |
| Pause bypass | Yes |
| Holder/VASP status bypass | Yes |
| Event | `BurnEvent` |

## 12. Pausing

| Property | Rule |
| --- | --- |
| Access | `ENFORCEMENT_ROLE` |
| Effect on normal transfers | Blocked |
| Effect on mint | Blocked via `_update` |
| Effect on normal burns | Not applicable; exposed burn paths are special-purpose operator flows |
| Effect on force transfer | Not blocked |
| Effect on enforcement burn | Not blocked |

## 13. Force Transfer

| Property | Rule |
| --- | --- |
| Access | `ENFORCEMENT_ROLE` |
| Zero address handling | `from` and `to` must both be non-zero |
| Recipient registration | `to` must already be a registered holder |
| Pause bypass | Yes |
| Status bypass | Yes |
| Limit validation | Bypassed |
| Event | `ForceTransferEvent` |
| Reentrancy protection | Internal `_forceTransferInProgress` guard |

## 14. Holder and VASP Administration

### 14.1 Allowed Direct Administrative Actions

| Action | Allowed while VASP inactive |
| --- | --- |
| `addVaspAdmin` | No |
| `removeVaspAdmin` | Yes, subject to remaining-admin rule |
| `addHolder` | No |
| `removeHolder` | No |
| `setHolderLimit` | Yes |
| `setHolderStatus` | Yes |

### 14.2 Effects of Admin Addition

Adding a VASP admin also ensures the admin address is registered as a holder for that VASP with:

| Field | Value |
| --- | --- |
| `limit` | `0` |
| `status` | `Active` |
| `vaspOwned` | `0` |

This path is only available while the VASP is active.

Holder removal is reserved for the issuer-side `UPDATE_VASP_ROLE` as a recovery action. The
contract forbids removing an address that is still an active VASP admin, so admin membership must
be cleared first if that address should be fully detached from the VASP.

## 15. Upgradeability

| Property | Rule |
| --- | --- |
| Pattern | UUPS |
| Upgrade authorization | `DEFAULT_ADMIN_ROLE` |
| V2 version reporting | Derived from `_getInitializedVersion()` in V2 implementations |
| Mutable version slot | Not used for canonical version reporting |

## 16. Events

### 16.1 CHFD Events

| Event |
| --- |
| `MintEvent` |
| `BurnEvent` |
| `CHFDTransferEvent` |
| `ForceTransferEvent` |
| `VaspContractAddressUpdated` |

### 16.2 CHFD_VASP Events

| Event |
| --- |
| `AddVaspEvent` |
| `SetVaspStatusEvent` |
| `AddVaspAdminEvent` |
| `RemoveVaspAdminEvent` |
| `AddHolderEvent` |
| `RemoveHolderEvent` |
| `SetHolderLimitEvent` |
| `SetHolderStatusEvent` |
| `SignatureNonceInvalidated` |

## 17. Invariants

The following properties are intended to hold:

| Invariant | Description |
| --- | --- |
| Single VASP per holder | A holder address is associated with one VASP at a time; reassignment requires issuer-side removal first |
| Nonce monotonicity | Signature nonces only move forward |
| At least one admin per VASP | Last admin cannot be removed |
| Controlled enforcement bypass | Only explicit enforcement paths bypass normal validation |
| Registered recipients for force transfer | Force transfers cannot move balances into unregistered holder addresses |

## 18. Canonical Interfaces and Naming

| Item | Canonical name |
| --- | --- |
| VASP signature executor role | `UPDATE_VASP_ROLE` |
| EIP-712 domain accessor | `DOMAIN_SEPARATOR()` |
| Mint interface | `mint(address to, uint256 amount, bytes32 referenceId)` |
| Permit burn interface | `burnFromWithPermit(...)` |
| Enforcement burn interface | `burnFrom(...)` |

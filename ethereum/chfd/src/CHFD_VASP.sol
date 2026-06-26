// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {
  CannotRemoveLastVaspAdmin,
  ExceedsHolderLimit,
  HolderAlreadyExists,
  HolderDoesNotBelongToVasp,
  HolderDoesNotExist,
  HolderIsVaspAdmin,
  HolderNotActive,
  InvalidHolderAddress,
  InvalidNonce,
  InvalidSignature,
  InvalidStatus,
  InvalidVaspId,
  MaxVaspAdminsReached,
  NotVaspAdmin,
  SignatureExpired,
  VaspAdminAlreadyExists,
  VaspAdminDoesNotExist,
  VaspAlreadyExists,
  VaspDoesNotExist,
  VaspNotActive,
  ZeroAddress
} from "./Errors.sol";
import {
  AddHolderEvent,
  AddVaspAdminEvent,
  AddVaspEvent,
  RemoveHolderEvent,
  RemoveVaspAdminEvent,
  SetHolderLimitEvent,
  SetHolderStatusEvent,
  SignatureNonceInvalidated,
  SetVaspStatusEvent
} from "./Events.sol";
import { HolderStatus, VaspStatus } from "./Statuses.sol";
import {
  AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
  EIP712Upgradeable
} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
  UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract CHFD_VASP is Initializable, AccessControlUpgradeable, EIP712Upgradeable, UUPSUpgradeable {
  bytes32 public constant UPDATE_VASP_ROLE = keccak256("UPDATE_VASP_ROLE");
  bytes32 public constant VALIDATE_TRANSFER_ROLE = keccak256("VALIDATE_TRANSFER_ROLE");
  uint8 public constant MAX_VASP_ADMINS = 10;

  bytes32 private constant ADD_VASP_TYPEHASH =
    keccak256("AddVasp(bytes32 vaspId,address vaspAdminAddress,uint256 nonce,uint256 deadline)");
  bytes32 private constant ADD_VASP_ADMIN_TYPEHASH = keccak256(
    "AddVaspAdmin(bytes32 vaspId,address vaspAdminAddress,uint256 nonce,uint256 deadline)"
  );
  bytes32 private constant REMOVE_VASP_ADMIN_TYPEHASH = keccak256(
    "RemoveVaspAdmin(bytes32 vaspId,address vaspAdminAddress,uint256 nonce,uint256 deadline)"
  );
  bytes32 private constant ADD_HOLDER_TYPEHASH = keccak256(
    "AddHolder(bytes32 vaspId,address holderAddress,uint256 holderLimit,uint8 vaspOwned,uint256 nonce,uint256 deadline)"
  );
  bytes32 private constant SET_HOLDER_LIMIT_TYPEHASH = keccak256(
    "SetHolderLimit(bytes32 vaspId,address holderAddress,uint256 holderLimit,uint256 nonce,uint256 deadline)"
  );
  bytes32 private constant SET_HOLDER_STATUS_TYPEHASH = keccak256(
    "SetHolderStatus(bytes32 vaspId,address holderAddress,uint8 status,uint256 nonce,uint256 deadline)"
  );

  struct Vasp {
    mapping(address => bool) admins;
    uint8 adminCount;
    VaspStatus status;
  }

  mapping(bytes32 => Vasp) private _vasps;

  struct Holder {
    bytes32 vaspId;
    uint256 limit;
    HolderStatus status;
    uint8 vaspOwned;
  }

  mapping(address => Holder) private _holders;
  mapping(address => uint256) public nonces;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  modifier nonZero(address addr) {
    _nonZero(addr);
    _;
  }

  modifier onlyVasp(bytes32 vaspId) {
    _onlyVasp(vaspId);
    _;
  }

  modifier onlyVaspAdmin(bytes32 vaspId) {
    _onlyVaspAdmin(vaspId);
    _;
  }

  modifier onlyHolder(address holderAddress) {
    _onlyHolder(holderAddress);
    _;
  }

  function initialize() public initializer {
    __AccessControl_init();
    __EIP712_init("CHFD_VASP", "1");

    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(UPDATE_VASP_ROLE, _msgSender());
  }

  function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  { }

  function _nonZero(address addr) internal pure {
    if (addr == address(0)) revert ZeroAddress();
  }

  function _onlyVasp(bytes32 vaspId) internal view {
    if (vaspId == bytes32(0)) revert InvalidVaspId();
    if (_vasps[vaspId].status == VaspStatus.None) revert VaspDoesNotExist();
  }

  function _onlyVaspAdmin(bytes32 vaspId) internal view {
    if (!_vasps[vaspId].admins[_msgSender()]) revert NotVaspAdmin();
  }

  function _onlyHolder(address holderAddress) internal view {
    if (holderAddress == address(0)) revert InvalidHolderAddress();
    if (_holders[holderAddress].vaspId == bytes32(0)) revert HolderDoesNotExist();
  }

  function grantWorkerRoles(address worker) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _grantRole(UPDATE_VASP_ROLE, worker);
  }

  function revokeWorkerRoles(address worker) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _revokeRole(UPDATE_VASP_ROLE, worker);
  }

  function grantValidateTransferRole(address validator) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _grantRole(VALIDATE_TRANSFER_ROLE, validator);
  }

  function revokeValidateTransferRole(address validator) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _revokeRole(VALIDATE_TRANSFER_ROLE, validator);
  }

  function getHolderDetails(address holderAddress)
    public
    view
    returns (uint256, HolderStatus, bytes32, uint8)
  {
    Holder storage holder = _holders[holderAddress];
    return (holder.limit, holder.status, holder.vaspId, holder.vaspOwned);
  }

  function getHolderVaspId(address holderAddress) public view returns (bytes32) {
    return _holders[holderAddress].vaspId;
  }

  function getTransferVaspIds(address from, address to) public view returns (bytes32, bytes32) {
    return (_holders[from].vaspId, _holders[to].vaspId);
  }

  function DOMAIN_SEPARATOR() public view returns (bytes32) {
    return _domainSeparatorV4();
  }

  function _hashAddVaspStruct(
    bytes32 vaspId,
    address vaspAdminAddress,
    uint256 nonce,
    uint256 deadline
  ) internal pure returns (bytes32 structHash) {
    return keccak256(abi.encode(ADD_VASP_TYPEHASH, vaspId, vaspAdminAddress, nonce, deadline));
  }

  function _hashAddVaspAdminStruct(
    bytes32 vaspId,
    address vaspAdminAddress,
    uint256 nonce,
    uint256 deadline
  ) internal pure returns (bytes32 structHash) {
    return keccak256(abi.encode(ADD_VASP_ADMIN_TYPEHASH, vaspId, vaspAdminAddress, nonce, deadline));
  }

  function _hashRemoveVaspAdminStruct(
    bytes32 vaspId,
    address vaspAdminAddress,
    uint256 nonce,
    uint256 deadline
  ) internal pure returns (bytes32 structHash) {
    return keccak256(
      abi.encode(REMOVE_VASP_ADMIN_TYPEHASH, vaspId, vaspAdminAddress, nonce, deadline)
    );
  }

  function _hashAddHolderStruct(
    bytes32 vaspId,
    address holderAddress,
    uint256 holderLimit,
    uint8 vaspOwned,
    uint256 nonce,
    uint256 deadline
  ) internal pure returns (bytes32 structHash) {
    return keccak256(
      abi.encode(
        ADD_HOLDER_TYPEHASH, vaspId, holderAddress, holderLimit, vaspOwned, nonce, deadline
      )
    );
  }

  function _hashSetHolderLimitStruct(
    bytes32 vaspId,
    address holderAddress,
    uint256 holderLimit,
    uint256 nonce,
    uint256 deadline
  ) internal pure returns (bytes32 structHash) {
    return keccak256(
      abi.encode(SET_HOLDER_LIMIT_TYPEHASH, vaspId, holderAddress, holderLimit, nonce, deadline)
    );
  }

  function _hashSetHolderStatusStruct(
    bytes32 vaspId,
    address holderAddress,
    HolderStatus status,
    uint256 nonce,
    uint256 deadline
  ) internal pure returns (bytes32 structHash) {
    return keccak256(
      abi.encode(SET_HOLDER_STATUS_TYPEHASH, vaspId, holderAddress, uint8(status), nonce, deadline)
    );
  }

  function _ensureHolder(
    bytes32 vaspId,
    address holderAddress,
    uint256 holderLimit,
    address operator,
    bytes32 referenceId
  ) internal {
    Holder storage holder = _holders[holderAddress];

    if (holder.vaspId == bytes32(0)) {
      holder.vaspId = vaspId;
      holder.limit = holderLimit;
      holder.status = HolderStatus.Active;
      emit AddHolderEvent(operator, referenceId, vaspId, holderAddress, holderLimit, 0);
      return;
    }

    if (holder.vaspId != vaspId) revert HolderAlreadyExists();
  }

  function _useSignatureNonce(address account) internal returns (uint256 current) {
    current = nonces[account];
    nonces[account] = current + 1;
  }

  function invalidateSignatureNonce(uint256 newNonce) public {
    uint256 currentNonce = nonces[_msgSender()];
    if (newNonce <= currentNonce) revert InvalidNonce();

    nonces[_msgSender()] = newNonce;
    emit SignatureNonceInvalidated(_msgSender(), currentNonce, newNonce);
  }

  function _verifyVaspAdminSignature(
    bytes32 vaspId,
    address signer,
    bytes32 structHash,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) internal view {
    // Signature deadlines intentionally use wall-clock expiry, like ERC20 permit-style flows.
    // slither-disable-next-line timestamp
    if (block.timestamp > deadline) revert SignatureExpired();
    if (!_vasps[vaspId].admins[signer]) revert NotVaspAdmin();

    bytes32 digest = _hashTypedDataV4(structHash);
    address recoveredSigner = ECDSA.recover(digest, v, r, s);
    if (recoveredSigner != signer) revert InvalidSignature();
  }

  function _addVaspAdmin(
    bytes32 vaspId,
    address vaspAdminAddress,
    address operator,
    bytes32 referenceId
  ) internal {
    Vasp storage vasp = _vasps[vaspId];
    if (vasp.status != VaspStatus.Active) revert VaspNotActive();
    if (vasp.admins[vaspAdminAddress]) revert VaspAdminAlreadyExists();
    if (vasp.adminCount == MAX_VASP_ADMINS) revert MaxVaspAdminsReached();

    vasp.admins[vaspAdminAddress] = true;
    vasp.adminCount += 1;
    _ensureHolder(vaspId, vaspAdminAddress, 0, operator, referenceId);
    emit AddVaspAdminEvent(operator, referenceId, vaspId, vaspAdminAddress);
  }

  function _removeVaspAdmin(
    bytes32 vaspId,
    address vaspAdminAddress,
    address operator,
    bytes32 referenceId
  ) internal {
    Vasp storage vasp = _vasps[vaspId];
    if (!vasp.admins[vaspAdminAddress]) revert VaspAdminDoesNotExist();
    if (vasp.adminCount == 1) revert CannotRemoveLastVaspAdmin();

    delete vasp.admins[vaspAdminAddress];
    vasp.adminCount -= 1;
    emit RemoveVaspAdminEvent(operator, referenceId, vaspId, vaspAdminAddress);
  }

  function _addHolder(
    bytes32 vaspId,
    address holderAddress,
    uint256 holderLimit,
    uint8 vaspOwned,
    address operator,
    bytes32 referenceId
  ) internal {
    Vasp storage vasp = _vasps[vaspId];
    if (vasp.status != VaspStatus.Active) revert VaspNotActive();
    if (_holders[holderAddress].vaspId != bytes32(0)) revert HolderAlreadyExists();

    _holders[holderAddress].vaspId = vaspId;
    _holders[holderAddress].limit = holderLimit;
    _holders[holderAddress].status = HolderStatus.Active;
    _holders[holderAddress].vaspOwned = vaspOwned;

    emit AddHolderEvent(operator, referenceId, vaspId, holderAddress, holderLimit, vaspOwned);
  }

  function _setHolderLimit(
    bytes32 vaspId,
    address holderAddress,
    uint256 holderLimit,
    address operator,
    bytes32 referenceId
  ) internal {
    if (_holders[holderAddress].vaspId != vaspId) {
      revert HolderDoesNotBelongToVasp();
    }

    uint256 prevHolderLimit = _holders[holderAddress].limit;
    _holders[holderAddress].limit = holderLimit;
    emit SetHolderLimitEvent(
      operator, referenceId, vaspId, holderAddress, prevHolderLimit, holderLimit
    );
  }

  function _setHolderStatus(
    bytes32 vaspId,
    address holderAddress,
    HolderStatus status,
    address operator,
    bytes32 referenceId
  ) internal {
    if (_holders[holderAddress].vaspId != vaspId) {
      revert HolderDoesNotBelongToVasp();
    }
    if (status == HolderStatus.None) revert InvalidStatus();

    HolderStatus prevStatus = _holders[holderAddress].status;
    _holders[holderAddress].status = status;
    emit SetHolderStatusEvent(operator, referenceId, vaspId, holderAddress, prevStatus, status);
  }

  function _removeHolder(
    bytes32 vaspId,
    address holderAddress,
    address operator,
    bytes32 referenceId
  ) internal {
    if (_holders[holderAddress].vaspId != vaspId) {
      revert HolderDoesNotBelongToVasp();
    }
    if (_vasps[vaspId].admins[holderAddress]) revert HolderIsVaspAdmin();

    delete _holders[holderAddress];
    emit RemoveHolderEvent(operator, referenceId, vaspId, holderAddress);
  }

  function addVasp(
    bytes32 vaspId,
    address vaspAdminAddress,
    bytes32 referenceId,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public onlyRole(UPDATE_VASP_ROLE) returns (bytes32) {
    if (vaspId == bytes32(0)) revert InvalidVaspId();
    if (vaspAdminAddress == address(0)) revert ZeroAddress();

    Vasp storage vasp = _vasps[vaspId];
    if (vasp.status != VaspStatus.None) revert VaspAlreadyExists();
    if (_holders[vaspAdminAddress].vaspId != bytes32(0)) revert HolderAlreadyExists();

    uint256 nonce = _useSignatureNonce(vaspAdminAddress);

    bytes32 structHash = _hashAddVaspStruct(vaspId, vaspAdminAddress, nonce, deadline);

    _verifySignature(vaspAdminAddress, structHash, deadline, v, r, s);

    vasp.admins[vaspAdminAddress] = true;
    vasp.adminCount = 1;
    vasp.status = VaspStatus.Active;

    _holders[vaspAdminAddress] =
      Holder({ vaspId: vaspId, limit: 0, status: HolderStatus.Active, vaspOwned: 0 });

    emit AddVaspEvent(_msgSender(), referenceId, vaspId);
    emit AddVaspAdminEvent(_msgSender(), referenceId, vaspId, vaspAdminAddress);
    emit AddHolderEvent(_msgSender(), referenceId, vaspId, vaspAdminAddress, 0, 0);

    return vaspId;
  }

  function setVaspStatus(bytes32 vaspId, VaspStatus status, bytes32 referenceId)
    public
    onlyVasp(vaspId)
    onlyRole(UPDATE_VASP_ROLE)
  {
    if (status == VaspStatus.None) revert InvalidStatus();

    VaspStatus prevStatus = _vasps[vaspId].status;
    _vasps[vaspId].status = status;
    emit SetVaspStatusEvent(_msgSender(), referenceId, vaspId, prevStatus, status);
  }

  function addVaspAdmin(bytes32 vaspId, address vaspAdminAddress, bytes32 referenceId)
    public
    onlyVasp(vaspId)
    onlyVaspAdmin(vaspId)
    nonZero(vaspAdminAddress)
  {
    _addVaspAdmin(vaspId, vaspAdminAddress, _msgSender(), referenceId);
  }

  function removeVaspAdmin(bytes32 vaspId, address vaspAdminAddress, bytes32 referenceId)
    public
    onlyVasp(vaspId)
    onlyVaspAdmin(vaspId)
    nonZero(vaspAdminAddress)
  {
    _removeVaspAdmin(vaspId, vaspAdminAddress, _msgSender(), referenceId);
  }

  function addHolder(
    bytes32 vaspId,
    address holderAddress,
    uint256 holderLimit,
    uint8 vaspOwned,
    bytes32 referenceId
  ) public onlyVasp(vaspId) onlyVaspAdmin(vaspId) nonZero(holderAddress) {
    _addHolder(vaspId, holderAddress, holderLimit, vaspOwned, _msgSender(), referenceId);
  }

  function setHolderLimit(
    bytes32 vaspId,
    address holderAddress,
    uint256 holderLimit,
    bytes32 referenceId
  ) public onlyHolder(holderAddress) onlyVasp(vaspId) onlyVaspAdmin(vaspId) {
    _setHolderLimit(vaspId, holderAddress, holderLimit, _msgSender(), referenceId);
  }

  function setHolderStatus(
    bytes32 vaspId,
    address holderAddress,
    HolderStatus status,
    bytes32 referenceId
  ) public onlyHolder(holderAddress) onlyVasp(vaspId) onlyVaspAdmin(vaspId) {
    _setHolderStatus(vaspId, holderAddress, status, _msgSender(), referenceId);
  }

  function removeHolder(bytes32 vaspId, address holderAddress, bytes32 referenceId)
    public
    onlyRole(UPDATE_VASP_ROLE)
    onlyHolder(holderAddress)
    onlyVasp(vaspId)
  {
    _removeHolder(vaspId, holderAddress, _msgSender(), referenceId);
  }

  function addVaspAdminWithSig(
    bytes32 vaspId,
    address vaspAdminAddress,
    address signer,
    bytes32 referenceId,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public onlyRole(UPDATE_VASP_ROLE) onlyVasp(vaspId) nonZero(vaspAdminAddress) {
    uint256 nonce = _useSignatureNonce(signer);
    bytes32 structHash = _hashAddVaspAdminStruct(vaspId, vaspAdminAddress, nonce, deadline);
    _verifyVaspAdminSignature(vaspId, signer, structHash, deadline, v, r, s);
    _addVaspAdmin(vaspId, vaspAdminAddress, _msgSender(), referenceId);
  }

  function removeVaspAdminWithSig(
    bytes32 vaspId,
    address vaspAdminAddress,
    address signer,
    bytes32 referenceId,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public onlyRole(UPDATE_VASP_ROLE) onlyVasp(vaspId) nonZero(vaspAdminAddress) {
    uint256 nonce = _useSignatureNonce(signer);
    bytes32 structHash = _hashRemoveVaspAdminStruct(vaspId, vaspAdminAddress, nonce, deadline);
    _verifyVaspAdminSignature(vaspId, signer, structHash, deadline, v, r, s);
    _removeVaspAdmin(vaspId, vaspAdminAddress, _msgSender(), referenceId);
  }

  function addHolderWithSig(
    bytes32 vaspId,
    address holderAddress,
    uint256 holderLimit,
    uint8 vaspOwned,
    address signer,
    bytes32 referenceId,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public onlyRole(UPDATE_VASP_ROLE) onlyVasp(vaspId) nonZero(holderAddress) {
    uint256 nonce = _useSignatureNonce(signer);
    bytes32 structHash =
      _hashAddHolderStruct(vaspId, holderAddress, holderLimit, vaspOwned, nonce, deadline);
    _verifyVaspAdminSignature(vaspId, signer, structHash, deadline, v, r, s);
    _addHolder(vaspId, holderAddress, holderLimit, vaspOwned, _msgSender(), referenceId);
  }

  function setHolderLimitWithSig(
    bytes32 vaspId,
    address holderAddress,
    uint256 holderLimit,
    address signer,
    bytes32 referenceId,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public onlyRole(UPDATE_VASP_ROLE) onlyHolder(holderAddress) onlyVasp(vaspId) {
    uint256 nonce = _useSignatureNonce(signer);
    bytes32 structHash =
      _hashSetHolderLimitStruct(vaspId, holderAddress, holderLimit, nonce, deadline);
    _verifyVaspAdminSignature(vaspId, signer, structHash, deadline, v, r, s);
    _setHolderLimit(vaspId, holderAddress, holderLimit, _msgSender(), referenceId);
  }

  function setHolderStatusWithSig(
    bytes32 vaspId,
    address holderAddress,
    HolderStatus status,
    address signer,
    bytes32 referenceId,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public onlyRole(UPDATE_VASP_ROLE) onlyHolder(holderAddress) onlyVasp(vaspId) {
    uint256 nonce = _useSignatureNonce(signer);
    bytes32 structHash = _hashSetHolderStatusStruct(vaspId, holderAddress, status, nonce, deadline);
    _verifyVaspAdminSignature(vaspId, signer, structHash, deadline, v, r, s);
    _setHolderStatus(vaspId, holderAddress, status, _msgSender(), referenceId);
  }

  function validateTransfer(address from, address to, uint256 targetAmount)
    public
    view
    onlyRole(VALIDATE_TRANSFER_ROLE)
  {
    if (from != address(0)) {
      Holder storage fromHolder = _holders[from];
      if (fromHolder.vaspId == bytes32(0)) revert HolderDoesNotExist();
      validateStatus(fromHolder);
    }

    if (to != address(0)) {
      Holder storage toHolder = _holders[to];
      if (toHolder.vaspId == bytes32(0)) revert HolderDoesNotExist();
      validateAmount(toHolder, targetAmount);
    }
  }

  function validateStatus(Holder storage holder) private view {
    Vasp storage vasp = _vasps[holder.vaspId];

    if (vasp.status != VaspStatus.Active) revert VaspNotActive();
    if (holder.status != HolderStatus.Active) revert HolderNotActive();
  }

  function validateAmount(Holder storage holder, uint256 totalHoldingAmount) private view {
    Vasp storage vasp = _vasps[holder.vaspId];

    if (vasp.status != VaspStatus.Active) revert VaspNotActive();
    if (holder.status != HolderStatus.Active) revert HolderNotActive();
    if (totalHoldingAmount > holder.limit) revert ExceedsHolderLimit();
  }

  function _verifySignature(
    address signer,
    bytes32 structHash,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) internal view {
    // Signature deadlines intentionally use wall-clock expiry, like ERC20 permit-style flows.
    // slither-disable-next-line timestamp
    if (block.timestamp > deadline) revert SignatureExpired();

    bytes32 digest = _hashTypedDataV4(structHash);
    address recovered = ECDSA.recover(digest, v, r, s);

    if (recovered != signer) revert InvalidSignature();
  }
}

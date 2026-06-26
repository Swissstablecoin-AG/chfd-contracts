// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {
  ForceTransferReentry,
  HolderDoesNotExist,
  InvalidForceTransferAddress,
  ZeroAddress
} from "./Errors.sol";
import {
  BurnEvent,
  CHFDTransferEvent,
  ForceTransferEvent,
  MintEvent,
  VaspContractAddressUpdated
} from "./Events.sol";
import { ICHFDVasp } from "./ICHFDVasp.sol";
import {
  AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
  ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
  ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
  UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
  PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract CHFD is
  Initializable,
  AccessControlUpgradeable,
  ERC20Upgradeable,
  ERC20PermitUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable
{
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 public constant ENFORCEMENT_ROLE = keccak256("ENFORCEMENT_ROLE");

  address private _vaspContractAddress;
  bool private _forceTransferInProgress;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address vaspMasterAddress) public initializer {
    if (vaspMasterAddress == address(0)) revert ZeroAddress();

    __AccessControl_init();
    __ERC20_init("Swiss Stablecoin", "CHFD");
    __ERC20Permit_init("Swiss Stablecoin");
    __Pausable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(MINTER_ROLE, _msgSender());
    _grantRole(BURNER_ROLE, _msgSender());
    _grantRole(ENFORCEMENT_ROLE, _msgSender());

    _vaspContractAddress = vaspMasterAddress;
  }

  function getVaspContractAddress() public view returns (address) {
    return _vaspContractAddress;
  }

  function decimals() public view virtual override returns (uint8) {
    return 6;
  }

  function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  { }

  function setVaspContractAddress(address vaspContractAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
    if (vaspContractAddress == address(0)) revert ZeroAddress();
    emit VaspContractAddressUpdated(_msgSender(), _vaspContractAddress, vaspContractAddress);
    _vaspContractAddress = vaspContractAddress;
  }

  function grantMintBurnRoles(address worker) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _grantRole(MINTER_ROLE, worker);
    _grantRole(BURNER_ROLE, worker);
  }

  function revokeMintBurnRoles(address worker) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _revokeRole(MINTER_ROLE, worker);
    _revokeRole(BURNER_ROLE, worker);
  }

  function mint(address to, uint256 amount, bytes32 referenceId) public onlyRole(MINTER_ROLE) {
    ICHFDVasp vaspContract = ICHFDVasp(_vaspContractAddress);
    vaspContract.validateTransfer(address(0), to, balanceOf(to) + amount);
    bytes32 vaspId = vaspContract.getHolderVaspId(to);
    _mint(to, amount);
    emit MintEvent(_msgSender(), to, referenceId, amount, vaspId);
  }

  function burnFrom(address from, uint256 amount, bytes32 referenceId)
    public
    onlyRole(ENFORCEMENT_ROLE)
  {
    bytes32 vaspId = ICHFDVasp(_vaspContractAddress).getHolderVaspId(from);
    _beginForceTransfer();
    _burn(from, amount);
    _endForceTransfer();
    emit BurnEvent(_msgSender(), from, referenceId, amount, vaspId);
  }

  function burnFromWithPermit(
    address owner,
    uint256 amount,
    bytes32 referenceId,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public onlyRole(BURNER_ROLE) {
    if (allowance(owner, _msgSender()) < amount) {
      try this.permit(owner, _msgSender(), amount, deadline, v, r, s) { } catch { }
    }

    _spendAllowance(owner, _msgSender(), amount);

    bytes32 vaspId = ICHFDVasp(_vaspContractAddress).getHolderVaspId(owner);

    _beginForceTransfer();
    _burn(owner, amount);
    _endForceTransfer();

    emit BurnEvent(_msgSender(), owner, referenceId, amount, vaspId);
  }

  function pause() public onlyRole(ENFORCEMENT_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ENFORCEMENT_ROLE) {
    _unpause();
  }

  function _beginForceTransfer() internal {
    if (_forceTransferInProgress) revert ForceTransferReentry();
    _forceTransferInProgress = true;
  }

  function _endForceTransfer() internal {
    _forceTransferInProgress = false;
  }

  function forceTransfer(address from, address to, uint256 amount, bytes32 referenceId)
    public
    onlyRole(ENFORCEMENT_ROLE)
    returns (bool)
  {
    if (from == address(0) || to == address(0)) revert InvalidForceTransferAddress();
    bytes32 toVaspId = ICHFDVasp(_vaspContractAddress).getHolderVaspId(to);
    if (toVaspId == bytes32(0)) {
      revert HolderDoesNotExist();
    }

    _beginForceTransfer();
    _update(from, to, amount);
    _endForceTransfer();
    emit ForceTransferEvent(_msgSender(), from, to, referenceId, amount);
    return true;
  }

  function _update(address from, address to, uint256 amount) internal override {
    ICHFDVasp vaspContract = ICHFDVasp(_vaspContractAddress);
    bool forceTransferInProgress = _forceTransferInProgress;

    if (!forceTransferInProgress) {
      _requireNotPaused();
    }

    if (from != address(0) && to != address(0)) {
      if (!forceTransferInProgress) {
        uint256 targetAmount = from == to ? balanceOf(to) : balanceOf(to) + amount;
        vaspContract.validateTransfer(from, to, targetAmount);
      }
    }

    super._update(from, to, amount);

    if (from != address(0) && to != address(0)) {
      (bytes32 fromVaspId, bytes32 toVaspId) = vaspContract.getTransferVaspIds(from, to);
      emit CHFDTransferEvent(from, to, fromVaspId, toVaspId, amount);
    }
  }
}

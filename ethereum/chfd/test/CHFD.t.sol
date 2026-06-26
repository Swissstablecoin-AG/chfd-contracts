// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { CHFD } from "../src/CHFD.sol";
import { CHFD_VASP } from "../src/CHFD_VASP.sol";
import { HolderStatus, VaspStatus } from "../src/Statuses.sol";
import {
  AddHolderEvent,
  AddVaspEvent,
  BurnEvent,
  CHFDTransferEvent,
  ForceTransferEvent,
  MintEvent,
  RemoveHolderEvent,
  SetHolderLimitEvent,
  SetHolderStatusEvent,
  SignatureNonceInvalidated,
  SetVaspStatusEvent
} from "../src/Events.sol";
import {
  VaspAlreadyExists,
  NotVaspAdmin,
  HolderAlreadyExists,
  HolderDoesNotExist,
  HolderIsVaspAdmin,
  HolderNotActive,
  ExceedsHolderLimit,
  VaspNotActive,
  HolderDoesNotBelongToVasp,
  InvalidStatus,
  CannotRemoveLastVaspAdmin,
  ZeroAddress,
  ForceTransferReentry,
  InvalidForceTransferAddress,
  InvalidSignature,
  InvalidNonce
} from "../src/Errors.sol";

contract CHFDForceTransferHarness is CHFD {
  function beginForceTransferTwice() external {
    _beginForceTransfer();
    _beginForceTransfer();
  }
}

contract CHFDTest is Test {
  bytes32 internal constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
  bytes32 internal constant ADD_VASP_TYPEHASH =
    keccak256("AddVasp(bytes32 vaspId,address vaspAdminAddress,uint256 nonce,uint256 deadline)");
  bytes32 internal constant ADD_VASP_ADMIN_TYPEHASH = keccak256(
    "AddVaspAdmin(bytes32 vaspId,address vaspAdminAddress,uint256 nonce,uint256 deadline)"
  );
  bytes32 internal constant REMOVE_VASP_ADMIN_TYPEHASH = keccak256(
    "RemoveVaspAdmin(bytes32 vaspId,address vaspAdminAddress,uint256 nonce,uint256 deadline)"
  );
  bytes32 internal constant ADD_HOLDER_TYPEHASH = keccak256(
    "AddHolder(bytes32 vaspId,address holderAddress,uint256 holderLimit,uint8 vaspOwned,uint256 nonce,uint256 deadline)"
  );
  bytes32 internal constant SET_HOLDER_LIMIT_TYPEHASH = keccak256(
    "SetHolderLimit(bytes32 vaspId,address holderAddress,uint256 holderLimit,uint256 nonce,uint256 deadline)"
  );
  bytes32 internal constant SET_HOLDER_STATUS_TYPEHASH = keccak256(
    "SetHolderStatus(bytes32 vaspId,address holderAddress,uint8 status,uint256 nonce,uint256 deadline)"
  );

  CHFD internal chfd;
  CHFD_VASP internal vasp;

  address internal admin = address(this);
  address internal worker = address(0x100);
  address internal outsider = address(0x101);

  address internal vaspAdmin1;
  address internal vaspAdmin2;

  address internal holder1 = address(0x300);
  address internal holder2 = address(0x301);
  address internal holder3 = address(0x302);
  address internal permitHolder;
  address internal sigAdmin;
  address internal sigAdmin2;
  address internal sigHolder;

  uint256 internal permitHolderKey = 0xA11CE;
  uint256 internal sigAdminKey = 0xB11CE;
  uint256 internal sigAdmin2Key = 0xC11CE;
  uint256 internal sigHolderKey = 0xD11CE;
  uint256 internal vaspAdmin1Key = 0xE11CE;
  uint256 internal vaspAdmin2Key = 0xF11CE;

  bytes32 internal constant VASP_ID_1 = keccak256("VASP_ID_1");
  bytes32 internal constant VASP_ID_2 = keccak256("VASP_ID_2");
  bytes32 internal constant SIG_VASP_ID = keccak256("SIG_VASP_ID");
  bytes32 internal constant TEST_REFERENCE_ID = keccak256("TEST_REFERENCE_ID");

  function setUp() public {
    permitHolder = vm.addr(permitHolderKey);
    sigAdmin = vm.addr(sigAdminKey);
    sigAdmin2 = vm.addr(sigAdmin2Key);
    sigHolder = vm.addr(sigHolderKey);
    vaspAdmin1 = vm.addr(vaspAdmin1Key);
    vaspAdmin2 = vm.addr(vaspAdmin2Key);

    CHFD_VASP vaspImplementation = new CHFD_VASP();
    ERC1967Proxy vaspProxy =
      new ERC1967Proxy(address(vaspImplementation), abi.encodeCall(CHFD_VASP.initialize, ()));
    vasp = CHFD_VASP(address(vaspProxy));

    CHFD chfdImplementation = new CHFD();
    ERC1967Proxy chfdProxy = new ERC1967Proxy(
      address(chfdImplementation), abi.encodeCall(CHFD.initialize, (address(vasp)))
    );
    chfd = CHFD(address(chfdProxy));

    vasp.grantValidateTransferRole(address(chfd));

    _addVaspWithSig(VASP_ID_1, vaspAdmin1, vaspAdmin1Key);

    vm.prank(vaspAdmin1);
    vasp.addHolder(VASP_ID_1, holder1, 10_000, 0, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.addHolder(VASP_ID_1, holder2, 20_000, 0, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.addHolder(VASP_ID_1, permitHolder, 20_000, 0, TEST_REFERENCE_ID);
  }

  function _signTypedData(uint256 privateKey, bytes32 structHash)
    internal
    view
    returns (uint8, bytes32, bytes32)
  {
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vasp.DOMAIN_SEPARATOR(), structHash));
    return vm.sign(privateKey, digest);
  }

  function _checkedTransfer(CHFD token, address to, uint256 amount) internal returns (bool) {
    return token.transfer(to, amount);
  }

  function _addVaspWithSig(bytes32 vaspId, address vaspAdminAddress, uint256 signerKey) internal {
    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(vaspAdminAddress);
    bytes32 structHash =
      keccak256(abi.encode(ADD_VASP_TYPEHASH, vaspId, vaspAdminAddress, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(signerKey, structHash);
    vasp.addVasp(vaspId, vaspAdminAddress, TEST_REFERENCE_ID, deadline, v, r, s);
  }

  function test_initialize_sets_expected_roles_and_vasp_address() public view {
    assertTrue(chfd.hasRole(chfd.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(chfd.hasRole(chfd.MINTER_ROLE(), admin));
    assertTrue(chfd.hasRole(chfd.BURNER_ROLE(), admin));
    assertTrue(chfd.hasRole(chfd.ENFORCEMENT_ROLE(), admin));

    assertTrue(vasp.hasRole(vasp.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(vasp.hasRole(vasp.UPDATE_VASP_ROLE(), admin));
    assertTrue(vasp.hasRole(vasp.VALIDATE_TRANSFER_ROLE(), address(chfd)));

    assertEq(chfd.decimals(), 6);
    assertEq(chfd.getVaspContractAddress(), address(vasp));
  }

  function test_initialize_reverts_when_called_twice() public {
    vm.expectRevert();
    chfd.initialize(address(vasp));

    vm.expectRevert();
    vasp.initialize();
  }

  function test_initialize_reverts_for_zero_vasp_address() public {
    CHFD chfdImplementation = new CHFD();

    vm.expectRevert(ZeroAddress.selector);
    new ERC1967Proxy(address(chfdImplementation), abi.encodeCall(CHFD.initialize, (address(0))));
  }

  function test_domain_separator_uses_token_name() public view {
    bytes32 expectedDomainSeparator = keccak256(
      abi.encode(
        keccak256(
          "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        ),
        keccak256(bytes("Swiss Stablecoin")),
        keccak256(bytes("1")),
        block.chainid,
        address(chfd)
      )
    );

    assertEq(chfd.DOMAIN_SEPARATOR(), expectedDomainSeparator);
  }

  function test_addVasp_registers_vasp_and_initial_admin() public {
    _addVaspWithSig(VASP_ID_2, vaspAdmin2, vaspAdmin2Key);

    (uint256 limit, HolderStatus holderStatus, bytes32 vaspId,) = vasp.getHolderDetails(vaspAdmin2);
    assertEq(limit, 0);
    assertEq(uint8(holderStatus), uint8(HolderStatus.Active));
    assertEq(vaspId, VASP_ID_2);

    vm.prank(vaspAdmin2);
    vasp.addHolder(VASP_ID_2, holder3, 30_000, 0, TEST_REFERENCE_ID);

    (uint256 holder3Limit, HolderStatus holder3Status, bytes32 holder3VaspId,) =
      vasp.getHolderDetails(holder3);
    assertEq(holder3Limit, 30_000);
    assertEq(uint8(holder3Status), uint8(HolderStatus.Active));
    assertEq(holder3VaspId, VASP_ID_2);
  }

  function test_addVasp_emits_operator_and_reference_id() public {
    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(vaspAdmin2);
    bytes32 structHash =
      keccak256(abi.encode(ADD_VASP_TYPEHASH, VASP_ID_2, vaspAdmin2, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(vaspAdmin2Key, structHash);

    vm.expectEmit(true, true, false, true, address(vasp));
    emit AddVaspEvent(address(this), TEST_REFERENCE_ID, VASP_ID_2);
    vasp.addVasp(VASP_ID_2, vaspAdmin2, TEST_REFERENCE_ID, deadline, v, r, s);
  }

  function test_addVasp_reverts_when_duplicate() public {
    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(vaspAdmin1);
    bytes32 structHash =
      keccak256(abi.encode(ADD_VASP_TYPEHASH, VASP_ID_1, vaspAdmin1, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(vaspAdmin1Key, structHash);

    vm.expectRevert(VaspAlreadyExists.selector);
    vasp.addVasp(VASP_ID_1, vaspAdmin1, TEST_REFERENCE_ID, deadline, v, r, s);
  }

  function test_addVasp_reverts_when_initial_admin_is_existing_holder() public {
    uint256 deadline = block.timestamp + 1 days;
    bytes32 vaspId = VASP_ID_2;
    uint256 nonce = vasp.nonces(holder1);
    bytes32 structHash = keccak256(abi.encode(ADD_VASP_TYPEHASH, vaspId, holder1, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(0x1234, structHash);

    vm.expectRevert(HolderAlreadyExists.selector);
    vasp.addVasp(vaspId, holder1, TEST_REFERENCE_ID, deadline, v, r, s);
  }

  function test_only_update_vasp_role_can_add_vasp() public {
    uint256 deadline = block.timestamp + 1 days;
    bytes32 vaspId = VASP_ID_2;
    uint256 nonce = vasp.nonces(vaspAdmin2);
    bytes32 structHash =
      keccak256(abi.encode(ADD_VASP_TYPEHASH, vaspId, vaspAdmin2, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(vaspAdmin2Key, structHash);

    vm.prank(outsider);
    vm.expectRevert();
    vasp.addVasp(vaspId, vaspAdmin2, TEST_REFERENCE_ID, deadline, v, r, s);
  }

  function test_vasp_admin_can_add_another_vasp_admin() public {
    vm.prank(vaspAdmin1);
    vasp.addVaspAdmin(VASP_ID_1, vaspAdmin2, TEST_REFERENCE_ID);

    (uint256 limit, HolderStatus status, bytes32 vaspId,) = vasp.getHolderDetails(vaspAdmin2);
    assertEq(limit, 0);
    assertEq(uint8(status), uint8(HolderStatus.Active));
    assertEq(vaspId, VASP_ID_1);

    vm.prank(vaspAdmin2);
    vasp.addHolder(VASP_ID_1, holder3, 30_000, 0, TEST_REFERENCE_ID);

    (uint256 holder3Limit, HolderStatus holder3Status, bytes32 holder3VaspId,) =
      vasp.getHolderDetails(holder3);
    assertEq(holder3Limit, 30_000);
    assertEq(uint8(holder3Status), uint8(HolderStatus.Active));
    assertEq(holder3VaspId, VASP_ID_1);
  }

  function test_addVaspAdmin_emits_AddHolderEvent_for_new_admin() public {
    vm.expectEmit(true, true, false, true, address(vasp));
    emit AddHolderEvent(vaspAdmin1, TEST_REFERENCE_ID, VASP_ID_1, vaspAdmin2, 0, 0);

    vm.prank(vaspAdmin1);
    vasp.addVaspAdmin(VASP_ID_1, vaspAdmin2, TEST_REFERENCE_ID);
  }

  function test_non_vasp_admin_cannot_add_vasp_admin() public {
    vm.prank(outsider);
    vm.expectRevert(NotVaspAdmin.selector);
    vasp.addVaspAdmin(VASP_ID_1, vaspAdmin2, TEST_REFERENCE_ID);
  }

  function test_addVaspAdminWithSig_succeeds() public {
    _addVaspWithSig(SIG_VASP_ID, sigAdmin, sigAdminKey);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(sigAdmin);
    bytes32 structHash =
      keccak256(abi.encode(ADD_VASP_ADMIN_TYPEHASH, SIG_VASP_ID, sigAdmin2, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(sigAdminKey, structHash);

    vasp.addVaspAdminWithSig(SIG_VASP_ID, sigAdmin2, sigAdmin, TEST_REFERENCE_ID, deadline, v, r, s);

    vm.prank(sigAdmin2);
    vasp.addHolder(SIG_VASP_ID, sigHolder, 42_000, 0, TEST_REFERENCE_ID);

    (uint256 limit, HolderStatus status, bytes32 vaspId,) = vasp.getHolderDetails(sigHolder);
    assertEq(limit, 42_000);
    assertEq(uint8(status), uint8(HolderStatus.Active));
    assertEq(vaspId, SIG_VASP_ID);
  }

  function test_addVaspAdminWithSig_reverts_without_update_vasp_role() public {
    _addVaspWithSig(SIG_VASP_ID, sigAdmin, sigAdminKey);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(sigAdmin);
    bytes32 structHash =
      keccak256(abi.encode(ADD_VASP_ADMIN_TYPEHASH, SIG_VASP_ID, sigAdmin2, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(sigAdminKey, structHash);

    vm.prank(worker);
    vm.expectRevert();
    vasp.addVaspAdminWithSig(SIG_VASP_ID, sigAdmin2, sigAdmin, TEST_REFERENCE_ID, deadline, v, r, s);
  }

  function test_addVaspAdmin_reverts_if_vasp_is_not_active() public {
    vasp.setVaspStatus(VASP_ID_1, VaspStatus.Blocked, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vm.expectRevert(VaspNotActive.selector);
    vasp.addVaspAdmin(VASP_ID_1, vaspAdmin2, TEST_REFERENCE_ID);
  }

  function test_addVaspAdminWithSig_reverts_if_vasp_is_not_active() public {
    _addVaspWithSig(SIG_VASP_ID, sigAdmin, sigAdminKey);
    vasp.setVaspStatus(SIG_VASP_ID, VaspStatus.Blocked, TEST_REFERENCE_ID);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(sigAdmin);
    bytes32 structHash =
      keccak256(abi.encode(ADD_VASP_ADMIN_TYPEHASH, SIG_VASP_ID, sigAdmin2, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(sigAdminKey, structHash);

    vm.expectRevert(VaspNotActive.selector);
    vasp.addVaspAdminWithSig(SIG_VASP_ID, sigAdmin2, sigAdmin, TEST_REFERENCE_ID, deadline, v, r, s);
  }

  function test_removeVaspAdmin_reverts_when_removing_last_admin() public {
    vm.prank(vaspAdmin1);
    vm.expectRevert(CannotRemoveLastVaspAdmin.selector);
    vasp.removeVaspAdmin(VASP_ID_1, vaspAdmin1, TEST_REFERENCE_ID);
  }

  function test_removeVaspAdminWithSig_succeeds() public {
    _addVaspWithSig(SIG_VASP_ID, sigAdmin, sigAdminKey);

    vm.prank(sigAdmin);
    vasp.addVaspAdmin(SIG_VASP_ID, sigAdmin2, TEST_REFERENCE_ID);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(sigAdmin);
    bytes32 structHash =
      keccak256(abi.encode(REMOVE_VASP_ADMIN_TYPEHASH, SIG_VASP_ID, sigAdmin2, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(sigAdminKey, structHash);

    vasp.removeVaspAdminWithSig(
      SIG_VASP_ID, sigAdmin2, sigAdmin, TEST_REFERENCE_ID, deadline, v, r, s
    );

    vm.prank(sigAdmin2);
    vm.expectRevert(NotVaspAdmin.selector);
    vasp.addHolder(SIG_VASP_ID, holder3, 30_000, 0, TEST_REFERENCE_ID);
  }

  function test_removeHolder_succeeds_for_update_vasp_role() public {
    vm.expectEmit(true, true, true, true, address(vasp));
    emit RemoveHolderEvent(address(this), TEST_REFERENCE_ID, VASP_ID_1, holder2);
    vasp.removeHolder(VASP_ID_1, holder2, TEST_REFERENCE_ID);

    (uint256 limit, HolderStatus status, bytes32 vaspId, uint8 vaspOwned) =
      vasp.getHolderDetails(holder2);
    assertEq(limit, 0);
    assertEq(uint8(status), uint8(HolderStatus.None));
    assertEq(vaspId, bytes32(0));
    assertEq(vaspOwned, 0);

    vm.expectRevert(HolderDoesNotExist.selector);
    chfd.mint(holder2, 1, TEST_REFERENCE_ID);
  }

  function test_removeHolder_reverts_without_update_vasp_role() public {
    vm.prank(vaspAdmin1);
    vm.expectRevert();
    vasp.removeHolder(VASP_ID_1, holder2, TEST_REFERENCE_ID);
  }

  function test_removeHolder_reverts_when_holder_belongs_to_different_vasp() public {
    _addVaspWithSig(VASP_ID_2, vaspAdmin2, vaspAdmin2Key);

    vm.expectRevert(HolderDoesNotBelongToVasp.selector);
    vasp.removeHolder(VASP_ID_2, holder1, TEST_REFERENCE_ID);
  }

  function test_removeHolder_reverts_while_holder_is_active_vasp_admin() public {
    vm.expectRevert(HolderIsVaspAdmin.selector);
    vasp.removeHolder(VASP_ID_1, vaspAdmin1, TEST_REFERENCE_ID);
  }

  function test_removeHolder_succeeds_after_admin_membership_is_removed() public {
    vm.prank(vaspAdmin1);
    vasp.addVaspAdmin(VASP_ID_1, vaspAdmin2, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.removeVaspAdmin(VASP_ID_1, vaspAdmin2, TEST_REFERENCE_ID);

    vasp.removeHolder(VASP_ID_1, vaspAdmin2, TEST_REFERENCE_ID);

    (,, bytes32 vaspId,) = vasp.getHolderDetails(vaspAdmin2);
    assertEq(vaspId, bytes32(0));
  }

  function test_addHolderWithSig_succeeds() public {
    _addVaspWithSig(SIG_VASP_ID, sigAdmin, sigAdminKey);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(sigAdmin);
    bytes32 structHash = keccak256(
      abi.encode(ADD_HOLDER_TYPEHASH, SIG_VASP_ID, sigHolder, 42_000, uint8(1), nonce, deadline)
    );
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(sigAdminKey, structHash);

    vasp.addHolderWithSig(
      SIG_VASP_ID, sigHolder, 42_000, 1, sigAdmin, TEST_REFERENCE_ID, deadline, v, r, s
    );

    (uint256 limit, HolderStatus status, bytes32 vaspId, uint8 vaspOwned) =
      vasp.getHolderDetails(sigHolder);
    assertEq(limit, 42_000);
    assertEq(uint8(status), uint8(HolderStatus.Active));
    assertEq(vaspId, SIG_VASP_ID);
    assertEq(vaspOwned, 1);
  }

  function test_setHolderLimitWithSig_succeeds() public {
    _addVaspWithSig(SIG_VASP_ID, sigAdmin, sigAdminKey);

    vm.prank(sigAdmin);
    vasp.addHolder(SIG_VASP_ID, sigHolder, 10_000, 0, TEST_REFERENCE_ID);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(sigAdmin);
    bytes32 structHash = keccak256(
      abi.encode(SET_HOLDER_LIMIT_TYPEHASH, SIG_VASP_ID, sigHolder, 55_000, nonce, deadline)
    );
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(sigAdminKey, structHash);

    vasp.setHolderLimitWithSig(
      SIG_VASP_ID, sigHolder, 55_000, sigAdmin, TEST_REFERENCE_ID, deadline, v, r, s
    );

    (uint256 limit,,,) = vasp.getHolderDetails(sigHolder);
    assertEq(limit, 55_000);
  }

  function test_setHolderStatusWithSig_succeeds() public {
    _addVaspWithSig(SIG_VASP_ID, sigAdmin, sigAdminKey);

    vm.prank(sigAdmin);
    vasp.addHolder(SIG_VASP_ID, sigHolder, 10_000, 0, TEST_REFERENCE_ID);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(sigAdmin);
    bytes32 structHash = keccak256(
      abi.encode(
        SET_HOLDER_STATUS_TYPEHASH,
        SIG_VASP_ID,
        sigHolder,
        uint8(HolderStatus.Frozen),
        nonce,
        deadline
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(sigAdminKey, structHash);

    vasp.setHolderStatusWithSig(
      SIG_VASP_ID, sigHolder, HolderStatus.Frozen, sigAdmin, TEST_REFERENCE_ID, deadline, v, r, s
    );

    (, HolderStatus status,,) = vasp.getHolderDetails(sigHolder);
    assertEq(uint8(status), uint8(HolderStatus.Frozen));
  }

  function test_setHolderStatusWithSig_reverts_without_update_vasp_role() public {
    _addVaspWithSig(SIG_VASP_ID, sigAdmin, sigAdminKey);

    vm.prank(sigAdmin);
    vasp.addHolder(SIG_VASP_ID, sigHolder, 10_000, 0, TEST_REFERENCE_ID);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(sigAdmin);
    bytes32 structHash = keccak256(
      abi.encode(
        SET_HOLDER_STATUS_TYPEHASH,
        SIG_VASP_ID,
        sigHolder,
        uint8(HolderStatus.Frozen),
        nonce,
        deadline
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(sigAdminKey, structHash);

    vm.prank(worker);
    vm.expectRevert();
    vasp.setHolderStatusWithSig(
      SIG_VASP_ID, sigHolder, HolderStatus.Frozen, sigAdmin, TEST_REFERENCE_ID, deadline, v, r, s
    );
  }

  function test_invalidateSignatureNonce_advances_nonce() public {
    assertEq(vasp.nonces(sigAdmin), 0);

    vm.prank(sigAdmin);
    vm.expectEmit(true, false, false, true, address(vasp));
    emit SignatureNonceInvalidated(sigAdmin, 0, 3);
    vasp.invalidateSignatureNonce(3);

    assertEq(vasp.nonces(sigAdmin), 3);
  }

  function test_invalidateSignatureNonce_reverts_if_not_advanced() public {
    vm.prank(sigAdmin);
    vm.expectRevert(InvalidNonce.selector);
    vasp.invalidateSignatureNonce(0);
  }

  function test_addHolderWithSig_reverts_after_signer_invalidates_nonce() public {
    _addVaspWithSig(SIG_VASP_ID, sigAdmin, sigAdminKey);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(sigAdmin);
    bytes32 structHash = keccak256(
      abi.encode(ADD_HOLDER_TYPEHASH, SIG_VASP_ID, sigHolder, 42_000, uint8(1), nonce, deadline)
    );
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(sigAdminKey, structHash);

    vm.prank(sigAdmin);
    vasp.invalidateSignatureNonce(nonce + 1);

    vm.expectRevert(InvalidSignature.selector);
    vasp.addHolderWithSig(
      SIG_VASP_ID, sigHolder, 42_000, 1, sigAdmin, TEST_REFERENCE_ID, deadline, v, r, s
    );
  }

  function test_vasp_admin_can_add_holder() public {
    vm.prank(vaspAdmin1);
    vasp.addHolder(VASP_ID_1, holder3, 30_000, 0, TEST_REFERENCE_ID);

    (uint256 limit, HolderStatus status, bytes32 vaspId, uint8 vaspOwned) =
      vasp.getHolderDetails(holder3);

    assertEq(limit, 30_000);
    assertEq(uint8(status), uint8(HolderStatus.Active));
    assertEq(vaspId, VASP_ID_1);
    assertEq(vaspOwned, 0);
  }

  function test_vasp_admin_can_add_vasp_owned_holder() public {
    vm.expectEmit(true, true, false, true, address(vasp));
    emit AddHolderEvent(vaspAdmin1, TEST_REFERENCE_ID, VASP_ID_1, holder3, 30_000, 1);

    vm.prank(vaspAdmin1);
    vasp.addHolder(VASP_ID_1, holder3, 30_000, 1, TEST_REFERENCE_ID);

    (,,, uint8 vaspOwned) = vasp.getHolderDetails(holder3);
    assertEq(vaspOwned, 1);
  }

  function test_addHolder_reverts_for_existing_holder() public {
    vm.prank(vaspAdmin1);
    vm.expectRevert(HolderAlreadyExists.selector);
    vasp.addHolder(VASP_ID_1, holder1, 30_000, 0, TEST_REFERENCE_ID);
  }

  function test_addHolder_reverts_if_holder_address_is_existing_vasp_admin_holder() public {
    vm.prank(vaspAdmin1);
    vm.expectRevert(HolderAlreadyExists.selector);
    vasp.addHolder(VASP_ID_1, vaspAdmin1, 30_000, 0, TEST_REFERENCE_ID);
  }

  function test_addHolder_reverts_if_vasp_is_not_active() public {
    vasp.setVaspStatus(VASP_ID_1, VaspStatus.Blocked, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vm.expectRevert(VaspNotActive.selector);
    vasp.addHolder(VASP_ID_1, holder3, 30_000, 0, TEST_REFERENCE_ID);
  }

  function test_grantWorkerRoles_allows_worker_to_mint_and_burn() public {
    chfd.grantMintBurnRoles(worker);
    chfd.grantRole(chfd.ENFORCEMENT_ROLE(), worker);

    assertTrue(chfd.hasRole(chfd.MINTER_ROLE(), worker));
    assertTrue(chfd.hasRole(chfd.BURNER_ROLE(), worker));
    assertTrue(chfd.hasRole(chfd.ENFORCEMENT_ROLE(), worker));

    vm.prank(worker);
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    assertEq(chfd.balanceOf(holder1), 500);

    vm.prank(worker);
    chfd.burnFrom(holder1, 200, TEST_REFERENCE_ID);

    assertEq(chfd.balanceOf(holder1), 300);
  }

  function test_revokeWorkerRoles_removes_worker_permissions() public {
    chfd.grantMintBurnRoles(worker);
    chfd.revokeMintBurnRoles(worker);

    assertFalse(chfd.hasRole(chfd.MINTER_ROLE(), worker));
    assertFalse(chfd.hasRole(chfd.BURNER_ROLE(), worker));

    vm.prank(worker);
    vm.expectRevert();
    chfd.mint(holder1, 100, TEST_REFERENCE_ID);
  }

  function test_only_minter_can_mint() public {
    vm.prank(outsider);
    vm.expectRevert();
    chfd.mint(holder1, 100, TEST_REFERENCE_ID);
  }

  function test_mint_succeeds() public {
    chfd.mint(holder1, 9_999, TEST_REFERENCE_ID);
    assertEq(chfd.balanceOf(holder1), 9_999);
  }

  function test_mint_emits_reference_id() public {
    vm.expectEmit(true, true, true, true, address(chfd));
    emit MintEvent(address(this), holder1, TEST_REFERENCE_ID, 9_999, VASP_ID_1);

    chfd.mint(holder1, 9_999, TEST_REFERENCE_ID);
  }

  function test_mint_reverts_if_receiver_holder_is_inactive() public {
    vm.prank(vaspAdmin1);
    vasp.setHolderStatus(VASP_ID_1, holder1, HolderStatus.Blocked, TEST_REFERENCE_ID);

    vm.expectRevert(HolderNotActive.selector);
    chfd.mint(holder1, 100, TEST_REFERENCE_ID);
  }

  function test_burnFrom_succeeds_without_allowance() public {
    chfd.grantRole(chfd.ENFORCEMENT_ROLE(), worker);
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vm.prank(worker);
    chfd.burnFrom(holder1, 250, TEST_REFERENCE_ID);

    assertEq(chfd.balanceOf(holder1), 250);
  }

  function test_burnFrom_emits_reference_id() public {
    chfd.grantRole(chfd.ENFORCEMENT_ROLE(), worker);
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vm.prank(worker);
    vm.expectEmit(true, true, true, true, address(chfd));
    emit BurnEvent(worker, holder1, TEST_REFERENCE_ID, 250, VASP_ID_1);
    chfd.burnFrom(holder1, 250, TEST_REFERENCE_ID);
  }

  function test_burnFrom_succeeds_for_blocked_holder() public {
    chfd.grantRole(chfd.ENFORCEMENT_ROLE(), worker);
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.setHolderStatus(VASP_ID_1, holder1, HolderStatus.Blocked, TEST_REFERENCE_ID);

    vm.prank(worker);
    chfd.burnFrom(holder1, 250, TEST_REFERENCE_ID);

    assertEq(chfd.balanceOf(holder1), 250);
  }

  function test_burnFrom_succeeds_while_paused() public {
    chfd.grantRole(chfd.ENFORCEMENT_ROLE(), worker);
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);
    chfd.pause();

    vm.prank(worker);
    chfd.burnFrom(holder1, 250, TEST_REFERENCE_ID);

    assertEq(chfd.balanceOf(holder1), 250);
  }

  function test_only_enforcement_role_can_burnFrom() public {
    chfd.grantMintBurnRoles(worker);
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vm.prank(worker);
    vm.expectRevert();
    chfd.burnFrom(holder1, 100, TEST_REFERENCE_ID);
  }

  function test_burnFromWithPermit_succeeds() public {
    chfd.grantMintBurnRoles(worker);
    chfd.mint(permitHolder, 500, TEST_REFERENCE_ID);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = chfd.nonces(permitHolder);
    bytes32 structHash =
      keccak256(abi.encode(PERMIT_TYPEHASH, permitHolder, worker, 200, nonce, deadline));
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", chfd.DOMAIN_SEPARATOR(), structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitHolderKey, digest);

    vm.prank(worker);
    chfd.burnFromWithPermit(permitHolder, 200, TEST_REFERENCE_ID, deadline, v, r, s);

    assertEq(chfd.balanceOf(permitHolder), 300);
    assertEq(chfd.allowance(permitHolder, worker), 0);
  }

  function test_burnFromWithPermit_succeeds_if_permit_was_front_run() public {
    chfd.grantMintBurnRoles(worker);
    chfd.mint(permitHolder, 500, TEST_REFERENCE_ID);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = chfd.nonces(permitHolder);
    bytes32 structHash =
      keccak256(abi.encode(PERMIT_TYPEHASH, permitHolder, worker, 200, nonce, deadline));
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", chfd.DOMAIN_SEPARATOR(), structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitHolderKey, digest);

    vm.prank(outsider);
    chfd.permit(permitHolder, worker, 200, deadline, v, r, s);

    vm.prank(worker);
    chfd.burnFromWithPermit(permitHolder, 200, TEST_REFERENCE_ID, deadline, v, r, s);

    assertEq(chfd.balanceOf(permitHolder), 300);
    assertEq(chfd.allowance(permitHolder, worker), 0);
  }

  function test_burnFromWithPermit_succeeds_if_owner_holder_is_blocked() public {
    chfd.grantMintBurnRoles(worker);
    chfd.mint(permitHolder, 500, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.setHolderStatus(VASP_ID_1, permitHolder, HolderStatus.Blocked, TEST_REFERENCE_ID);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = chfd.nonces(permitHolder);
    bytes32 structHash =
      keccak256(abi.encode(PERMIT_TYPEHASH, permitHolder, worker, 200, nonce, deadline));
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", chfd.DOMAIN_SEPARATOR(), structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitHolderKey, digest);

    vm.prank(worker);
    chfd.burnFromWithPermit(permitHolder, 200, TEST_REFERENCE_ID, deadline, v, r, s);

    assertEq(chfd.balanceOf(permitHolder), 300);
    assertEq(chfd.allowance(permitHolder, worker), 0);
  }

  function test_burnFromWithPermit_succeeds_while_paused() public {
    chfd.grantMintBurnRoles(worker);
    chfd.mint(permitHolder, 500, TEST_REFERENCE_ID);
    chfd.pause();

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = chfd.nonces(permitHolder);
    bytes32 structHash =
      keccak256(abi.encode(PERMIT_TYPEHASH, permitHolder, worker, 200, nonce, deadline));
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", chfd.DOMAIN_SEPARATOR(), structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitHolderKey, digest);

    vm.prank(worker);
    chfd.burnFromWithPermit(permitHolder, 200, TEST_REFERENCE_ID, deadline, v, r, s);

    assertEq(chfd.balanceOf(permitHolder), 300);
    assertEq(chfd.allowance(permitHolder, worker), 0);
  }

  function test_transfer_between_registered_active_holders_succeeds() public {
    chfd.mint(holder1, 1_000, TEST_REFERENCE_ID);

    vm.prank(holder1);
    vm.expectEmit(address(chfd));
    emit CHFDTransferEvent(holder1, holder2, VASP_ID_1, VASP_ID_1, 400);
    bool ok = chfd.transfer(holder2, 400);

    assertTrue(ok);
    assertEq(chfd.balanceOf(holder1), 600);
    assertEq(chfd.balanceOf(holder2), 400);
  }

  function test_pause_blocks_regular_transfers() public {
    chfd.mint(holder1, 1_000, TEST_REFERENCE_ID);
    chfd.pause();

    vm.prank(holder1);
    vm.expectRevert();
    _checkedTransfer(chfd, holder2, 100);
  }

  function test_forceTransfer_succeeds_while_paused_and_bypasses_vasp_validation() public {
    chfd.mint(holder1, 1_000, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.setHolderStatus(VASP_ID_1, holder1, HolderStatus.Blocked, TEST_REFERENCE_ID);

    chfd.pause();
    bool ok = chfd.forceTransfer(holder1, holder2, 250, TEST_REFERENCE_ID);

    assertTrue(ok);
    assertEq(chfd.balanceOf(holder1), 750);
    assertEq(chfd.balanceOf(holder2), 250);
  }

  function test_forceTransfer_emits_operator_event() public {
    chfd.mint(holder1, 1_000, TEST_REFERENCE_ID);
    chfd.pause();

    vm.expectEmit(true, true, true, true, address(chfd));
    emit ForceTransferEvent(address(this), holder1, holder2, TEST_REFERENCE_ID, 250);
    chfd.forceTransfer(holder1, holder2, 250, TEST_REFERENCE_ID);
  }

  function test_validateTransfer_reverts_for_unauthorized_caller() public {
    vm.prank(outsider);
    vm.expectRevert();
    vasp.validateTransfer(holder1, holder2, 100);
  }

  function test_only_enforcement_role_can_pause() public {
    vm.prank(outsider);
    vm.expectRevert();
    chfd.pause();
  }

  function test_only_enforcement_role_can_force_transfer() public {
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vm.prank(outsider);
    vm.expectRevert();
    chfd.forceTransfer(holder1, holder2, 100, TEST_REFERENCE_ID);
  }

  function test_forceTransfer_reverts_for_zero_from_address() public {
    vm.expectRevert(InvalidForceTransferAddress.selector);
    chfd.forceTransfer(address(0), holder2, 100, TEST_REFERENCE_ID);
  }

  function test_forceTransfer_reverts_for_zero_to_address() public {
    vm.expectRevert(InvalidForceTransferAddress.selector);
    chfd.forceTransfer(holder1, address(0), 100, TEST_REFERENCE_ID);
  }

  function test_forceTransfer_reverts_if_receiver_not_registered() public {
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vm.expectRevert(HolderDoesNotExist.selector);
    chfd.forceTransfer(holder1, holder3, 100, TEST_REFERENCE_ID);
  }

  function test_beginForceTransfer_reverts_on_reentry() public {
    CHFDForceTransferHarness harness = new CHFDForceTransferHarness();

    vm.expectRevert(ForceTransferReentry.selector);
    harness.beginForceTransferTwice();
  }

  function test_transfer_reverts_if_receiver_not_registered() public {
    chfd.mint(holder1, 1_000, TEST_REFERENCE_ID);

    vm.prank(holder1);
    vm.expectRevert(HolderDoesNotExist.selector);
    _checkedTransfer(chfd, holder3, 100);
  }

  function test_transfer_reverts_if_sender_holder_is_inactive() public {
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.setHolderStatus(VASP_ID_1, holder1, HolderStatus.Blocked, TEST_REFERENCE_ID);

    vm.prank(holder1);
    vm.expectRevert(HolderNotActive.selector);
    _checkedTransfer(chfd, holder2, 100);
  }

  function test_transfer_reverts_if_receiver_holder_is_inactive() public {
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.setHolderStatus(VASP_ID_1, holder2, HolderStatus.Frozen, TEST_REFERENCE_ID);

    vm.prank(holder1);
    vm.expectRevert(HolderNotActive.selector);
    _checkedTransfer(chfd, holder2, 100);
  }

  function test_transfer_reverts_if_receiver_would_exceed_limit() public {
    chfd.mint(holder1, 10_000, TEST_REFERENCE_ID);
    chfd.mint(holder2, 19_900, TEST_REFERENCE_ID);

    vm.prank(holder1);
    vm.expectRevert(ExceedsHolderLimit.selector);
    _checkedTransfer(chfd, holder2, 101);
  }

  function test_self_transfer_at_limit_succeeds() public {
    vm.prank(vaspAdmin1);
    vasp.setHolderLimit(VASP_ID_1, holder1, 10_000, TEST_REFERENCE_ID);

    chfd.mint(holder1, 10_000, TEST_REFERENCE_ID);

    vm.prank(holder1);
    bool ok = _checkedTransfer(chfd, holder1, 100);

    assertTrue(ok);
    assertEq(chfd.balanceOf(holder1), 10_000);
  }

  function test_transfer_reverts_if_vasp_is_not_active() public {
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vasp.setVaspStatus(VASP_ID_1, VaspStatus.Blocked, TEST_REFERENCE_ID);

    vm.prank(holder1);
    vm.expectRevert(VaspNotActive.selector);
    _checkedTransfer(chfd, holder2, 100);
  }

  function test_setVaspStatus_reverts_when_status_is_none() public {
    vm.expectRevert(InvalidStatus.selector);
    vasp.setVaspStatus(VASP_ID_1, VaspStatus.None, TEST_REFERENCE_ID);
  }

  function test_setVaspStatus_emits_prev_and_new_status() public {
    vm.expectEmit(true, true, false, true, address(vasp));
    emit SetVaspStatusEvent(
      address(this), TEST_REFERENCE_ID, VASP_ID_1, VaspStatus.Active, VaspStatus.Blocked
    );
    vasp.setVaspStatus(VASP_ID_1, VaspStatus.Blocked, TEST_REFERENCE_ID);
  }

  function test_setHolderLimit_updates_limit() public {
    vm.prank(vaspAdmin1);
    vm.expectEmit(true, true, false, true, address(vasp));
    emit SetHolderLimitEvent(vaspAdmin1, TEST_REFERENCE_ID, VASP_ID_1, holder1, 10_000, 55_000);
    vasp.setHolderLimit(VASP_ID_1, holder1, 55_000, TEST_REFERENCE_ID);

    (uint256 limit,,,) = vasp.getHolderDetails(holder1);
    assertEq(limit, 55_000);
  }

  function test_setHolderLimit_succeeds_while_vasp_is_blocked() public {
    vasp.setVaspStatus(VASP_ID_1, VaspStatus.Blocked, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.setHolderLimit(VASP_ID_1, holder1, 55_000, TEST_REFERENCE_ID);

    (uint256 limit,,,) = vasp.getHolderDetails(holder1);
    assertEq(limit, 55_000);
  }

  function test_setHolderLimit_reverts_when_holder_belongs_to_different_vasp() public {
    _addVaspWithSig(VASP_ID_2, vaspAdmin2, vaspAdmin2Key);

    vm.prank(vaspAdmin2);
    vm.expectRevert(HolderDoesNotBelongToVasp.selector);
    vasp.setHolderLimit(VASP_ID_2, holder1, 55_000, TEST_REFERENCE_ID);
  }

  function test_setHolderStatus_updates_status() public {
    vm.expectEmit(true, true, false, true, address(vasp));
    emit SetHolderStatusEvent(
      vaspAdmin1, TEST_REFERENCE_ID, VASP_ID_1, holder1, HolderStatus.Active, HolderStatus.Blocked
    );

    vm.prank(vaspAdmin1);
    vasp.setHolderStatus(VASP_ID_1, holder1, HolderStatus.Blocked, TEST_REFERENCE_ID);

    (, HolderStatus status,,) = vasp.getHolderDetails(holder1);
    assertEq(uint8(status), uint8(HolderStatus.Blocked));
  }

  function test_setHolderStatus_succeeds_while_vasp_is_blocked() public {
    vasp.setVaspStatus(VASP_ID_1, VaspStatus.Blocked, TEST_REFERENCE_ID);

    vm.prank(vaspAdmin1);
    vasp.setHolderStatus(VASP_ID_1, holder1, HolderStatus.Blocked, TEST_REFERENCE_ID);

    (, HolderStatus status,,) = vasp.getHolderDetails(holder1);
    assertEq(uint8(status), uint8(HolderStatus.Blocked));
  }

  function test_setHolderStatus_reverts_when_status_is_none() public {
    vm.prank(vaspAdmin1);
    vm.expectRevert(InvalidStatus.selector);
    vasp.setHolderStatus(VASP_ID_1, holder1, HolderStatus.None, TEST_REFERENCE_ID);
  }

  function test_setHolderStatus_reverts_when_holder_belongs_to_different_vasp() public {
    _addVaspWithSig(VASP_ID_2, vaspAdmin2, vaspAdmin2Key);

    vm.prank(vaspAdmin2);
    vm.expectRevert(HolderDoesNotBelongToVasp.selector);
    vasp.setHolderStatus(VASP_ID_2, holder1, HolderStatus.Blocked, TEST_REFERENCE_ID);
  }

  function test_only_vasp_admin_can_set_holder_limit() public {
    vm.prank(outsider);
    vm.expectRevert(NotVaspAdmin.selector);
    vasp.setHolderLimit(VASP_ID_1, holder1, 50_000, TEST_REFERENCE_ID);
  }

  function test_only_vasp_admin_can_set_holder_status() public {
    vm.prank(outsider);
    vm.expectRevert(NotVaspAdmin.selector);
    vasp.setHolderStatus(VASP_ID_1, holder1, HolderStatus.Blocked, TEST_REFERENCE_ID);
  }

  function test_setVaspContractAddress_updates_chfd_validation_source() public {
    CHFD_VASP newVaspImplementation = new CHFD_VASP();
    ERC1967Proxy newVaspProxy =
      new ERC1967Proxy(address(newVaspImplementation), abi.encodeCall(CHFD_VASP.initialize, ()));
    CHFD_VASP newVasp = CHFD_VASP(address(newVaspProxy));

    newVasp.grantValidateTransferRole(address(chfd));

    // use an address with a real known private key, not address(this)
    uint256 newVaspAdminKey = 0xE11CE;
    address newVaspAdmin = vm.addr(newVaspAdminKey);

    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = newVasp.nonces(newVaspAdmin);
    bytes32 structHash =
      keccak256(abi.encode(ADD_VASP_TYPEHASH, VASP_ID_2, newVaspAdmin, nonce, deadline));
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", newVasp.DOMAIN_SEPARATOR(), structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(newVaspAdminKey, digest);

    newVasp.addVasp(VASP_ID_2, newVaspAdmin, TEST_REFERENCE_ID, deadline, v, r, s);

    vm.prank(newVaspAdmin);
    newVasp.addHolder(VASP_ID_2, holder1, 10_000, 0, TEST_REFERENCE_ID);

    vm.prank(newVaspAdmin);
    newVasp.addHolder(VASP_ID_2, holder2, 10_000, 0, TEST_REFERENCE_ID);

    chfd.setVaspContractAddress(address(newVasp));
    chfd.mint(holder1, 500, TEST_REFERENCE_ID);

    vm.prank(holder1);
    bool ok = chfd.transfer(holder2, 100);

    assertTrue(ok);
    assertEq(chfd.balanceOf(holder2), 100);
  }

  function test_only_default_admin_can_set_vasp_master_address() public {
    vm.prank(outsider);
    vm.expectRevert();
    chfd.setVaspContractAddress(address(0x999));
  }

  function test_setVaspContractAddress_reverts_for_zero_address() public {
    vm.expectRevert(ZeroAddress.selector);
    chfd.setVaspContractAddress(address(0));
  }
}

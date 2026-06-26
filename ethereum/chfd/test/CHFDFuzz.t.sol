// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { CHFD } from "../src/CHFD.sol";
import { CHFD_VASP } from "../src/CHFD_VASP.sol";
import { HolderStatus } from "../src/Statuses.sol";
import { ExceedsHolderLimit } from "../src/Errors.sol";

contract CHFDFuzzTest is Test {
  bytes32 internal constant ADD_VASP_TYPEHASH =
    keccak256("AddVasp(bytes32 vaspId,address vaspAdminAddress,uint256 nonce,uint256 deadline)");

  bytes32 internal constant VASP_ID_1 = keccak256("VASP_ID_1");
  bytes32 internal constant TEST_REFERENCE_ID = keccak256("TEST_REFERENCE_ID");

  CHFD internal chfd;
  CHFD_VASP internal vasp;

  address internal vaspAdmin1;
  address internal holder1 = address(0x300);
  address internal holder2 = address(0x301);

  uint256 internal vaspAdmin1Key = 0xE11CE;

  function setUp() public {
    vaspAdmin1 = vm.addr(vaspAdmin1Key);

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

    vm.startPrank(vaspAdmin1);
    vasp.addHolder(VASP_ID_1, holder1, 10_000, 0, TEST_REFERENCE_ID);
    vasp.addHolder(VASP_ID_1, holder2, 20_000, 0, TEST_REFERENCE_ID);
    vm.stopPrank();
  }

  function _signTypedData(uint256 privateKey, bytes32 structHash)
    internal
    view
    returns (uint8, bytes32, bytes32)
  {
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vasp.DOMAIN_SEPARATOR(), structHash));
    return vm.sign(privateKey, digest);
  }

  function _addVaspWithSig(bytes32 vaspId, address vaspAdminAddress, uint256 signerKey) internal {
    uint256 deadline = block.timestamp + 1 days;
    uint256 nonce = vasp.nonces(vaspAdminAddress);
    bytes32 structHash =
      keccak256(abi.encode(ADD_VASP_TYPEHASH, vaspId, vaspAdminAddress, nonce, deadline));
    (uint8 v, bytes32 r, bytes32 s) = _signTypedData(signerKey, structHash);
    vasp.addVasp(vaspId, vaspAdminAddress, TEST_REFERENCE_ID, deadline, v, r, s);
  }

  function _checkedTransfer(CHFD token, address to, uint256 amount) internal returns (bool) {
    return token.transfer(to, amount);
  }

  function testFuzz_mint_succeeds_within_holder_limit(uint256 holderLimit, uint256 mintAmount)
    public
  {
    holderLimit = bound(holderLimit, 1, type(uint128).max);
    mintAmount = bound(mintAmount, 0, holderLimit);

    vm.prank(vaspAdmin1);
    vasp.setHolderLimit(VASP_ID_1, holder1, holderLimit, TEST_REFERENCE_ID);

    chfd.mint(holder1, mintAmount, TEST_REFERENCE_ID);

    assertEq(chfd.balanceOf(holder1), mintAmount);
  }

  function testFuzz_transfer_succeeds_within_receiver_limit(
    uint256 mintedAmount,
    uint256 transferAmount,
    uint256 receiverHeadroom
  ) public {
    mintedAmount = bound(mintedAmount, 1, type(uint128).max);
    transferAmount = bound(transferAmount, 0, mintedAmount);
    receiverHeadroom = bound(receiverHeadroom, 0, type(uint128).max - transferAmount);

    vm.startPrank(vaspAdmin1);
    vasp.setHolderLimit(VASP_ID_1, holder1, mintedAmount, TEST_REFERENCE_ID);
    vasp.setHolderLimit(VASP_ID_1, holder2, transferAmount + receiverHeadroom, TEST_REFERENCE_ID);
    vm.stopPrank();

    chfd.mint(holder1, mintedAmount, TEST_REFERENCE_ID);

    vm.prank(holder1);
    bool ok = chfd.transfer(holder2, transferAmount);

    assertTrue(ok);
    assertEq(chfd.balanceOf(holder1), mintedAmount - transferAmount);
    assertEq(chfd.balanceOf(holder2), transferAmount);
  }

  function testFuzz_transfer_reverts_when_receiver_limit_exceeded(
    uint256 mintedAmount,
    uint256 transferAmount,
    uint256 receiverLimit
  ) public {
    mintedAmount = bound(mintedAmount, 1, type(uint128).max);
    transferAmount = bound(transferAmount, 1, mintedAmount);
    receiverLimit = bound(receiverLimit, 0, transferAmount - 1);

    vm.startPrank(vaspAdmin1);
    vasp.setHolderLimit(VASP_ID_1, holder1, mintedAmount, TEST_REFERENCE_ID);
    vasp.setHolderLimit(VASP_ID_1, holder2, receiverLimit, TEST_REFERENCE_ID);
    vm.stopPrank();

    chfd.mint(holder1, mintedAmount, TEST_REFERENCE_ID);

    vm.prank(holder1);
    vm.expectRevert(ExceedsHolderLimit.selector);
    _checkedTransfer(chfd, holder2, transferAmount);
  }

  function testFuzz_forceTransfer_bypasses_pause_and_holder_status(
    uint256 mintedAmount,
    uint256 forcedAmount
  ) public {
    mintedAmount = bound(mintedAmount, 1, type(uint128).max);
    forcedAmount = bound(forcedAmount, 0, mintedAmount);

    vm.prank(vaspAdmin1);
    vasp.setHolderLimit(VASP_ID_1, holder1, mintedAmount, TEST_REFERENCE_ID);

    chfd.mint(holder1, mintedAmount, TEST_REFERENCE_ID);

    vm.startPrank(vaspAdmin1);
    vasp.setHolderStatus(VASP_ID_1, holder1, HolderStatus.Blocked, TEST_REFERENCE_ID);
    vasp.setHolderStatus(VASP_ID_1, holder2, HolderStatus.Blocked, TEST_REFERENCE_ID);
    vm.stopPrank();

    chfd.pause();

    bool ok = chfd.forceTransfer(holder1, holder2, forcedAmount, TEST_REFERENCE_ID);

    assertTrue(ok);
    assertEq(chfd.balanceOf(holder1), mintedAmount - forcedAmount);
    assertEq(chfd.balanceOf(holder2), forcedAmount);
  }
}

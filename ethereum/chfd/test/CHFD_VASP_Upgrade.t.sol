// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { CHFD } from "../src/CHFD.sol";
import { CHFD_V2 } from "../src/CHFD_V2.sol";
import { HolderStatus } from "../src/Statuses.sol";

contract MockVASP {
  function getHolderVaspId(address) external pure returns (bytes32) {
    return keccak256("vasp-id");
  }

  function getHolderDetails(address) external pure returns (uint256, HolderStatus, bytes32, uint8) {
    return (type(uint256).max, HolderStatus.Active, keccak256("vasp-id"), 0);
  }

  function getTransferVaspIds(address, address) external pure returns (bytes32, bytes32) {
    bytes32 vaspId = keccak256("vasp-id");
    return (vaspId, vaspId);
  }

  function validateTransfer(address, address, uint256) external pure { }
}

contract MockRejectingVASP {
  function getHolderVaspId(address) external pure returns (bytes32) {
    return keccak256("vasp-id");
  }

  function getHolderDetails(address) external pure returns (uint256, HolderStatus, bytes32, uint8) {
    return (type(uint256).max, HolderStatus.Active, keccak256("vasp-id"), 0);
  }

  function getTransferVaspIds(address, address) external pure returns (bytes32, bytes32) {
    bytes32 vaspId = keccak256("vasp-id");
    return (vaspId, vaspId);
  }

  function validateTransfer(address from, address to, uint256) external pure {
    if (from != address(0) && to != address(0)) {
      revert("validation failed");
    }
  }
}

contract CHFDUpgradeTest is Test {
  CHFD internal chfd;
  CHFD_V2 internal chfdV2;
  MockVASP internal vasp;

  address internal admin = address(0xA11CE);
  address internal worker = address(0xB0B);
  address internal holder1 = address(0x1111);
  address internal holder2 = address(0x2222);
  address internal attacker = address(0x9999);

  bytes32 internal constant TEST_VASP_ID = keccak256("vasp-id");
  bytes32 internal constant TEST_REFERENCE_ID = keccak256("upgrade-reference-id");

  function _checkedTransfer(CHFD token, address to, uint256 amount) internal returns (bool) {
    return token.transfer(to, amount);
  }

  function setUp() public {
    vasp = new MockVASP();

    CHFD implementation = new CHFD();
    bytes memory initData = abi.encodeCall(CHFD.initialize, (address(vasp)));

    vm.prank(admin);
    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

    chfd = CHFD(address(proxy));

    vm.startPrank(admin);
    chfd.grantMintBurnRoles(worker);
    chfd.mint(holder1, 1_000, TEST_REFERENCE_ID);
    vm.stopPrank();

    vm.prank(holder1);
    chfd.approve(worker, 300);
  }

  function test_initializeSetsExpectedState() public view {
    assertEq(chfd.name(), "Swiss Stablecoin");
    assertEq(chfd.symbol(), "CHFD");
    assertEq(chfd.decimals(), 6);

    assertTrue(chfd.hasRole(chfd.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(chfd.hasRole(chfd.MINTER_ROLE(), admin));
    assertTrue(chfd.hasRole(chfd.BURNER_ROLE(), admin));
    assertTrue(chfd.hasRole(chfd.ENFORCEMENT_ROLE(), admin));
    assertTrue(chfd.hasRole(chfd.MINTER_ROLE(), worker));
    assertTrue(chfd.hasRole(chfd.BURNER_ROLE(), worker));

    assertEq(chfd.balanceOf(holder1), 1_000);
    assertEq(chfd.allowance(holder1, worker), 300);
    assertEq(chfd.getVaspContractAddress(), address(vasp));
  }

  function test_cannotInitializeTwice() public {
    vm.expectRevert();
    chfd.initialize(address(vasp));
  }

  function test_onlyAdminCanUpgrade() public {
    CHFD_V2 implementationV2 = new CHFD_V2();

    vm.prank(attacker);
    vm.expectRevert();
    chfd.upgradeToAndCall(address(implementationV2), "");
  }

  function test_adminCanUpgradeAndStatePersists() public {
    CHFD_V2 implementationV2 = new CHFD_V2();

    vm.prank(admin);
    chfd.upgradeToAndCall(address(implementationV2), abi.encodeCall(CHFD_V2.initializeV2, ()));

    chfdV2 = CHFD_V2(address(chfd));

    assertEq(chfdV2.name(), "Swiss Stablecoin");
    assertEq(chfdV2.symbol(), "CHFD");
    assertEq(chfdV2.decimals(), 6);

    assertTrue(chfdV2.hasRole(chfdV2.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(chfdV2.hasRole(chfdV2.MINTER_ROLE(), admin));
    assertTrue(chfdV2.hasRole(chfdV2.BURNER_ROLE(), admin));
    assertTrue(chfdV2.hasRole(chfdV2.ENFORCEMENT_ROLE(), admin));
    assertTrue(chfdV2.hasRole(chfdV2.MINTER_ROLE(), worker));
    assertTrue(chfdV2.hasRole(chfdV2.BURNER_ROLE(), worker));

    assertEq(chfdV2.balanceOf(holder1), 1_000);
    assertEq(chfdV2.allowance(holder1, worker), 300);
    assertEq(chfdV2.getVaspContractAddress(), address(vasp));

    assertEq(chfdV2.version(), "V2");
    assertEq(chfdV2.versionNumber(), 2);
  }

  function test_upgradedContractStillWorks() public {
    CHFD_V2 implementationV2 = new CHFD_V2();

    vm.prank(admin);
    chfd.upgradeToAndCall(address(implementationV2), abi.encodeCall(CHFD_V2.initializeV2, ()));

    chfdV2 = CHFD_V2(address(chfd));

    vm.prank(admin);
    chfdV2.mint(holder2, 250, TEST_REFERENCE_ID);

    assertEq(chfdV2.balanceOf(holder2), 250);
    assertEq(chfdV2.versionNumber(), 2);
  }

  function test_transfer_reverts_when_vasp_validation_reverts() public {
    MockRejectingVASP rejectingVasp = new MockRejectingVASP();

    CHFD implementation = new CHFD();
    bytes memory initData = abi.encodeCall(CHFD.initialize, (address(rejectingVasp)));

    vm.prank(admin);
    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

    CHFD rejectingChfd = CHFD(address(proxy));

    vm.prank(admin);
    rejectingChfd.mint(holder1, 1_000, TEST_REFERENCE_ID);

    vm.prank(holder1);
    vm.expectRevert(abi.encodeWithSignature("Error(string)", "validation failed"));
    _checkedTransfer(rejectingChfd, holder2, 100);
  }
}

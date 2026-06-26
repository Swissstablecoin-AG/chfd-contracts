// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { CHFD } from "../src/CHFD.sol";
import { CHFD_VASP } from "../src/CHFD_VASP.sol";
import { HolderStatus } from "../src/Statuses.sol";

contract CHFDInvariantHandler is Test {
  bytes32 internal constant TEST_REFERENCE_ID = keccak256("TEST_REFERENCE_ID");
  bytes32 internal immutable VASP_ID;

  CHFD internal immutable CHFD_TOKEN;
  CHFD_VASP internal immutable VASP;

  address[] internal actors;

  uint256 public ghostExpectedSupply;

  uint256 public mintCalls;
  uint256 public transferCalls;
  uint256 public forceTransferCalls;
  uint256 public setLimitCalls;
  uint256 public blockCalls;
  uint256 public unblockCalls;

  constructor(CHFD _chfd, CHFD_VASP _vasp, bytes32 _vaspId, address[] memory _actors) {
    CHFD_TOKEN = _chfd;
    VASP = _vasp;
    VASP_ID = _vaspId;

    for (uint256 i = 0; i < _actors.length; i++) {
      actors.push(_actors[i]);
    }
  }

  function actorAt(uint256 index) external view returns (address) {
    return actors[index];
  }

  function actorCount() external view returns (uint256) {
    return actors.length;
  }

  function totalCalls() external view returns (uint256) {
    return
      mintCalls + transferCalls + forceTransferCalls + setLimitCalls + blockCalls + unblockCalls;
  }

  function mintToActor(uint256 actorSeed, uint256 holderLimit, uint256 mintAmount) external {
    address actor = _actor(actorSeed);
    uint256 balance = CHFD_TOKEN.balanceOf(actor);

    holderLimit = bound(holderLimit, balance, type(uint128).max);
    mintAmount = bound(mintAmount, 0, holderLimit - balance);

    _ensureUnpaused();
    _setStatus(actor, HolderStatus.Active);
    _setLimit(actor, holderLimit);

    CHFD_TOKEN.mint(actor, mintAmount, TEST_REFERENCE_ID);

    ghostExpectedSupply += mintAmount;
    mintCalls += 1;
  }

  function transferBetweenActors(
    uint256 fromSeed,
    uint256 toSeed,
    uint256 transferAmount,
    uint256 receiverHeadroom
  ) external {
    (address from, address to) = _distinctActors(fromSeed, toSeed);
    uint256 senderBalance = CHFD_TOKEN.balanceOf(from);
    uint256 receiverCapacity = type(uint128).max - CHFD_TOKEN.balanceOf(to);

    if (senderBalance > receiverCapacity) {
      senderBalance = receiverCapacity;
    }

    transferAmount = bound(transferAmount, 0, senderBalance);
    receiverHeadroom = bound(receiverHeadroom, 0, receiverCapacity - transferAmount);

    _ensureUnpaused();
    _setStatus(from, HolderStatus.Active);
    _setStatus(to, HolderStatus.Active);
    _setLimit(to, CHFD_TOKEN.balanceOf(to) + transferAmount + receiverHeadroom);

    vm.prank(from);
    _checkedTransfer(CHFD_TOKEN, to, transferAmount);

    transferCalls += 1;
  }

  function forceTransferBetweenActors(uint256 fromSeed, uint256 toSeed, uint256 transferAmount)
    external
  {
    (address from, address to) = _distinctActors(fromSeed, toSeed);
    uint256 senderBalance = CHFD_TOKEN.balanceOf(from);

    transferAmount = bound(transferAmount, 0, senderBalance);

    _setStatus(from, HolderStatus.Blocked);
    _setStatus(to, HolderStatus.Blocked);
    _setLimit(to, CHFD_TOKEN.balanceOf(to) + transferAmount);

    if (!CHFD_TOKEN.paused()) {
      CHFD_TOKEN.pause();
    }

    CHFD_TOKEN.forceTransfer(from, to, transferAmount, TEST_REFERENCE_ID);

    forceTransferCalls += 1;
  }

  function setActorLimit(uint256 actorSeed, uint256 newLimit) external {
    address actor = _actor(actorSeed);
    uint256 balance = CHFD_TOKEN.balanceOf(actor);

    newLimit = bound(newLimit, balance, type(uint128).max);
    _setLimit(actor, newLimit);

    setLimitCalls += 1;
  }

  function blockActor(uint256 actorSeed) external {
    _setStatus(_actor(actorSeed), HolderStatus.Blocked);
    blockCalls += 1;
  }

  function unblockActor(uint256 actorSeed) external {
    _setStatus(_actor(actorSeed), HolderStatus.Active);
    unblockCalls += 1;
  }

  function _actor(uint256 seed) internal view returns (address) {
    return actors[bound(seed, 0, actors.length - 1)];
  }

  function _distinctActors(uint256 fromSeed, uint256 toSeed)
    internal
    view
    returns (address, address)
  {
    uint256 fromIndex = bound(fromSeed, 0, actors.length - 1);
    uint256 toIndex = bound(toSeed, 0, actors.length - 2);

    if (toIndex >= fromIndex) {
      toIndex += 1;
    }

    return (actors[fromIndex], actors[toIndex]);
  }

  function _setLimit(address actor, uint256 limit) internal {
    VASP.setHolderLimit(VASP_ID, actor, limit, TEST_REFERENCE_ID);
  }

  function _setStatus(address actor, HolderStatus status) internal {
    VASP.setHolderStatus(VASP_ID, actor, status, TEST_REFERENCE_ID);
  }

  function _ensureUnpaused() internal {
    if (CHFD_TOKEN.paused()) {
      CHFD_TOKEN.unpause();
    }
  }

  function _checkedTransfer(CHFD token, address to, uint256 amount) internal returns (bool) {
    return token.transfer(to, amount);
  }
}

contract CHFDInvariantTest is StdInvariant, Test {
  bytes32 internal constant ADD_VASP_TYPEHASH =
    keccak256("AddVasp(bytes32 vaspId,address vaspAdminAddress,uint256 nonce,uint256 deadline)");

  bytes32 internal constant VASP_ID_1 = keccak256("VASP_ID_1");
  bytes32 internal constant TEST_REFERENCE_ID = keccak256("TEST_REFERENCE_ID");

  CHFD internal chfd;
  CHFD_VASP internal vasp;
  CHFDInvariantHandler internal handler;

  address internal vaspAdmin1;
  address[] internal actors;

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

    actors.push(address(0x300));
    actors.push(address(0x301));
    actors.push(address(0x302));
    actors.push(address(0x303));

    vm.startPrank(vaspAdmin1);
    for (uint256 i = 0; i < actors.length; i++) {
      vasp.addHolder(VASP_ID_1, actors[i], 1_000_000, 0, TEST_REFERENCE_ID);
    }
    vm.stopPrank();

    handler = new CHFDInvariantHandler(chfd, vasp, VASP_ID_1, actors);

    chfd.grantMintBurnRoles(address(handler));
    chfd.grantRole(chfd.ENFORCEMENT_ROLE(), address(handler));

    vm.prank(vaspAdmin1);
    vasp.addVaspAdmin(VASP_ID_1, address(handler), TEST_REFERENCE_ID);

    targetContract(address(handler));
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

  // Level 1: simple accounting invariant.
  function invariant_totalSupply_matches_ghost_supply() public view {
    assertEq(chfd.totalSupply(), handler.ghostExpectedSupply());
  }

  // Level 2: tracked balances must reconcile to the full supply.
  function invariant_sum_of_actor_balances_matches_total_supply() public view {
    uint256 summedBalances;

    for (uint256 i = 0; i < actors.length; i++) {
      summedBalances += chfd.balanceOf(actors[i]);
    }

    assertEq(summedBalances, chfd.totalSupply());
  }

  // Level 3: handler actions should never detach tracked actors from their VASP.
  function invariant_all_tracked_holders_stay_attached_to_the_same_vasp() public view {
    for (uint256 i = 0; i < actors.length; i++) {
      (,, bytes32 vaspId,) = vasp.getHolderDetails(actors[i]);
      assertEq(vaspId, VASP_ID_1);
    }
  }

  // Level 4: the handler never lowers a holder's limit below the holder's live balance.
  function invariant_actor_balances_never_exceed_their_limits() public view {
    for (uint256 i = 0; i < actors.length; i++) {
      (uint256 holderLimit,,,) = vasp.getHolderDetails(actors[i]);
      assertLe(chfd.balanceOf(actors[i]), holderLimit);
    }
  }

  function afterInvariant() public {
    emit log_named_uint("mintCalls", handler.mintCalls());
    emit log_named_uint("transferCalls", handler.transferCalls());
    emit log_named_uint("forceTransferCalls", handler.forceTransferCalls());
    emit log_named_uint("setLimitCalls", handler.setLimitCalls());
    emit log_named_uint("blockCalls", handler.blockCalls());
    emit log_named_uint("unblockCalls", handler.unblockCalls());
    emit log_named_uint("totalCalls", handler.totalCalls());
  }
}

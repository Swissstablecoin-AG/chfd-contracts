// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { HolderStatus, VaspStatus } from "./Statuses.sol";

event MintEvent(
  address operator,
  address indexed recipientAddress,
  bytes32 indexed referenceId,
  uint256 amount,
  bytes32 indexed vaspId
);
event BurnEvent(
  address operator,
  address indexed fromAddress,
  bytes32 indexed referenceId,
  uint256 amount,
  bytes32 indexed vaspId
);
event CHFDTransferEvent(
  address indexed from,
  address indexed to,
  bytes32 indexed fromVaspId,
  bytes32 toVaspId,
  uint256 amount
);
event ForceTransferEvent(
  address operator,
  address indexed from,
  address indexed to,
  bytes32 indexed referenceId,
  uint256 amount
);

event AddVaspEvent(address operator, bytes32 indexed referenceId, bytes32 indexed vaspId);
event SetVaspStatusEvent(
  address operator,
  bytes32 indexed referenceId,
  bytes32 indexed vaspId,
  VaspStatus prevStatus,
  VaspStatus newStatus
);
event AddVaspAdminEvent(
  address operator,
  bytes32 indexed referenceId,
  bytes32 indexed vaspId,
  address indexed adminAddress
);
event RemoveVaspAdminEvent(
  address operator,
  bytes32 indexed referenceId,
  bytes32 indexed vaspId,
  address indexed adminAddress
);
event AddHolderEvent(
  address operator,
  bytes32 indexed referenceId,
  bytes32 indexed vaspId,
  address indexed holderAddress,
  uint256 holderLimit,
  uint8 vaspOwned
);
event RemoveHolderEvent(
  address operator,
  bytes32 indexed referenceId,
  bytes32 indexed vaspId,
  address indexed holderAddress
);
event SetHolderLimitEvent(
  address operator,
  bytes32 indexed referenceId,
  bytes32 indexed vaspId,
  address indexed holderAddress,
  uint256 prevHolderLimit,
  uint256 newHolderLimit
);
event SetHolderStatusEvent(
  address operator,
  bytes32 indexed referenceId,
  bytes32 indexed vaspId,
  address indexed holderAddress,
  HolderStatus prevStatus,
  HolderStatus newStatus
);
event SignatureNonceInvalidated(address indexed account, uint256 previousNonce, uint256 newNonce);

event VaspContractAddressUpdated(
  address indexed operator, address indexed previousAddress, address indexed newAddress
);

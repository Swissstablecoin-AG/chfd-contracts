// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { HolderStatus } from "./Statuses.sol";

interface ICHFDVasp {
  function getHolderVaspId(address holderAddress) external view returns (bytes32);

  function getHolderDetails(address holderAddress)
    external
    view
    returns (uint256, HolderStatus, bytes32, uint8);
  function getTransferVaspIds(address from, address to) external view returns (bytes32, bytes32);

  function validateTransfer(address from, address to, uint256 targetAmount) external view;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { CHFD_VASP } from "./CHFD_VASP.sol";

contract CHFD_VASP_V2 is CHFD_VASP {
  function initializeV2() public reinitializer(2) { }

  function version() external pure returns (string memory) {
    return "V2";
  }

  function versionNumber() external view returns (uint256) {
    return _getInitializedVersion();
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Script, console2 } from "forge-std/Script.sol";

import { CHFD } from "../src/CHFD.sol";
import { CHFD_VASP } from "../src/CHFD_VASP.sol";

contract RejectCHFDRole is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    address targetAddress = vm.envAddress("ROLE_ADDRESS_TO_REJECT");
    address chfdProxyAddress = vm.envAddress("CHFD_PROXY");
    address chfdVaspProxyAddress = vm.envAddress("CHFD_VASP_PROXY");

    CHFD chfd = CHFD(chfdProxyAddress);
    CHFD_VASP chfdVasp = CHFD_VASP(chfdVaspProxyAddress);

    vm.startBroadcast(deployerPrivateKey);

    _revokeChfdRole(chfd, chfd.DEFAULT_ADMIN_ROLE(), targetAddress, "DEFAULT_ADMIN_ROLE");
    _revokeChfdRole(chfd, chfd.MINTER_ROLE(), targetAddress, "MINTER_ROLE");
    _revokeChfdRole(chfd, chfd.BURNER_ROLE(), targetAddress, "BURNER_ROLE");
    _revokeChfdRole(chfd, chfd.ENFORCEMENT_ROLE(), targetAddress, "ENFORCEMENT_ROLE");

    _revokeChfdVaspRole(
      chfdVasp, chfdVasp.DEFAULT_ADMIN_ROLE(), targetAddress, "DEFAULT_ADMIN_ROLE"
    );
    _revokeChfdVaspRole(chfdVasp, chfdVasp.UPDATE_VASP_ROLE(), targetAddress, "UPDATE_VASP_ROLE");
    _revokeChfdVaspRole(
      chfdVasp, chfdVasp.VALIDATE_TRANSFER_ROLE(), targetAddress, "VALIDATE_TRANSFER_ROLE"
    );

    vm.stopBroadcast();

    console2.log("DEPLOYER:", deployer);
    console2.log("ROLE_ADDRESS_TO_REJECT:", targetAddress);
    console2.log("CHFD_PROXY:", chfdProxyAddress);
    console2.log("CHFD_VASP_PROXY:", chfdVaspProxyAddress);
    console2.log("Completed CHFD and CHFD_VASP role rejection attempts.");
  }

  function _revokeChfdRole(CHFD chfd, bytes32 role, address targetAddress, string memory roleName)
    internal
  {
    if (!chfd.hasRole(role, targetAddress)) {
      console2.log("SKIP CHFD role:");
      console2.log(roleName);
      console2.log("Address:");
      console2.log(targetAddress);
      return;
    }

    try chfd.revokeRole(role, targetAddress) {
      console2.log("REVOKED CHFD role:");
      console2.log(roleName);
      console2.log("Address:");
      console2.log(targetAddress);
    } catch Error(string memory reason) {
      console2.log("WARNING CHFD revoke failed for role:");
      console2.log(roleName);
      console2.log("Reason:");
      console2.log(reason);
    } catch (bytes memory) {
      console2.log("WARNING CHFD revoke failed with unknown error for role:");
      console2.log(roleName);
    }
  }

  function _revokeChfdVaspRole(
    CHFD_VASP chfdVasp,
    bytes32 role,
    address targetAddress,
    string memory roleName
  ) internal {
    if (!chfdVasp.hasRole(role, targetAddress)) {
      console2.log("SKIP CHFD_VASP role:");
      console2.log(roleName);
      console2.log("Address:");
      console2.log(targetAddress);
      return;
    }

    try chfdVasp.revokeRole(role, targetAddress) {
      console2.log("REVOKED CHFD_VASP role:");
      console2.log(roleName);
      console2.log("Address:");
      console2.log(targetAddress);
    } catch Error(string memory reason) {
      console2.log("WARNING CHFD_VASP revoke failed for role:");
      console2.log(roleName);
      console2.log("Reason:");
      console2.log(reason);
    } catch (bytes memory) {
      console2.log("WARNING CHFD_VASP revoke failed with unknown error for role:");
      console2.log(roleName);
    }
  }
}

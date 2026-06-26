// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Script, console2 } from "forge-std/Script.sol";

import { CHFD } from "../src/CHFD.sol";
import { CHFD_VASP } from "../src/CHFD_VASP.sol";

contract GrantCHFDRoles is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    address minterRoleAddress = vm.envAddress("MINTER_ROLE_ADDRESS");
    address burnerRoleAddress = vm.envAddress("BURNER_ROLE_ADDRESS");
    address enforcementRoleAddress = vm.envAddress("ENFORCEMENT_ROLE_ADDRESS");
    address updateVaspRoleAddress = vm.envAddress("UPDATE_VASP_ROLE_ADDRESS");

    address chfdProxyAddress = vm.envAddress("CHFD_PROXY");
    address chfdVaspProxyAddress = vm.envAddress("CHFD_VASP_PROXY");

    CHFD chfd = CHFD(chfdProxyAddress);
    CHFD_VASP chfdVasp = CHFD_VASP(chfdVaspProxyAddress);

    vm.startBroadcast(deployerPrivateKey);

    chfd.grantRole(chfd.MINTER_ROLE(), minterRoleAddress);
    chfd.grantRole(chfd.BURNER_ROLE(), burnerRoleAddress);
    chfd.grantRole(chfd.ENFORCEMENT_ROLE(), enforcementRoleAddress);
    chfdVasp.grantRole(chfdVasp.UPDATE_VASP_ROLE(), updateVaspRoleAddress);

    vm.stopBroadcast();

    console2.log("DEPLOYER:", deployer);
    console2.log("MINTER_ROLE_ADDRESS:", minterRoleAddress);
    console2.log("BURNER_ROLE_ADDRESS:", burnerRoleAddress);
    console2.log("ENFORCEMENT_ROLE_ADDRESS:", enforcementRoleAddress);
    console2.log("UPDATE_VASP_ROLE_ADDRESS:", updateVaspRoleAddress);
    console2.log("CHFD_PROXY:", chfdProxyAddress);
    console2.log("CHFD_VASP_PROXY:", chfdVaspProxyAddress);
    console2.log("Granted CHFD and CHFD_VASP roles.");
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Script, console2 } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { CHFD } from "../src/CHFD.sol";
import { CHFD_VASP } from "../src/CHFD_VASP.sol";

contract DeployCHFD is Script {
  struct RoleConfig {
    address minter;
    address burner;
    address enforcement;
    address updateVasp;
    address defaultAdmin;
    address defaultAdminFailover;
  }

  struct Deployment {
    address deployer;
    address chfdProxy;
    address chfdVaspProxy;
    uint256 lastOperationBlockNumber;
  }

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    RoleConfig memory roles = _loadRoleConfig();
    Deployment memory deployment;

    deployment.deployer = vm.addr(deployerPrivateKey);

    vm.startBroadcast(deployerPrivateKey);

    (deployment.chfdProxy, deployment.chfdVaspProxy) = _deployContracts();
    _configureRoles(deployment, roles);
    deployment.lastOperationBlockNumber = block.number;

    vm.stopBroadcast();

    _writeDeploymentJson(deployment, roles);
    _logDeployment(deployment, roles);
  }

  function _loadRoleConfig() private view returns (RoleConfig memory roles) {
    roles.minter = vm.envAddress("MINTER_ROLE_ADDRESS");
    roles.burner = vm.envAddress("BURNER_ROLE_ADDRESS");
    roles.enforcement = vm.envAddress("ENFORCEMENT_ROLE_ADDRESS");
    roles.updateVasp = vm.envAddress("UPDATE_VASP_ROLE_ADDRESS");
    roles.defaultAdmin = vm.envAddress("DEFAULT_ADMIN_ROLE_ADDRESS");
    roles.defaultAdminFailover = vm.envAddress("DEFAULT_ADMIN_ROLE_FAILOVER_ADDRESS");
  }

  function _deployContracts()
    private
    returns (address chfdProxyAddress, address chfdVaspProxyAddress)
  {
    CHFD_VASP vaspImplementation = new CHFD_VASP();
    ERC1967Proxy vaspProxy =
      new ERC1967Proxy(address(vaspImplementation), abi.encodeCall(CHFD_VASP.initialize, ()));

    chfdVaspProxyAddress = address(vaspProxy);

    CHFD chfdImplementation = new CHFD();
    ERC1967Proxy chfdProxy = new ERC1967Proxy(
      address(chfdImplementation), abi.encodeCall(CHFD.initialize, (chfdVaspProxyAddress))
    );

    chfdProxyAddress = address(chfdProxy);
  }

  function _configureRoles(Deployment memory deployment, RoleConfig memory roles) private {
    CHFD chfd = CHFD(deployment.chfdProxy);
    CHFD_VASP chfdVasp = CHFD_VASP(deployment.chfdVaspProxy);

    chfd.grantRole(chfd.DEFAULT_ADMIN_ROLE(), roles.defaultAdmin);
    chfd.grantRole(chfd.DEFAULT_ADMIN_ROLE(), roles.defaultAdminFailover);

    chfdVasp.grantRole(chfdVasp.DEFAULT_ADMIN_ROLE(), roles.defaultAdmin);
    chfdVasp.grantRole(chfdVasp.DEFAULT_ADMIN_ROLE(), roles.defaultAdminFailover);

    chfdVasp.grantValidateTransferRole(deployment.chfdProxy);

    chfd.grantRole(chfd.MINTER_ROLE(), roles.minter);
    chfd.grantRole(chfd.BURNER_ROLE(), roles.burner);
    chfd.grantRole(chfd.ENFORCEMENT_ROLE(), roles.enforcement);

    chfdVasp.grantRole(chfdVasp.UPDATE_VASP_ROLE(), roles.updateVasp);

    chfd.revokeRole(chfd.MINTER_ROLE(), deployment.deployer);
    chfd.revokeRole(chfd.BURNER_ROLE(), deployment.deployer);
    chfd.revokeRole(chfd.ENFORCEMENT_ROLE(), deployment.deployer);
    chfd.revokeRole(chfd.DEFAULT_ADMIN_ROLE(), deployment.deployer);

    chfdVasp.revokeRole(chfdVasp.UPDATE_VASP_ROLE(), deployment.deployer);
    chfdVasp.revokeRole(chfdVasp.DEFAULT_ADMIN_ROLE(), deployment.deployer);
  }

  function _writeDeploymentJson(Deployment memory deployment, RoleConfig memory roles) private {
    string memory jsonKey = "deployment";

    vm.serializeAddress(jsonKey, "DEPLOYER", deployment.deployer);
    vm.serializeAddress(jsonKey, "MINTER_ROLE_ADDRESS", roles.minter);
    vm.serializeAddress(jsonKey, "BURNER_ROLE_ADDRESS", roles.burner);
    vm.serializeAddress(jsonKey, "ENFORCEMENT_ROLE_ADDRESS", roles.enforcement);
    vm.serializeAddress(jsonKey, "UPDATE_VASP_ROLE_ADDRESS", roles.updateVasp);
    vm.serializeAddress(jsonKey, "RELAYER_SIGNER_ADDRESS", roles.updateVasp);
    vm.serializeAddress(jsonKey, "DEFAULT_ADMIN_ROLE_ADDRESS", roles.defaultAdmin);
    vm.serializeAddress(jsonKey, "DEFAULT_ADMIN_ROLE_FAILOVER_ADDRESS", roles.defaultAdminFailover);
    vm.serializeAddress(jsonKey, "CHFD_PROXY", deployment.chfdProxy);
    vm.serializeUint(jsonKey, "LAST_OPERATION_BLOCK_NUMBER", deployment.lastOperationBlockNumber);

    string memory finalJson =
      vm.serializeAddress(jsonKey, "CHFD_VASP_PROXY", deployment.chfdVaspProxy);

    vm.writeJson(finalJson, "./out/deployment.json");
  }

  function _logDeployment(Deployment memory deployment, RoleConfig memory roles) private pure {
    console2.log("DEPLOYER:", deployment.deployer);
    console2.log("MINTER_ROLE_ADDRESS:", roles.minter);
    console2.log("BURNER_ROLE_ADDRESS:", roles.burner);
    console2.log("ENFORCEMENT_ROLE_ADDRESS:", roles.enforcement);
    console2.log("UPDATE_VASP_ROLE_ADDRESS:", roles.updateVasp);
    console2.log("RELAYER_SIGNER_ADDRESS:", roles.updateVasp);
    console2.log("DEFAULT_ADMIN_ROLE_ADDRESS:", roles.defaultAdmin);
    console2.log("DEFAULT_ADMIN_ROLE_FAILOVER_ADDRESS:", roles.defaultAdminFailover);
    console2.log("CHFD_PROXY:", deployment.chfdProxy);
    console2.log("CHFD_VASP_PROXY:", deployment.chfdVaspProxy);
    console2.log("LAST_OPERATION_BLOCK_NUMBER:", deployment.lastOperationBlockNumber);
    console2.log("Wrote ./out/deployment.json");
  }
}

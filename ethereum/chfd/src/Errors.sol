// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

error ZeroAddress();
error InvalidVaspId();
error VaspDoesNotExist();
error NotVaspAdmin();
error InvalidHolderAddress();
error HolderDoesNotExist();
error VaspAlreadyExists();
error VaspAdminAlreadyExists();
error VaspAdminDoesNotExist();
error HolderAlreadyExists();
error VaspNotActive();
error HolderNotActive();
error ExceedsHolderLimit();
error HolderDoesNotBelongToVasp();
error InvalidStatus();
error CannotRemoveLastVaspAdmin();
error MaxVaspAdminsReached();
error ForceTransferReentry();
error InvalidForceTransferAddress();
error InvalidNonce();
error InvalidSignature();
error SignatureExpired();
error HolderIsVaspAdmin();

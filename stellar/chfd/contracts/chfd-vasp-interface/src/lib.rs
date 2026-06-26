#![no_std]

use soroban_sdk::{contractclient, contracttype, Address, BytesN, Env};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[contracttype]
pub enum VaspStatus {
    None = 0,
    Active = 1,
    Blocked = 2,
    Locked = 3,
    Sanctioned = 4,
    Frozen = 5,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[contracttype]
pub enum HolderStatus {
    None = 0,
    Active = 1,
    Blocked = 2,
    Locked = 3,
    Sanctioned = 4,
    Frozen = 5,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contracttype]
pub struct HolderDetails {
    pub limit: u128,
    pub status: HolderStatus,
    pub vasp_id: BytesN<32>,
    pub vasp_owned: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contracttype]
pub struct TransferVaspIds {
    pub from_vasp_id: BytesN<32>,
    pub to_vasp_id: BytesN<32>,
}

#[contractclient(name = "ChfdVaspContractClient")]
pub trait ChfdVaspContract {
    fn get_holder_vasp_id(env: Env, holder_address: Address) -> BytesN<32>;

    fn get_transfer_vasp_ids(env: Env, from: Address, to: Address) -> TransferVaspIds;

    fn validate_transfer(env: Env, from: Option<Address>, to: Option<Address>, target_amount: u128);
}

#![cfg(test)]

extern crate std;

use super::*;
use soroban_sdk::testutils::Address as _;
use soroban_sdk::{BytesN, Env};

fn id(env: &Env, value: u8) -> BytesN<32> {
    BytesN::from_array(env, &[value; 32])
}

fn upload_fixture_wasm(env: &Env) -> BytesN<32> {
    env.deployer().upload_contract_wasm(&[][..])
}

fn setup() -> (
    Env,
    ChfdVaspContractClient<'static>,
    Address,
    Address,
    Address,
    Address,
    Address,
    Address,
    BytesN<32>,
    BytesN<32>,
) {
    let env = Env::default();
    env.mock_all_auths();

    let platform_admin = Address::generate(&env);
    let platform_admin_failover = Address::generate(&env);
    let worker = Address::generate(&env);
    let outsider = Address::generate(&env);
    let vasp_admin_1 = Address::generate(&env);
    let vasp_admin_2 = Address::generate(&env);
    let vasp_id_1 = id(&env, 1);
    let reference_id = id(&env, 9);

    let contract_id = env.register(
        ChfdVaspContract,
        (&platform_admin, &platform_admin_failover),
    );
    let client = ChfdVaspContractClient::new(&env, &contract_id);

    (
        env,
        client,
        platform_admin,
        platform_admin_failover,
        worker,
        outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id_1,
        reference_id,
    )
}

fn add_vasp(
    client: &ChfdVaspContractClient<'_>,
    operator: &Address,
    vasp_id: &BytesN<32>,
    vasp_admin: &Address,
    reference_id: &BytesN<32>,
) {
    client.add_vasp(operator, vasp_id, vasp_admin, reference_id);
}

fn grant_update_operator(
    client: &ChfdVaspContractClient<'_>,
    platform_admin: &Address,
    operator: &Address,
) {
    client.grant_update_operator(platform_admin, operator);
    assert!(client.is_update_operator(operator));
}

#[test]
fn verify_vasp_admin_requires_only_admin_auth() {
    let (
        env,
        client,
        _platform_admin,
        _platform_admin_failover,
        _worker,
        _outsider,
        vasp_admin_1,
        _vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    env.mock_all_auths();

    let result = client.verify_vasp_admin(&vasp_id, &vasp_admin_1, &ref_id);
    assert_eq!(result, ref_id);
}

#[test]
fn constructor_sets_platform_admin() {
    let env = Env::default();
    env.mock_all_auths();

    let platform_admin = Address::generate(&env);
    let platform_admin_failover = Address::generate(&env);
    let worker = Address::generate(&env);

    let contract_id = env.register(
        ChfdVaspContract,
        (&platform_admin, &platform_admin_failover),
    );
    let client = ChfdVaspContractClient::new(&env, &contract_id);

    assert!(client.is_default_admin(&platform_admin));
    assert!(client.is_default_admin(&platform_admin_failover));
    assert!(!client.is_update_operator(&platform_admin));
    assert!(!client.is_update_operator(&platform_admin_failover));
    assert!(!client.is_update_operator(&worker));
}

#[test]
fn grant_and_revoke_update_operator_work() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        _vasp_admin_1,
        _vasp_admin_2,
        _vasp_id,
        _ref_id,
    ) = setup();

    client.grant_update_operator(&platform_admin, &worker);
    assert!(client.is_update_operator(&worker));

    client.revoke_update_operator(&platform_admin, &worker);
    assert!(!client.is_update_operator(&worker));
}

#[test]
fn granted_default_admin_can_manage_update_operator() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        _vasp_admin_1,
        _vasp_admin_2,
        _vasp_id,
        _ref_id,
    ) = setup();
    let backup_admin = Address::generate(&_env);

    client.grant_default_admin_role(&platform_admin, &backup_admin);
    assert!(client.is_default_admin(&backup_admin));

    client.grant_update_operator(&backup_admin, &worker);
    assert!(client.is_update_operator(&worker));
}

#[test]
fn default_admin_can_upgrade_contract() {
    let (env, client, platform_admin, _platform_admin_failover, _worker, _outsider, _vasp_admin_1, _vasp_admin_2, _vasp_id, _ref_id) =
        setup();
    let wasm_hash = upload_fixture_wasm(&env);

    client.upgrade(&platform_admin, &wasm_hash);
}

#[test]
#[should_panic(expected = "Error(Contract, #17)")]
fn non_admin_cannot_upgrade_contract() {
    let (env, client, _platform_admin, _platform_admin_failover, _worker, outsider, _vasp_admin_1, _vasp_admin_2, _vasp_id, _ref_id) =
        setup();
    let wasm_hash = upload_fixture_wasm(&env);

    client.upgrade(&outsider, &wasm_hash);
}

#[test]
fn add_vasp_registers_initial_admin_and_holder() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        _vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);

    assert_eq!(client.get_vasp_details(&vasp_id), VaspStatus::Active);
    assert!(client.get_vasp_admin_status(&vasp_id, &vasp_admin_1));

    let holder = client.get_holder_details(&vasp_admin_1);
    assert_eq!(
        holder,
        HolderDetails {
            limit: 0,
            status: HolderStatus::Active,
            vasp_id,
            vasp_owned: 0,
        }
    );
}

#[test]
#[should_panic(expected = "Error(Contract, #6)")]
fn add_vasp_rejects_duplicate_vasp() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        _vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    add_vasp(
        &client,
        &worker,
        &vasp_id,
        &Address::generate(&_env),
        &ref_id,
    );
}

#[test]
#[should_panic(expected = "Error(Contract, #9)")]
fn add_vasp_rejects_existing_holder_as_initial_admin() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();
    let vasp_id_2 = id(&_env, 2);

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &10_000_u128,
        &0_u32,
        &ref_id,
    );
    add_vasp(&client, &worker, &vasp_id_2, &vasp_admin_2, &ref_id);
}

#[test]
#[should_panic(expected = "Error(Contract, #17)")]
fn add_vasp_requires_platform_operator() {
    let (
        _env,
        client,
        _platform_admin,
        _platform_admin_failover,
        _worker,
        outsider,
        vasp_admin_1,
        _vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    add_vasp(&client, &outsider, &vasp_id, &vasp_admin_1, &ref_id);
}

#[test]
fn vasp_admin_can_add_and_remove_another_admin() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_vasp_admin(
        &worker,
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &ref_id,
    );
    assert!(client.get_vasp_admin_status(&vasp_id, &vasp_admin_2));

    client.remove_vasp_admin(
        &worker,
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &ref_id,
    );
    assert!(!client.get_vasp_admin_status(&vasp_id, &vasp_admin_2));
}

#[test]
fn add_vasp_admin_promotes_existing_same_vasp_holder() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &42_000_u128,
        &0_u32,
        &ref_id,
    );
    client.add_vasp_admin(
        &worker,
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &ref_id,
    );

    let holder = client.get_holder_details(&vasp_admin_2);
    assert_eq!(holder.limit, 42_000);
    assert_eq!(holder.status, HolderStatus::Active);
    assert!(client.get_vasp_admin_status(&vasp_id, &vasp_admin_2));
}

#[test]
#[should_panic(expected = "Error(Contract, #4)")]
fn non_vasp_admin_cannot_add_vasp_admin() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_vasp_admin(&worker, &outsider, &vasp_id, &vasp_admin_2, &ref_id);
}

#[test]
#[should_panic(expected = "Error(Contract, #15)")]
fn remove_vasp_admin_rejects_removing_last_admin() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        _vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.remove_vasp_admin(
        &worker,
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_1,
        &ref_id,
    );
}

#[test]
fn add_holder_and_update_holder_controls_work() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &30_000_u128,
        &0_u32,
        &ref_id,
    );
    client.set_holder_limit(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &55_000_u128,
        &ref_id,
    );
    client.set_holder_status(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &HolderStatus::Frozen,
        &ref_id,
    );

    let holder = client.get_holder_details(&vasp_admin_2);
    assert_eq!(holder.limit, 55_000);
    assert_eq!(holder.status, HolderStatus::Frozen);
    assert_eq!(holder.vasp_owned, 0);
}

#[test]
fn add_holder_records_vasp_owned_flag() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &30_000_u128,
        &1_u32,
        &ref_id,
    );

    let holder = client.get_holder_details(&vasp_admin_2);
    assert_eq!(holder.vasp_owned, 1);

    // set_holder_limit must preserve the vasp_owned flag.
    client.set_holder_limit(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &55_000_u128,
        &ref_id,
    );
    assert_eq!(client.get_holder_details(&vasp_admin_2).vasp_owned, 1);
}

#[test]
#[should_panic(expected = "Error(Contract, #10)")]
fn add_holder_requires_active_vasp() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.set_vasp_status(&worker, &vasp_id, &VaspStatus::Blocked, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &30_000_u128,
        &0_u32,
        &ref_id,
    );
}

#[test]
#[should_panic(expected = "Error(Contract, #13)")]
fn set_holder_limit_rejects_holder_from_other_vasp() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();
    let vasp_id_2 = id(&_env, 2);
    let vasp_admin_3 = Address::generate(&_env);

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    add_vasp(&client, &worker, &vasp_id_2, &vasp_admin_3, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &30_000_u128,
        &0_u32,
        &ref_id,
    );
    client.set_holder_limit(
        &vasp_admin_3,
        &vasp_id_2,
        &vasp_admin_2,
        &55_000_u128,
        &ref_id,
    );
}

#[test]
#[should_panic(expected = "Error(Contract, #14)")]
fn set_holder_status_rejects_none() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &30_000_u128,
        &0_u32,
        &ref_id,
    );
    client.set_holder_status(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &HolderStatus::None,
        &ref_id,
    );
}

#[test]
fn validate_transfer_accepts_registered_active_holders_within_limit() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &20_000_u128,
        &0_u32,
        &ref_id,
    );
    client.validate_transfer(
        &Some(vasp_admin_1.clone()),
        &Some(vasp_admin_2.clone()),
        &10_000_u128,
    );

    let ids = client.get_transfer_vasp_ids(&vasp_admin_1, &vasp_admin_2);
    assert_eq!(ids.from_vasp_id, vasp_id);
    assert_eq!(ids.to_vasp_id, vasp_id);
}

#[test]
#[should_panic(expected = "Error(Contract, #11)")]
fn validate_transfer_rejects_inactive_sender() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &20_000_u128,
        &0_u32,
        &ref_id,
    );
    client.set_holder_status(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_1,
        &HolderStatus::Blocked,
        &ref_id,
    );
    client.validate_transfer(&Some(vasp_admin_1), &Some(vasp_admin_2), &10_000_u128);
}

#[test]
#[should_panic(expected = "Error(Contract, #12)")]
fn validate_transfer_rejects_receiver_above_limit() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &20_000_u128,
        &0_u32,
        &ref_id,
    );
    client.validate_transfer(&Some(vasp_admin_1), &Some(vasp_admin_2), &20_001_u128);
}

#[test]
#[should_panic(expected = "Error(Contract, #10)")]
fn validate_transfer_rejects_blocked_vasp() {
    let (
        _env,
        client,
        platform_admin,
        _platform_admin_failover,
        worker,
        _outsider,
        vasp_admin_1,
        vasp_admin_2,
        vasp_id,
        ref_id,
    ) = setup();

    grant_update_operator(&client, &platform_admin, &worker);
    add_vasp(&client, &worker, &vasp_id, &vasp_admin_1, &ref_id);
    client.add_holder(
        &vasp_admin_1,
        &vasp_id,
        &vasp_admin_2,
        &20_000_u128,
        &0_u32,
        &ref_id,
    );
    client.set_vasp_status(&worker, &vasp_id, &VaspStatus::Blocked, &ref_id);
    client.validate_transfer(&Some(vasp_admin_1), &Some(vasp_admin_2), &10_000_u128);
}

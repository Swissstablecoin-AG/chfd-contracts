#![cfg(test)]

extern crate std;

use super::*;
use chfd_vasp::{ChfdVaspContract, ChfdVaspContractClient};
use chfd_vasp_interface::{HolderStatus, VaspStatus};
use soroban_sdk::testutils::{Address as _, MuxedAddress as _};
use soroban_sdk::{token::TokenClient, Address, BytesN, Env, MuxedAddress};

fn id(env: &Env, value: u8) -> BytesN<32> {
    BytesN::from_array(env, &[value; 32])
}

fn upload_fixture_wasm(env: &Env) -> BytesN<32> {
    env.deployer().upload_contract_wasm(&[][..])
}

fn grant_update_operator(
    client: &ChfdVaspContractClient<'_>,
    platform_admin: &Address,
    operator: &Address,
) {
    client.grant_update_operator(platform_admin, operator);
    assert!(client.is_update_operator(operator));
}

struct TestContext {
    env: Env,
    vasp: ChfdVaspContractClient<'static>,
    chfd: ChfdContractClient<'static>,
    admin: Address,
    admin_failover: Address,
    worker: Address,
    outsider: Address,
    vasp_admin_1: Address,
    holder_1: Address,
    holder_2: Address,
    holder_3: Address,
    vasp_id_1: BytesN<32>,
    reference_id: BytesN<32>,
}

fn setup() -> TestContext {
    let env = Env::default();
    env.mock_all_auths();

    let admin = Address::generate(&env);
    let admin_failover = Address::generate(&env);
    let worker = Address::generate(&env);
    let outsider = Address::generate(&env);
    let vasp_admin_1 = Address::generate(&env);
    let holder_1 = Address::generate(&env);
    let holder_2 = Address::generate(&env);
    let holder_3 = Address::generate(&env);
    let vasp_id_1 = id(&env, 1);
    let reference_id = id(&env, 9);

    let vasp_id = env.register(ChfdVaspContract, (&admin, &admin_failover));
    let vasp = ChfdVaspContractClient::new(&env, &vasp_id);
    grant_update_operator(&vasp, &admin, &worker);
    vasp.add_vasp(&worker, &vasp_id_1, &vasp_admin_1, &reference_id);
    vasp.add_holder(
        &vasp_admin_1,
        &vasp_id_1,
        &holder_1,
        &10_000_u128,
        &0_u32,
        &reference_id,
    );
    vasp.add_holder(
        &vasp_admin_1,
        &vasp_id_1,
        &holder_2,
        &20_000_u128,
        &0_u32,
        &reference_id,
    );

    let chfd_id = env.register(ChfdContract, (&admin, &admin_failover, &vasp_id));
    let chfd = ChfdContractClient::new(&env, &chfd_id);

    TestContext {
        env,
        vasp,
        chfd,
        admin,
        admin_failover,
        worker,
        outsider,
        vasp_admin_1,
        holder_1,
        holder_2,
        holder_3,
        vasp_id_1,
        reference_id,
    }
}

#[test]
fn constructor_sets_expected_roles_and_vasp_address() {
    let ctx = setup();

    assert!(ctx.chfd.is_default_admin(&ctx.admin));
    assert!(ctx.chfd.is_default_admin(&ctx.admin_failover));
    assert!(ctx.chfd.is_minter(&ctx.admin));
    assert!(ctx.chfd.is_burner(&ctx.admin));
    assert!(ctx.chfd.is_enforcement(&ctx.admin));
    assert_eq!(ctx.chfd.decimals(), DECIMALS);
    assert_eq!(ctx.chfd.name(), String::from_str(&ctx.env, NAME));
    assert_eq!(ctx.chfd.symbol(), String::from_str(&ctx.env, SYMBOL));
    assert_eq!(
        ctx.chfd.get_vasp_contract_address(),
        ctx.vasp.address.clone()
    );
}

#[test]
fn grant_and_revoke_roles_work() {
    let ctx = setup();

    ctx.chfd.grant_minter_role(&ctx.admin, &ctx.worker);
    ctx.chfd.grant_burner_role(&ctx.admin, &ctx.worker);
    ctx.chfd.grant_enforcement_role(&ctx.admin, &ctx.worker);

    assert!(ctx.chfd.is_minter(&ctx.worker));
    assert!(ctx.chfd.is_burner(&ctx.worker));
    assert!(ctx.chfd.is_enforcement(&ctx.worker));

    ctx.chfd.revoke_minter_role(&ctx.admin, &ctx.worker);
    ctx.chfd.revoke_burner_role(&ctx.admin, &ctx.worker);
    ctx.chfd.revoke_enforcement_role(&ctx.admin, &ctx.worker);

    assert!(!ctx.chfd.is_minter(&ctx.worker));
    assert!(!ctx.chfd.is_burner(&ctx.worker));
    assert!(!ctx.chfd.is_enforcement(&ctx.worker));
}

#[test]
fn failover_admin_can_manage_roles() {
    let ctx = setup();

    ctx.chfd.grant_enforcement_role(&ctx.admin_failover, &ctx.worker);

    assert!(ctx.chfd.is_enforcement(&ctx.worker));
}

#[test]
fn granted_default_admin_can_manage_roles() {
    let ctx = setup();
    let backup_admin = Address::generate(&ctx.env);

    ctx.chfd
        .grant_default_admin_role(&ctx.admin, &backup_admin);
    assert!(ctx.chfd.is_default_admin(&backup_admin));

    ctx.chfd.grant_minter_role(&backup_admin, &ctx.worker);

    assert!(ctx.chfd.is_minter(&ctx.worker));
}

#[test]
fn default_admin_can_upgrade_contract() {
    let ctx = setup();
    let wasm_hash = upload_fixture_wasm(&ctx.env);

    ctx.chfd.upgrade(&ctx.admin, &wasm_hash);
}

#[test]
#[should_panic(expected = "Error(Contract, #2)")]
fn non_admin_cannot_upgrade_contract() {
    let ctx = setup();
    let wasm_hash = upload_fixture_wasm(&ctx.env);

    ctx.chfd.upgrade(&ctx.outsider, &wasm_hash);
}

#[test]
fn mint_succeeds_for_registered_active_holder() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &9_999_i128, &ctx.reference_id);

    assert_eq!(ctx.chfd.balance(&ctx.holder_1), 9_999);
    assert_eq!(ctx.chfd.total_supply(), 9_999);
}

#[test]
#[should_panic(expected = "Error(Contract, #11)")]
fn mint_reverts_if_receiver_holder_is_inactive() {
    let ctx = setup();
    ctx.vasp.set_holder_status(
        &ctx.vasp_admin_1,
        &ctx.vasp_id_1,
        &ctx.holder_1,
        &HolderStatus::Blocked,
        &ctx.reference_id,
    );

    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &100_i128, &ctx.reference_id);
}

#[test]
#[should_panic(expected = "Error(Contract, #2000)")]
fn only_minter_can_mint() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.outsider, &ctx.holder_1, &100_i128, &ctx.reference_id);
}

#[test]
fn burn_from_succeeds_for_enforcement_role() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &500_i128, &ctx.reference_id);
    ctx.chfd.grant_enforcement_role(&ctx.admin, &ctx.worker);

    ctx.chfd
        .enforcement_burn_from(&ctx.worker, &ctx.holder_1, &250_i128, &ctx.reference_id);

    assert_eq!(ctx.chfd.balance(&ctx.holder_1), 250);
    assert_eq!(ctx.chfd.total_supply(), 250);
}

#[test]
fn burn_with_ref_requires_burner_role_and_holder_auth() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &500_i128, &ctx.reference_id);
    ctx.chfd.grant_burner_role(&ctx.admin, &ctx.worker);

    ctx.chfd
        .burn_with_ref(&ctx.holder_1, &200_i128, &ctx.worker, &ctx.reference_id);

    assert_eq!(ctx.chfd.balance(&ctx.holder_1), 300);
    assert_eq!(ctx.chfd.total_supply(), 300);
}

#[test]
fn burn_from_with_auth_matches_burner_role_flow() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &500_i128, &ctx.reference_id);
    ctx.chfd.grant_burner_role(&ctx.admin, &ctx.worker);

    ctx.chfd.burn_from_with_auth(
        &ctx.worker,
        &ctx.holder_1,
        &200_i128,
        &ctx.reference_id,
    );

    assert_eq!(ctx.chfd.balance(&ctx.holder_1), 300);
    assert_eq!(ctx.chfd.total_supply(), 300);
}

#[test]
#[should_panic(expected = "Error(Contract, #4)")]
fn burner_role_is_required_for_burn_with_ref() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &500_i128, &ctx.reference_id);

    ctx.chfd
        .burn_with_ref(&ctx.holder_1, &200_i128, &ctx.worker, &ctx.reference_id);
}

#[test]
fn approve_and_transfer_from_work() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &1_000_i128, &ctx.reference_id);
    let expiration = ctx.env.ledger().sequence() + 100;

    ctx.chfd
        .approve(&ctx.holder_1, &ctx.worker, &400_i128, &expiration);
    assert_eq!(ctx.chfd.allowance(&ctx.holder_1, &ctx.worker), 400);

    ctx.chfd
        .transfer_from(&ctx.worker, &ctx.holder_1, &ctx.holder_2, &250_i128);

    assert_eq!(ctx.chfd.balance(&ctx.holder_1), 750);
    assert_eq!(ctx.chfd.balance(&ctx.holder_2), 250);
    assert_eq!(ctx.chfd.allowance(&ctx.holder_1, &ctx.worker), 150);
}

#[test]
fn standard_token_client_interacts_with_chfd() {
    let ctx = setup();
    let token = TokenClient::new(&ctx.env, &ctx.chfd.address);

    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &1_000_i128, &ctx.reference_id);
    token.approve(
        &ctx.holder_1,
        &ctx.worker,
        &300_i128,
        &(ctx.env.ledger().sequence() + 50),
    );
    token.transfer_from(&ctx.worker, &ctx.holder_1, &ctx.holder_2, &200_i128);

    assert_eq!(token.balance(&ctx.holder_1), 800);
    assert_eq!(token.balance(&ctx.holder_2), 200);
    assert_eq!(token.allowance(&ctx.holder_1, &ctx.worker), 100);
    assert_eq!(token.decimals(), DECIMALS);
    assert_eq!(token.name(), String::from_str(&ctx.env, NAME));
    assert_eq!(token.symbol(), String::from_str(&ctx.env, SYMBOL));
}

#[test]
fn transfer_between_registered_active_holders_succeeds() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &1_000_i128, &ctx.reference_id);

    let muxed_to = MuxedAddress::from(&ctx.holder_2);
    ctx.chfd.transfer(&ctx.holder_1, &muxed_to, &400_i128);

    assert_eq!(ctx.chfd.balance(&ctx.holder_1), 600);
    assert_eq!(ctx.chfd.balance(&ctx.holder_2), 400);
}

#[test]
fn transfer_accepts_muxed_destination_addresses() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &1_000_i128, &ctx.reference_id);

    let muxed_to = MuxedAddress::generate(&ctx.env);
    ctx.vasp.add_holder(
        &ctx.vasp_admin_1,
        &ctx.vasp_id_1,
        &muxed_to.address(),
        &20_000_u128,
        &0_u32,
        &ctx.reference_id,
    );

    ctx.chfd.transfer(&ctx.holder_1, &muxed_to, &400_i128);

    assert_eq!(ctx.chfd.balance(&muxed_to.address()), 400);
}

#[test]
#[should_panic(expected = "Error(Contract, #1000)")]
fn pause_blocks_regular_transfers() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &1_000_i128, &ctx.reference_id);
    ctx.chfd.pause(&ctx.admin);

    assert!(ctx.chfd.is_paused());

    ctx.chfd
        .transfer(&ctx.holder_1, &MuxedAddress::from(&ctx.holder_2), &100_i128);
}

#[test]
fn force_transfer_succeeds_while_paused_and_bypasses_vasp_validation() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &1_000_i128, &ctx.reference_id);
    ctx.vasp.set_holder_status(
        &ctx.vasp_admin_1,
        &ctx.vasp_id_1,
        &ctx.holder_1,
        &HolderStatus::Blocked,
        &ctx.reference_id,
    );
    ctx.chfd.pause(&ctx.admin);

    let ok = ctx.chfd.force_transfer(
        &ctx.admin,
        &ctx.holder_1,
        &ctx.holder_2,
        &250_i128,
        &ctx.reference_id,
    );

    assert!(ok);
    assert_eq!(ctx.chfd.balance(&ctx.holder_1), 750);
    assert_eq!(ctx.chfd.balance(&ctx.holder_2), 250);
}

#[test]
#[should_panic(expected = "Error(Contract, #5)")]
fn transfer_reverts_if_receiver_not_registered() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &1_000_i128, &ctx.reference_id);

    ctx.chfd
        .transfer(&ctx.holder_1, &MuxedAddress::from(&ctx.holder_3), &100_i128);
}

#[test]
#[should_panic(expected = "Error(Contract, #11)")]
fn transfer_reverts_if_sender_holder_is_inactive() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &500_i128, &ctx.reference_id);
    ctx.vasp.set_holder_status(
        &ctx.vasp_admin_1,
        &ctx.vasp_id_1,
        &ctx.holder_1,
        &HolderStatus::Blocked,
        &ctx.reference_id,
    );

    ctx.chfd
        .transfer(&ctx.holder_1, &MuxedAddress::from(&ctx.holder_2), &100_i128);
}

#[test]
#[should_panic(expected = "Error(Contract, #11)")]
fn transfer_reverts_if_receiver_holder_is_inactive() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &500_i128, &ctx.reference_id);
    ctx.vasp.set_holder_status(
        &ctx.vasp_admin_1,
        &ctx.vasp_id_1,
        &ctx.holder_2,
        &HolderStatus::Frozen,
        &ctx.reference_id,
    );

    ctx.chfd
        .transfer(&ctx.holder_1, &MuxedAddress::from(&ctx.holder_2), &100_i128);
}

#[test]
#[should_panic(expected = "Error(Contract, #12)")]
fn transfer_reverts_if_receiver_would_exceed_limit() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &10_000_i128, &ctx.reference_id);
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_2, &19_900_i128, &ctx.reference_id);

    ctx.chfd
        .transfer(&ctx.holder_1, &MuxedAddress::from(&ctx.holder_2), &101_i128);
}

#[test]
#[should_panic(expected = "Error(Contract, #10)")]
fn transfer_reverts_if_vasp_is_not_active() {
    let ctx = setup();
    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &500_i128, &ctx.reference_id);
    ctx.vasp.set_vasp_status(
        &ctx.worker,
        &ctx.vasp_id_1,
        &VaspStatus::Blocked,
        &ctx.reference_id,
    );

    ctx.chfd
        .transfer(&ctx.holder_1, &MuxedAddress::from(&ctx.holder_2), &100_i128);
}

#[test]
fn set_vasp_contract_address_updates_validation_source() {
    let ctx = setup();

    let new_vasp_admin = Address::generate(&ctx.env);
    let vasp_id_2 = id(&ctx.env, 2);

    let vasp_2_id = ctx
        .env
        .register(ChfdVaspContract, (&ctx.admin, &ctx.admin_failover));
    let vasp_2 = ChfdVaspContractClient::new(&ctx.env, &vasp_2_id);
    grant_update_operator(&vasp_2, &ctx.admin, &ctx.worker);

    vasp_2.add_vasp(&ctx.worker, &vasp_id_2, &new_vasp_admin, &ctx.reference_id);

    vasp_2.add_holder(
        &new_vasp_admin,
        &vasp_id_2,
        &ctx.holder_1,
        &10_000_u128,
        &0_u32,
        &ctx.reference_id,
    );

    vasp_2.add_holder(
        &new_vasp_admin,
        &vasp_id_2,
        &ctx.holder_2,
        &10_000_u128,
        &0_u32,
        &ctx.reference_id,
    );

    ctx.chfd
        .set_vasp_contract_address(&ctx.admin, &vasp_2_id);

    ctx.chfd
        .mint(&ctx.admin, &ctx.holder_1, &500_i128, &ctx.reference_id);

    ctx.chfd
        .transfer(&ctx.holder_1, &MuxedAddress::from(&ctx.holder_2), &100_i128);

    assert_eq!(ctx.chfd.balance(&ctx.holder_2), 100);
}

#![no_std]

use chfd_vasp_interface::{ChfdVaspContractClient, TransferVaspIds};
use soroban_sdk::{
    contract, contracterror, contractevent, contractimpl, contracttype, panic_with_error,
    token::TokenInterface, Address, BytesN, Env, MuxedAddress, String, Symbol,
};
use stellar_access::access_control::{
    grant_role_no_auth, has_role as access_has_role, revoke_role_no_auth,
};
use stellar_contract_utils::pausable::{self, Pausable};
use stellar_macros::{only_role, when_not_paused, when_paused};
use stellar_tokens::fungible::{
    self, burnable::emit_burn, Base, INSTANCE_EXTEND_AMOUNT, INSTANCE_TTL_THRESHOLD,
};

const DECIMALS: u32 = 6;
const NAME: &str = "Swiss Stablecoin";
const SYMBOL: &str = "CHFD";

#[derive(Clone)]
#[contracttype]
enum DataKey {
    VaspContract,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
#[repr(u32)]
#[contracterror]
pub enum Error {
    NotAdmin = 2,
    NotMinter = 3,
    NotBurner = 4,
    NotEnforcement = 5,
    ContractPaused = 10,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd", "mint"])]
struct MintEvent {
    #[topic]
    recipient_address: Address,
    operator: Address,
    reference_id: BytesN<32>,
    amount: i128,
    vasp_id: BytesN<32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd", "burn"])]
struct BurnEvent {
    #[topic]
    from_address: Address,
    operator: Address,
    reference_id: BytesN<32>,
    amount: i128,
    vasp_id: BytesN<32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd", "transfer_vasp"])]
struct ChfdTransferEvent {
    #[topic]
    from: Address,
    #[topic]
    to: Address,
    from_vasp_id: BytesN<32>,
    to_vasp_id: BytesN<32>,
    amount: i128,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd", "force_transfer"])]
struct ForceTransferEvent {
    #[topic]
    from: Address,
    #[topic]
    to: Address,
    operator: Address,
    reference_id: BytesN<32>,
    amount: i128,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd", "vasp_contract_updated"])]
struct VaspContractAddressUpdated {
    #[topic]
    previous_address: Address,
    #[topic]
    new_address: Address,
    operator: Address,
}

#[contract]
pub struct ChfdContract;

#[contractimpl]
impl ChfdContract {
    pub fn __constructor(env: &Env, admin: Address, admin_failover: Address, vasp_contract: Address) {
        admin.require_auth();

        set_role(env, &admin, &default_admin_role(env), true, &admin);
        set_role(env, &admin_failover, &default_admin_role(env), true, &admin);
        env.storage()
            .instance()
            .set(&DataKey::VaspContract, &vasp_contract);

        set_role(env, &admin, &minter_role(env), true, &admin);
        set_role(env, &admin, &burner_role(env), true, &admin);
        set_role(env, &admin, &enforcement_role(env), true, &admin);

        Base::set_metadata(
            env,
            DECIMALS,
            String::from_str(env, NAME),
            String::from_str(env, SYMBOL),
        );

        bump_instance(env);
    }

    pub fn get_vasp_contract_address(env: Env) -> Address {
        bump_instance(&env);
        get_vasp_contract_address(&env)
    }

    pub fn is_default_admin(env: Env, account: Address) -> bool {
        bump_instance(&env);
        is_default_admin(&env, &account)
    }

    pub fn grant_default_admin_role(env: Env, admin: Address, new_admin: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(&env, &new_admin, &default_admin_role(&env), true, &admin);
    }

    pub fn revoke_default_admin_role(env: Env, admin: Address, existing_admin: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(
            &env,
            &existing_admin,
            &default_admin_role(&env),
            false,
            &admin,
        );
    }

    pub fn upgrade(env: Env, admin: Address, new_wasm_hash: BytesN<32>) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        env.deployer().update_current_contract_wasm(new_wasm_hash);
    }

    pub fn set_vasp_contract_address(env: Env, admin: Address, vasp_contract: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);

        let previous_address = get_vasp_contract_address(&env);
        env.storage()
            .instance()
            .set(&DataKey::VaspContract, &vasp_contract);

        VaspContractAddressUpdated {
            previous_address,
            new_address: vasp_contract,
            operator: admin,
        }
        .publish(&env);
    }

    pub fn grant_minter_role(env: Env, admin: Address, worker: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(&env, &worker, &minter_role(&env), true, &admin);
    }

    pub fn revoke_minter_role(env: Env, admin: Address, worker: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(&env, &worker, &minter_role(&env), false, &admin);
    }

    pub fn grant_burner_role(env: Env, admin: Address, worker: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(&env, &worker, &burner_role(&env), true, &admin);
    }

    pub fn revoke_burner_role(env: Env, admin: Address, worker: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(&env, &worker, &burner_role(&env), false, &admin);
    }

    pub fn grant_mint_burn_roles(env: Env, admin: Address, worker: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(&env, &worker, &minter_role(&env), true, &admin);
        set_role(&env, &worker, &burner_role(&env), true, &admin);
    }

    pub fn revoke_mint_burn_roles(env: Env, admin: Address, worker: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(&env, &worker, &minter_role(&env), false, &admin);
        set_role(&env, &worker, &burner_role(&env), false, &admin);
    }

    pub fn grant_enforcement_role(env: Env, admin: Address, worker: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(&env, &worker, &enforcement_role(&env), true, &admin);
    }

    pub fn revoke_enforcement_role(env: Env, admin: Address, worker: Address) {
        bump_instance(&env);
        require_default_admin(&env, &admin);
        set_role(&env, &worker, &enforcement_role(&env), false, &admin);
    }

    pub fn is_minter(env: Env, worker: Address) -> bool {
        bump_instance(&env);
        has_role(&env, &worker, &minter_role(&env))
    }

    pub fn is_burner(env: Env, worker: Address) -> bool {
        bump_instance(&env);
        has_role(&env, &worker, &burner_role(&env))
    }

    pub fn is_enforcement(env: Env, worker: Address) -> bool {
        bump_instance(&env);
        has_role(&env, &worker, &enforcement_role(&env))
    }

    #[when_not_paused]
    #[only_role(operator, "minter")]
    pub fn mint(env: Env, operator: Address, to: Address, amount: i128, reference_id: BytesN<32>) {
        bump_instance(&env);

        let target_balance = checked_add(Base::balance(&env, &to), amount, &env);
        let vasp = vasp_client(&env);
        vasp.validate_transfer(&None, &Some(to.clone()), &to_u128(&env, target_balance));
        let vasp_id = vasp.get_holder_vasp_id(&to);

        Base::mint(&env, &to, amount);

        MintEvent {
            recipient_address: to,
            operator,
            reference_id,
            amount,
            vasp_id,
        }
        .publish(&env);
    }

    #[when_not_paused]
    pub fn burn_with_ref(env: Env, from: Address, amount: i128, operator: Address, reference_id: BytesN<32>) {
        burn_from_with_operator_auth(&env, &operator, &from, amount, &reference_id);
    }

    #[when_not_paused]
    pub fn burn_from_with_auth(
        env: Env,
        operator: Address,
        from: Address,
        amount: i128,
        reference_id: BytesN<32>,
    ) {
        burn_from_with_operator_auth(&env, &operator, &from, amount, &reference_id);
    }

    #[when_not_paused]
    #[only_role(operator, "burner")]
    pub fn burner_burn_from(
        env: Env,
        operator: Address,
        from: Address,
        amount: i128,
        reference_id: BytesN<32>,
    ) {
        bump_instance(&env);
        let vasp_id = validate_burn_or_transfer_out(&env, &from);

        Base::update(&env, Some(&from), None, amount);
        emit_burn(&env, &from, amount);

        BurnEvent {
            from_address: from,
            operator,
            reference_id,
            amount,
            vasp_id,
        }
        .publish(&env);
    }

    #[when_not_paused]
    #[only_role(operator, "enforcement")]
    pub fn enforcement_burn_from(
        env: Env,
        operator: Address,
        from: Address,
        amount: i128,
        reference_id: BytesN<32>,
    ) {
        bump_instance(&env);

        let vasp_id = validate_burn_or_transfer_out(&env, &from);

        Base::update(&env, Some(&from), None, amount);
        emit_burn(&env, &from, amount);

        BurnEvent {
            from_address: from,
            operator,
            reference_id,
            amount,
            vasp_id,
        }
        .publish(&env);
    }

    pub fn total_supply(env: Env) -> i128 {
        bump_instance(&env);
        Base::total_supply(&env)
    }

    pub fn is_paused(env: Env) -> bool {
        bump_instance(&env);
        pausable::paused(&env)
    }

    #[only_role(operator, "enforcement")]
    pub fn force_transfer(
        env: Env,
        operator: Address,
        from: Address,
        to: Address,
        amount: i128,
        reference_id: BytesN<32>,
    ) -> bool {
        bump_instance(&env);

        execute_transfer(&env, &from, &to, None, amount, false);

        ForceTransferEvent {
            from,
            to,
            operator,
            reference_id,
            amount,
        }
        .publish(&env);

        true
    }
}

#[contractimpl(contracttrait)]
impl TokenInterface for ChfdContract {
    fn allowance(env: Env, from: Address, spender: Address) -> i128 {
        bump_instance(&env);
        Base::allowance(&env, &from, &spender)
    }

    fn approve(env: Env, from: Address, spender: Address, amount: i128, expiration_ledger: u32) {
        bump_instance(&env);
        Base::approve(&env, &from, &spender, amount, expiration_ledger);
    }

    fn balance(env: Env, id: Address) -> i128 {
        bump_instance(&env);
        Base::balance(&env, &id)
    }

    #[when_not_paused]
    fn transfer(env: Env, from: Address, to: MuxedAddress, amount: i128) {
        bump_instance(&env);
        from.require_auth();
        execute_transfer(&env, &from, &to.address(), to.id(), amount, true);
    }

    #[when_not_paused]
    fn transfer_from(env: Env, spender: Address, from: Address, to: Address, amount: i128) {
        bump_instance(&env);
        spender.require_auth();
        validate_burn_or_transfer_out(&env, &from);
        Base::spend_allowance(&env, &from, &spender, amount);
        execute_transfer(&env, &from, &to, None, amount, true);
    }

    #[when_not_paused]
    fn burn_from(env: Env, spender: Address, from: Address, amount: i128) {
        bump_instance(&env);
        validate_burn_or_transfer_out(&env, &from);
        Base::burn_from(&env, &spender, &from, amount);
    }

    #[when_not_paused]
    fn burn(env: Env, from: Address, amount: i128) {
        bump_instance(&env);
        validate_burn_or_transfer_out(&env, &from);
        Base::burn(&env, &from, amount);
    }

    fn decimals(env: Env) -> u32 {
        bump_instance(&env);
        Base::decimals(&env)
    }

    fn name(env: Env) -> String {
        bump_instance(&env);
        Base::name(&env)
    }

    fn symbol(env: Env) -> String {
        bump_instance(&env);
        Base::symbol(&env)
    }
}

#[contractimpl(contracttrait)]
impl Pausable for ChfdContract {
    #[when_not_paused]
    #[only_role(caller, "enforcement")]
    fn pause(env: &Env, caller: Address) {
        bump_instance(env);
        pausable::pause(env);
    }

    #[when_paused]
    #[only_role(caller, "enforcement")]
    fn unpause(env: &Env, caller: Address) {
        bump_instance(env);
        pausable::unpause(env);
    }
}

fn bump_instance(env: &Env) {
    env.storage()
        .instance()
        .extend_ttl(INSTANCE_TTL_THRESHOLD, INSTANCE_EXTEND_AMOUNT);
}

fn default_admin_role(env: &Env) -> Symbol {
    Symbol::new(env, "default_admin")
}

fn minter_role(env: &Env) -> Symbol {
    Symbol::new(env, "minter")
}

fn burner_role(env: &Env) -> Symbol {
    Symbol::new(env, "burner")
}

fn enforcement_role(env: &Env) -> Symbol {
    Symbol::new(env, "enforcement")
}

fn has_role(env: &Env, account: &Address, role: &Symbol) -> bool {
    access_has_role(env, account, role).is_some()
}

fn is_default_admin(env: &Env, account: &Address) -> bool {
    has_role(env, account, &default_admin_role(env))
}

fn require_default_admin(env: &Env, account: &Address) {
    account.require_auth();
    if !is_default_admin(env, account) {
        panic_with_error!(env, Error::NotAdmin);
    }
}

fn set_role(env: &Env, account: &Address, role: &Symbol, enabled: bool, caller: &Address) {
    if enabled {
        grant_role_no_auth(env, account, role, caller);
    } else if has_role(env, account, role) {
        revoke_role_no_auth(env, account, role, caller);
    }
}

fn get_vasp_contract_address(env: &Env) -> Address {
    env.storage()
        .instance()
        .get(&DataKey::VaspContract)
        .unwrap()
}

fn vasp_client(env: &Env) -> ChfdVaspContractClient<'_> {
    let address = get_vasp_contract_address(env);
    ChfdVaspContractClient::new(env, &address)
}

fn validate_burn_or_transfer_out(env: &Env, from: &Address) -> BytesN<32> {
    let vasp = vasp_client(env);
    vasp.validate_transfer(&Some(from.clone()), &None, &0_u128);
    vasp.get_holder_vasp_id(from)
}

fn burn_from_with_operator_auth(
    env: &Env,
    operator: &Address,
    from: &Address,
    amount: i128,
    reference_id: &BytesN<32>,
) {
    bump_instance(env);
    operator.require_auth();
    from.require_auth();
    if !has_role(env, operator, &burner_role(env)) {
        panic_with_error!(env, Error::NotBurner);
    }

    let vasp_id = validate_burn_or_transfer_out(env, from);

    Base::update(env, Some(from), None, amount);
    emit_burn(env, from, amount);

    BurnEvent {
        from_address: from.clone(),
        operator: operator.clone(),
        reference_id: reference_id.clone(),
        amount,
        vasp_id,
    }
    .publish(env);
}

fn execute_transfer(
    env: &Env,
    from: &Address,
    to: &Address,
    to_muxed_id: Option<u64>,
    amount: i128,
    validate_vasp: bool,
) {
    if validate_vasp {
        let projected_receiver_balance = checked_add(Base::balance(env, to), amount, env);
        let vasp = vasp_client(env);
        vasp.validate_transfer(
            &Some(from.clone()),
            &Some(to.clone()),
            &to_u128(env, projected_receiver_balance),
        );
        let TransferVaspIds {
            from_vasp_id,
            to_vasp_id,
        } = vasp.get_transfer_vasp_ids(from, to);

        ChfdTransferEvent {
            from: from.clone(),
            to: to.clone(),
            from_vasp_id,
            to_vasp_id,
            amount,
        }
        .publish(env);
    }

    Base::update(env, Some(from), Some(to), amount);
    fungible::emit_transfer(env, from, to, to_muxed_id, amount);
}

fn checked_add(lhs: i128, rhs: i128, env: &Env) -> i128 {
    let _ = env;
    lhs.checked_add(rhs)
        .unwrap_or_else(|| panic!("balance overflow"))
}

fn to_u128(env: &Env, amount: i128) -> u128 {
    let _ = env;
    amount
        .try_into()
        .unwrap_or_else(|_| panic!("invalid negative amount"))
}

mod test;

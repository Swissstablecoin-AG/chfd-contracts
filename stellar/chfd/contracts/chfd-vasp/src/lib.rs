#![no_std]

use soroban_sdk::{
    contract, contracterror, contractevent, contractimpl, contracttype, panic_with_error, Address,
    BytesN, Env, Symbol,
};
use stellar_access::access_control::{
    grant_role_no_auth, has_role as access_has_role, revoke_role_no_auth,
};

use chfd_vasp_interface::{HolderDetails, HolderStatus, TransferVaspIds, VaspStatus};

const MAX_VASP_ADMINS: u32 = 10;

#[derive(Clone, Debug, Eq, PartialEq)]
#[contracttype]
pub struct Vasp {
    pub admin_count: u32,
    pub status: VaspStatus,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contracttype]
pub struct Holder {
    pub vasp_id: BytesN<32>,
    pub limit: u128,
    pub status: HolderStatus,
    pub vasp_owned: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd_vasp", "add_vasp"])]
struct AddVaspEvent {
    #[topic]
    vasp_id: BytesN<32>,
    operator: Address,
    reference_id: BytesN<32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd_vasp", "add_vasp_admin"])]
struct AddVaspAdminEvent {
    #[topic]
    vasp_id: BytesN<32>,
    #[topic]
    admin_address: Address,
    operator: Address,
    reference_id: BytesN<32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd_vasp", "remove_vasp_admin"])]
struct RemoveVaspAdminEvent {
    #[topic]
    vasp_id: BytesN<32>,
    #[topic]
    admin_address: Address,
    operator: Address,
    reference_id: BytesN<32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd_vasp", "add_holder"])]
struct AddHolderEvent {
    #[topic]
    vasp_id: BytesN<32>,
    #[topic]
    holder_address: Address,
    operator: Address,
    reference_id: BytesN<32>,
    holder_limit: u128,
    vasp_owned: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd_vasp", "set_vasp_status"])]
struct SetVaspStatusEvent {
    #[topic]
    vasp_id: BytesN<32>,
    operator: Address,
    reference_id: BytesN<32>,
    previous_status: VaspStatus,
    new_status: VaspStatus,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd_vasp", "set_holder_limit"])]
struct SetHolderLimitEvent {
    #[topic]
    vasp_id: BytesN<32>,
    #[topic]
    holder_address: Address,
    operator: Address,
    reference_id: BytesN<32>,
    previous_limit: u128,
    new_limit: u128,
}

#[derive(Clone, Debug, Eq, PartialEq)]
#[contractevent(topics = ["chfd_vasp", "set_holder_status"])]
struct SetHolderStatusEvent {
    #[topic]
    vasp_id: BytesN<32>,
    #[topic]
    holder_address: Address,
    operator: Address,
    reference_id: BytesN<32>,
    previous_status: HolderStatus,
    new_status: HolderStatus,
}

#[derive(Clone)]
#[contracttype]
struct VaspAdminKey {
    vasp_id: BytesN<32>,
    admin: Address,
}

#[derive(Clone)]
#[contracttype]
enum DataKey {
    Vasp(BytesN<32>),
    VaspAdmin(VaspAdminKey),
    Holder(Address),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
#[repr(u32)]
#[contracterror]
pub enum Error {
    InvalidVaspId = 2,
    VaspDoesNotExist = 3,
    NotVaspAdmin = 4,
    HolderDoesNotExist = 5,
    VaspAlreadyExists = 6,
    VaspAdminAlreadyExists = 7,
    VaspAdminDoesNotExist = 8,
    HolderAlreadyExists = 9,
    VaspNotActive = 10,
    HolderNotActive = 11,
    ExceedsHolderLimit = 12,
    HolderDoesNotBelongToVasp = 13,
    InvalidStatus = 14,
    CannotRemoveLastVaspAdmin = 15,
    MaxVaspAdminsReached = 16,
    NotPlatformOperator = 17,
}

#[contract]
pub struct ChfdVaspContract;

#[contractimpl]
impl ChfdVaspContract {
    pub fn __constructor(env: &Env, platform_admin: Address, platform_admin_failover: Address) {
        platform_admin.require_auth();
        set_role(
            env,
            &platform_admin,
            &default_admin_role(env),
            true,
            &platform_admin,
        );
        set_role(
            env,
            &platform_admin_failover,
            &default_admin_role(env),
            true,
            &platform_admin,
        );
    }

    pub fn is_default_admin(env: Env, account: Address) -> bool {
        is_default_admin(&env, &account)
    }

    pub fn grant_default_admin_role(env: Env, admin: Address, new_admin: Address) {
        require_default_admin(&env, &admin);
        set_role(&env, &new_admin, &default_admin_role(&env), true, &admin);
    }

    pub fn revoke_default_admin_role(env: Env, admin: Address, existing_admin: Address) {
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
        require_default_admin(&env, &admin);
        env.deployer().update_current_contract_wasm(new_wasm_hash);
    }

    pub fn grant_update_operator(env: Env, admin: Address, worker: Address) {
        require_default_admin(&env, &admin);
        let platform_admin = admin;
        grant_role_no_auth(&env, &worker, &update_operator_role(&env), &platform_admin);
    }

    pub fn revoke_update_operator(env: Env, admin: Address, worker: Address) {
        require_default_admin(&env, &admin);
        let platform_admin = admin;
        if access_has_role(&env, &worker, &update_operator_role(&env)).is_some() {
            revoke_role_no_auth(&env, &worker, &update_operator_role(&env), &platform_admin);
        }
    }

    pub fn is_update_operator(env: Env, worker: Address) -> bool {
        is_update_operator(&env, &worker)
    }

    pub fn add_vasp(
        env: Env,
        operator: Address,
        vasp_id: BytesN<32>,
        vasp_admin: Address,
        reference_id: BytesN<32>,
    ) -> BytesN<32> {
        operator.require_auth();

        require_update_operator(&env, &operator);
        require_valid_vasp_id(&env, &vasp_id);

        if has_vasp(&env, &vasp_id) {
            panic_with_error!(&env, Error::VaspAlreadyExists);
        }
        if has_holder(&env, &vasp_admin) {
            panic_with_error!(&env, Error::HolderAlreadyExists);
        }

        env.storage().persistent().set(
            &DataKey::Vasp(vasp_id.clone()),
            &Vasp {
                admin_count: 1,
                status: VaspStatus::Active,
            },
        );
        set_vasp_admin_membership(&env, &vasp_id, &vasp_admin, true);
        env.storage().persistent().set(
            &DataKey::Holder(vasp_admin.clone()),
            &Holder {
                vasp_id: vasp_id.clone(),
                limit: 0,
                status: HolderStatus::Active,
                vasp_owned: 0,
            },
        );

        AddVaspEvent {
            operator: operator.clone(),
            reference_id: reference_id.clone(),
            vasp_id: vasp_id.clone(),
        }
        .publish(&env);
        AddVaspAdminEvent {
            operator: operator.clone(),
            reference_id: reference_id.clone(),
            vasp_id: vasp_id.clone(),
            admin_address: vasp_admin.clone(),
        }
        .publish(&env);
        AddHolderEvent {
            operator,
            reference_id,
            vasp_id: vasp_id.clone(),
            holder_address: vasp_admin,
            holder_limit: 0_u128,
            vasp_owned: 0,
        }
        .publish(&env);

        vasp_id
    }

    pub fn verify_vasp_admin(
        env: Env,
        vasp_id: BytesN<32>,
        vasp_admin: Address,
        reference_id: BytesN<32>,
    ) -> BytesN<32> {
        vasp_admin.require_auth();
        require_valid_vasp_id(&env, &vasp_id);
        reference_id
    }

    pub fn set_vasp_status(
        env: Env,
        operator: Address,
        vasp_id: BytesN<32>,
        status: VaspStatus,
        reference_id: BytesN<32>,
    ) {
        operator.require_auth();
        require_update_operator(&env, &operator);
        require_vasp(&env, &vasp_id);

        if status == VaspStatus::None {
            panic_with_error!(&env, Error::InvalidStatus);
        }

        let key = DataKey::Vasp(vasp_id.clone());
        let mut vasp = get_vasp(&env, &vasp_id);
        let previous_status = vasp.status;
        vasp.status = status;
        env.storage().persistent().set(&key, &vasp);

        SetVaspStatusEvent {
            operator,
            reference_id,
            vasp_id,
            previous_status,
            new_status: status,
        }
        .publish(&env);
    }

    pub fn add_vasp_admin(
        env: Env,
        operator: Address,
        admin: Address,
        vasp_id: BytesN<32>,
        new_admin: Address,
        reference_id: BytesN<32>,
    ) {
        operator.require_auth();
        admin.require_auth();
        require_update_operator(&env, &operator);
        require_vasp(&env, &vasp_id);
        require_vasp_admin(&env, &vasp_id, &admin);

        add_vasp_admin_internal(&env, &vasp_id, &new_admin, &operator, &reference_id);
    }

    pub fn remove_vasp_admin(
        env: Env,
        operator: Address,
        admin: Address,
        vasp_id: BytesN<32>,
        admin_to_remove: Address,
        reference_id: BytesN<32>,
    ) {
        operator.require_auth();
        admin.require_auth();
        require_update_operator(&env, &operator);
        require_vasp(&env, &vasp_id);
        require_vasp_admin(&env, &vasp_id, &admin);

        let admin_key = make_vasp_admin_key(&vasp_id, &admin_to_remove);
        if !env
            .storage()
            .persistent()
            .has(&DataKey::VaspAdmin(admin_key))
        {
            panic_with_error!(&env, Error::VaspAdminDoesNotExist);
        }

        let vasp_key = DataKey::Vasp(vasp_id.clone());
        let mut vasp = get_vasp(&env, &vasp_id);
        if vasp.admin_count == 1 {
            panic_with_error!(&env, Error::CannotRemoveLastVaspAdmin);
        }

        vasp.admin_count -= 1;
        env.storage().persistent().set(&vasp_key, &vasp);
        set_vasp_admin_membership(&env, &vasp_id, &admin_to_remove, false);

        RemoveVaspAdminEvent {
            operator,
            reference_id,
            vasp_id,
            admin_address: admin_to_remove,
        }
        .publish(&env);
    }

    pub fn add_holder(
        env: Env,
        admin: Address,
        vasp_id: BytesN<32>,
        holder_address: Address,
        holder_limit: u128,
        vasp_owned: u32,
        reference_id: BytesN<32>,
    ) {
        admin.require_auth();
        require_vasp(&env, &vasp_id);
        require_vasp_admin(&env, &vasp_id, &admin);
        require_vasp_active(&env, &vasp_id);

        if has_holder(&env, &holder_address) {
            panic_with_error!(&env, Error::HolderAlreadyExists);
        }

        env.storage().persistent().set(
            &DataKey::Holder(holder_address.clone()),
            &Holder {
                vasp_id: vasp_id.clone(),
                limit: holder_limit,
                status: HolderStatus::Active,
                vasp_owned,
            },
        );

        AddHolderEvent {
            operator: admin,
            reference_id,
            vasp_id,
            holder_address,
            holder_limit,
            vasp_owned,
        }
        .publish(&env);
    }

    pub fn set_holder_limit(
        env: Env,
        admin: Address,
        vasp_id: BytesN<32>,
        holder_address: Address,
        holder_limit: u128,
        reference_id: BytesN<32>,
    ) {
        admin.require_auth();
        require_vasp(&env, &vasp_id);
        require_vasp_admin(&env, &vasp_id, &admin);
        require_holder(&env, &holder_address);
        require_vasp_active(&env, &vasp_id);

        let key = DataKey::Holder(holder_address.clone());
        let mut holder = get_holder(&env, &holder_address);
        if holder.vasp_id != vasp_id {
            panic_with_error!(&env, Error::HolderDoesNotBelongToVasp);
        }

        let previous_limit = holder.limit;
        holder.limit = holder_limit;
        env.storage().persistent().set(&key, &holder);

        SetHolderLimitEvent {
            operator: admin,
            reference_id,
            vasp_id,
            holder_address,
            previous_limit,
            new_limit: holder_limit,
        }
        .publish(&env);
    }

    pub fn set_holder_status(
        env: Env,
        admin: Address,
        vasp_id: BytesN<32>,
        holder_address: Address,
        status: HolderStatus,
        reference_id: BytesN<32>,
    ) {
        admin.require_auth();
        require_vasp(&env, &vasp_id);
        require_vasp_admin(&env, &vasp_id, &admin);
        require_holder(&env, &holder_address);
        require_vasp_active(&env, &vasp_id);

        if status == HolderStatus::None {
            panic_with_error!(&env, Error::InvalidStatus);
        }

        let key = DataKey::Holder(holder_address.clone());
        let mut holder = get_holder(&env, &holder_address);
        if holder.vasp_id != vasp_id {
            panic_with_error!(&env, Error::HolderDoesNotBelongToVasp);
        }

        let previous_status = holder.status;
        holder.status = status;
        env.storage().persistent().set(&key, &holder);

        SetHolderStatusEvent {
            operator: admin,
            reference_id,
            vasp_id,
            holder_address,
            previous_status,
            new_status: status,
        }
        .publish(&env);
    }

    pub fn get_vasp_details(env: Env, vasp_id: BytesN<32>) -> VaspStatus {
        env.storage()
            .persistent()
            .get::<_, Vasp>(&DataKey::Vasp(vasp_id))
            .map(|vasp| vasp.status)
            .unwrap_or(VaspStatus::None)
    }

    pub fn get_vasp_admin_status(env: Env, vasp_id: BytesN<32>, member_address: Address) -> bool {
        env.storage()
            .persistent()
            .get::<_, bool>(&DataKey::VaspAdmin(make_vasp_admin_key(
                &vasp_id,
                &member_address,
            )))
            .unwrap_or(false)
    }

    pub fn get_holder_details(env: Env, holder_address: Address) -> HolderDetails {
        let zero = zero_vasp_id(&env);
        env.storage()
            .persistent()
            .get::<_, Holder>(&DataKey::Holder(holder_address))
            .map(|holder| HolderDetails {
                limit: holder.limit,
                status: holder.status,
                vasp_id: holder.vasp_id,
                vasp_owned: holder.vasp_owned,
            })
            .unwrap_or(HolderDetails {
                limit: 0,
                status: HolderStatus::None,
                vasp_id: zero,
                vasp_owned: 0,
            })
    }

    pub fn get_holder_vasp_id(env: Env, holder_address: Address) -> BytesN<32> {
        env.storage()
            .persistent()
            .get::<_, Holder>(&DataKey::Holder(holder_address))
            .map(|holder| holder.vasp_id)
            .unwrap_or_else(|| zero_vasp_id(&env))
    }

    pub fn get_transfer_vasp_ids(env: Env, from: Address, to: Address) -> TransferVaspIds {
        TransferVaspIds {
            from_vasp_id: Self::get_holder_vasp_id(env.clone(), from),
            to_vasp_id: Self::get_holder_vasp_id(env, to),
        }
    }

    pub fn validate_transfer(
        env: Env,
        from: Option<Address>,
        to: Option<Address>,
        target_amount: u128,
    ) {
        if let Some(from_address) = from {
            require_holder(&env, &from_address);
            validate_status(&env, &from_address);
        }

        if let Some(to_address) = to {
            require_holder(&env, &to_address);
            validate_amount(&env, &to_address, target_amount);
        }
    }
}

fn is_update_operator(env: &Env, address: &Address) -> bool {
    access_has_role(env, address, &update_operator_role(env)).is_some()
}

fn require_update_operator(env: &Env, address: &Address) {
    if !is_update_operator(env, address) {
        panic_with_error!(env, Error::NotPlatformOperator);
    }
}

fn default_admin_role(env: &Env) -> Symbol {
    Symbol::new(env, "default_admin")
}

fn is_default_admin(env: &Env, address: &Address) -> bool {
    access_has_role(env, address, &default_admin_role(env)).is_some()
}

fn require_default_admin(env: &Env, address: &Address) {
    address.require_auth();
    if !is_default_admin(env, address) {
        panic_with_error!(env, Error::NotPlatformOperator);
    }
}

fn require_valid_vasp_id(env: &Env, vasp_id: &BytesN<32>) {
    if *vasp_id == zero_vasp_id(env) {
        panic_with_error!(env, Error::InvalidVaspId);
    }
}

fn update_operator_role(env: &Env) -> Symbol {
    Symbol::new(env, "update_operator")
}

fn set_role(env: &Env, account: &Address, role: &Symbol, enabled: bool, caller: &Address) {
    if enabled {
        grant_role_no_auth(env, account, role, caller);
    } else if access_has_role(env, account, role).is_some() {
        revoke_role_no_auth(env, account, role, caller);
    }
}

fn zero_vasp_id(env: &Env) -> BytesN<32> {
    BytesN::from_array(env, &[0; 32])
}

fn has_vasp(env: &Env, vasp_id: &BytesN<32>) -> bool {
    env.storage()
        .persistent()
        .has(&DataKey::Vasp(vasp_id.clone()))
}

fn get_vasp(env: &Env, vasp_id: &BytesN<32>) -> Vasp {
    env.storage()
        .persistent()
        .get(&DataKey::Vasp(vasp_id.clone()))
        .unwrap()
}

fn require_vasp(env: &Env, vasp_id: &BytesN<32>) {
    require_valid_vasp_id(env, vasp_id);
    if !has_vasp(env, vasp_id) {
        panic_with_error!(env, Error::VaspDoesNotExist);
    }
}

fn require_vasp_active(env: &Env, vasp_id: &BytesN<32>) {
    let vasp = get_vasp(env, vasp_id);
    if vasp.status != VaspStatus::Active {
        panic_with_error!(env, Error::VaspNotActive);
    }
}

fn make_vasp_admin_key(vasp_id: &BytesN<32>, admin: &Address) -> VaspAdminKey {
    VaspAdminKey {
        vasp_id: vasp_id.clone(),
        admin: admin.clone(),
    }
}

fn set_vasp_admin_membership(env: &Env, vasp_id: &BytesN<32>, admin: &Address, is_member: bool) {
    let key = DataKey::VaspAdmin(make_vasp_admin_key(vasp_id, admin));
    if is_member {
        env.storage().persistent().set(&key, &true);
    } else {
        env.storage().persistent().remove(&key);
    }
}

fn require_vasp_admin(env: &Env, vasp_id: &BytesN<32>, admin: &Address) {
    let is_member = env
        .storage()
        .persistent()
        .get::<_, bool>(&DataKey::VaspAdmin(make_vasp_admin_key(vasp_id, admin)))
        .unwrap_or(false);
    if !is_member {
        panic_with_error!(env, Error::NotVaspAdmin);
    }
}

fn has_holder(env: &Env, holder_address: &Address) -> bool {
    env.storage()
        .persistent()
        .has(&DataKey::Holder(holder_address.clone()))
}

fn get_holder(env: &Env, holder_address: &Address) -> Holder {
    env.storage()
        .persistent()
        .get(&DataKey::Holder(holder_address.clone()))
        .unwrap()
}

fn require_holder(env: &Env, holder_address: &Address) {
    if !has_holder(env, holder_address) {
        panic_with_error!(env, Error::HolderDoesNotExist);
    }
}

fn add_vasp_admin_internal(
    env: &Env,
    vasp_id: &BytesN<32>,
    new_admin: &Address,
    operator: &Address,
    reference_id: &BytesN<32>,
) {
    let admin_key = make_vasp_admin_key(vasp_id, new_admin);
    if env
        .storage()
        .persistent()
        .has(&DataKey::VaspAdmin(admin_key))
    {
        panic_with_error!(env, Error::VaspAdminAlreadyExists);
    }

    let vasp_key = DataKey::Vasp(vasp_id.clone());
    let mut vasp = get_vasp(env, vasp_id);
    if vasp.admin_count == MAX_VASP_ADMINS {
        panic_with_error!(env, Error::MaxVaspAdminsReached);
    }

    if has_holder(env, new_admin) {
        let holder = get_holder(env, new_admin);
        if holder.vasp_id != *vasp_id {
            panic_with_error!(env, Error::HolderAlreadyExists);
        }
    } else {
        env.storage().persistent().set(
            &DataKey::Holder(new_admin.clone()),
            &Holder {
                vasp_id: vasp_id.clone(),
                limit: 0,
                status: HolderStatus::Active,
                vasp_owned: 0,
            },
        );
        AddHolderEvent {
            operator: operator.clone(),
            reference_id: reference_id.clone(),
            vasp_id: vasp_id.clone(),
            holder_address: new_admin.clone(),
            holder_limit: 0_u128,
            vasp_owned: 0,
        }
        .publish(env);
    }

    vasp.admin_count += 1;
    env.storage().persistent().set(&vasp_key, &vasp);
    set_vasp_admin_membership(env, vasp_id, new_admin, true);

    AddVaspAdminEvent {
        operator: operator.clone(),
        reference_id: reference_id.clone(),
        vasp_id: vasp_id.clone(),
        admin_address: new_admin.clone(),
    }
    .publish(env);
}

fn validate_status(env: &Env, holder_address: &Address) {
    let holder = get_holder(env, holder_address);
    let vasp = get_vasp(env, &holder.vasp_id);

    if vasp.status != VaspStatus::Active {
        panic_with_error!(env, Error::VaspNotActive);
    }
    if holder.status != HolderStatus::Active {
        panic_with_error!(env, Error::HolderNotActive);
    }
}

fn validate_amount(env: &Env, holder_address: &Address, total_holding_amount: u128) {
    let holder = get_holder(env, holder_address);
    let vasp = get_vasp(env, &holder.vasp_id);

    if vasp.status != VaspStatus::Active {
        panic_with_error!(env, Error::VaspNotActive);
    }
    if holder.status != HolderStatus::Active {
        panic_with_error!(env, Error::HolderNotActive);
    }
    if total_holding_amount > holder.limit {
        panic_with_error!(env, Error::ExceedsHolderLimit);
    }
}

mod test;

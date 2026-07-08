//! Interfaces and configuration schema for the Adventurer Oracle.

use starknet::ContractAddress;
use crate::types::{Adventurer, Bag};

// ---------------------------------------------------------------------------
// Objective component conformance (game-components `IMinigameObjectives`)
// ---------------------------------------------------------------------------

/// SNIP-5 interface id for `IMinigameObjectives`, copied verbatim from
/// `game_components_interfaces::minigame::objectives` so this oracle registers the
/// same SRC5 id and is discoverable as an objectives provider by Denshokan / Budokan.
pub const IMINIGAME_OBJECTIVES_ID: felt252 =
    0xac0aaa451454d78741d9fafe803b69c8b31d073156020b08496104356db5e5;

/// Mirror of `game_components_interfaces::structs::minigame::GameObjective`.
#[derive(Drop, Serde, Copy)]
pub struct GameObjective {
    pub name: felt252,
    pub value: felt252,
}

/// Mirror of `game_components_interfaces::structs::minigame::GameObjectiveDetails`.
#[derive(Drop, Serde, Clone)]
pub struct GameObjectiveDetails {
    pub name: ByteArray,
    pub description: ByteArray,
    pub objectives: Span<GameObjective>,
}

/// The canonical objective-checker interface consumed by Denshokan / Budokan.
#[starknet::interface]
pub trait IMinigameObjectives<TState> {
    fn objective_exists(self: @TState, objective_id: u32) -> bool;
    fn completed_objective(self: @TState, token_id: felt252, objective_id: u32) -> bool;
    fn objective_exists_batch(self: @TState, objective_ids: Span<u32>) -> Array<bool>;
}

/// Optional render/detail surface for the objective component.
#[starknet::interface]
pub trait IMinigameObjectivesDetails<TState> {
    fn objectives_count(self: @TState) -> u32;
    fn objectives_details(self: @TState, objective_id: u32) -> GameObjectiveDetails;
    fn objectives_details_batch(
        self: @TState, objective_ids: Span<u32>,
    ) -> Array<GameObjectiveDetails>;
}

// ---------------------------------------------------------------------------
// Objective configuration schema
// ---------------------------------------------------------------------------

/// The adventurer attribute a single objective CONDITION evaluates.
///
/// Scalar metrics compare a single numeric attribute against `Condition.target`
/// using `Condition.comparator`. Item metrics use `target` as the item id (and,
/// for `ItemGreatness`, `aux` as the greatness threshold compared via `comparator`).
///
/// "Own a whole SET of items" is NOT a metric — it is the objective-level `items`
/// list (see `create_objective`), so a set requirement is one entry, not one
/// condition per id.
///
/// Adding a new scalar metric is a one-line change in `oracle_lib::scalar_value`.
#[allow(starknet::store_no_default_variant)]
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum Metric {
    // -- Scalars ---------------------------------------------------------
    Xp,
    Level,
    Gold,
    Health,
    BeastHealth,
    StatUpgradesAvailable,
    // -- Stats -----------------------------------------------------------
    Strength,
    Dexterity,
    Vitality,
    Intelligence,
    Wisdom,
    Charisma,
    Luck,
    // -- Item checks (target = item id) ---------------------------------
    /// Item held anywhere: equipped OR in the bag.
    ItemHeldAnywhere,
    /// Item currently equipped in one of the 8 equipment slots.
    ItemEquipped,
    /// Item present in the 15-slot bag.
    ItemInBag,
    /// Greatness (derived from item xp) of item `target`, taken as the max across
    /// equipped + bag copies, compared against `aux` via `comparator`. Absent item
    /// yields greatness 0 (fails an `AtLeast`/`GreaterThan` check).
    ItemGreatness,
}

/// How the extracted value is compared against the objective target.
#[allow(starknet::store_no_default_variant)]
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum Comparator {
    AtLeast,
    AtMost,
    Equal,
    GreaterThan,
    LessThan,
    NotEqual,
}

/// One check within an objective. An objective is a CONJUNCTION of conditions (all
/// must pass), so a single-metric objective is one condition and a "score + gold +
/// item" objective is several. Fixed-size (no item list) — the objective's item set
/// lives separately (see `create_objective`'s `items`).
///
/// - `metric` / `comparator` / `target`: the attribute check (`target` is the item id
///   for the single-item metrics).
/// - `aux`: auxiliary parameter (currently only the greatness threshold for
///   `Metric::ItemGreatness`; must be 0 otherwise for clarity).
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub struct Condition {
    pub metric: Metric,
    pub comparator: Comparator,
    pub target: u64,
    pub aux: u64,
}

// ---------------------------------------------------------------------------
// Oracle admin / read interface
// ---------------------------------------------------------------------------

#[starknet::interface]
pub trait IAdventurerOracle<TState> {
    /// Register a new objective. Owner-only. Returns the assigned objective id
    /// (sequential, starting at 1).
    ///
    /// An objective is complete for a token iff the token's `settings_id` matches AND
    /// every condition in `conditions` passes AND — when `items` is `Some` — the
    /// adventurer holds ALL of those item ids (equipped or in the bag). `items` is
    /// `None` (or an empty array) for objectives with no set requirement.
    ///
    /// Reverts if `settings_id` does not exist on the settings source, if the objective
    /// has no requirements at all (no conditions and no items), or if `items` contains a
    /// zero id.
    fn create_objective(
        ref self: TState,
        name: ByteArray,
        description: ByteArray,
        settings_id: u32,
        conditions: Array<Condition>,
        items: Option<Array<u8>>,
    ) -> u32;

    /// The settings id an objective is scoped to (panics if it does not exist).
    fn get_objective_settings_id(self: @TState, objective_id: u32) -> u32;
    /// The conditions registered for an objective (panics if it does not exist).
    fn get_objective_conditions(self: @TState, objective_id: u32) -> Array<Condition>;
    /// The required item id set for an objective (empty when there is none).
    fn get_objective_items(self: @TState, objective_id: u32) -> Array<u8>;

    fn owner(self: @TState) -> ContractAddress;
    fn transfer_ownership(ref self: TState, new_owner: ContractAddress);

    // Source addresses (for transparency / off-chain indexing).
    fn adventurer_source(self: @TState) -> ContractAddress;
    fn token_source(self: @TState) -> ContractAddress;
    fn settings_source(self: @TState) -> ContractAddress;
}

// ---------------------------------------------------------------------------
// External source contracts the oracle reads from
// ---------------------------------------------------------------------------

/// Adventurer state source. In production this is the Death Mountain GameCore contract
/// (`death_mountain::systems::game_core::IGameCore`). `load_assets` returns the live,
/// stat-boosted adventurer plus its bag, which is exactly the state objectives evaluate.
#[starknet::interface]
pub trait IAdventurerStateSource<TState> {
    fn load_assets(self: @TState, adventurer_id: felt252) -> (Adventurer, Bag);
}

/// Token metadata source. In production this is the Denshokan minigame token contract
/// (`game_components_interfaces::minigame::token IMinigameToken`), which records the
/// `settings_id` each token was minted with.
#[starknet::interface]
pub trait ITokenSettingsSource<TState> {
    fn settings_id(self: @TState, token_id: felt252) -> u32;
}

/// Settings registry source. In production this is the Death Mountain GameToken contract
/// (`IMinigameSettings::settings_exist`), used to validate an objective's `settings_id`
/// at registration time.
#[starknet::interface]
pub trait IGameSettingsSource<TState> {
    fn settings_exist(self: @TState, settings_id: u32) -> bool;
}

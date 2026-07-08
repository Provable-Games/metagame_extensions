//! Local mirror of the Death Mountain adventurer state structs.
//!
//! These structs intentionally duplicate the layout of the corresponding types in
//! `death_mountain::models::{adventurer, stats, equipment, item, bag}` so that the
//! oracle can decode the return value of the game contract's
//! `load_assets(token_id) -> (Adventurer, Bag)` view via Serde **without** taking a
//! heavyweight dependency on the whole `death_mountain` crate (which pins a different
//! Scarb/starknet toolchain and pulls in Ekubo + the full game). This mirrors the
//! existing "define the minimal interface locally" convention used elsewhere in this
//! workspace (see `presets/src/externals/game_components.cairo`).
//!
//! IMPORTANT: The field order below MUST match the on-chain structs field-for-field,
//! because Serde encodes/decodes positionally. If the game contract changes its struct
//! layout, this mirror must be updated in lockstep.

/// Mirror of `death_mountain::models::item::Item`.
#[derive(Drop, Copy, PartialEq, Serde, starknet::Store)]
pub struct Item {
    pub id: u8,
    pub xp: u16,
}

/// Mirror of `death_mountain::models::stats::Stats`.
#[derive(Drop, Copy, PartialEq, Serde, starknet::Store)]
pub struct Stats {
    pub strength: u8,
    pub dexterity: u8,
    pub vitality: u8,
    pub intelligence: u8,
    pub wisdom: u8,
    pub charisma: u8,
    pub luck: u8,
}

/// Mirror of `death_mountain::models::equipment::Equipment`.
#[derive(Drop, Copy, PartialEq, Serde, starknet::Store)]
pub struct Equipment {
    pub weapon: Item,
    pub chest: Item,
    pub head: Item,
    pub waist: Item,
    pub foot: Item,
    pub hand: Item,
    pub neck: Item,
    pub ring: Item,
}

/// Mirror of `death_mountain::models::adventurer::Adventurer`.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Adventurer {
    pub health: u16,
    pub xp: u16,
    pub gold: u16,
    pub beast_health: u16,
    pub stat_upgrades_available: u8,
    pub stats: Stats,
    pub equipment: Equipment,
    pub item_specials_salt: u16,
    pub beast_salt: u32,
    pub level_salt: u16,
}

/// Mirror of `death_mountain::models::bag::Bag`.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Bag {
    pub item_1: Item,
    pub item_2: Item,
    pub item_3: Item,
    pub item_4: Item,
    pub item_5: Item,
    pub item_6: Item,
    pub item_7: Item,
    pub item_8: Item,
    pub item_9: Item,
    pub item_10: Item,
    pub item_11: Item,
    pub item_12: Item,
    pub item_13: Item,
    pub item_14: Item,
    pub item_15: Item,
    pub mutated: bool,
}

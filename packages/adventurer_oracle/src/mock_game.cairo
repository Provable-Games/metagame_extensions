//! Test-only mock of the Death Mountain game contracts.
//!
//! Combines the three source surfaces the oracle reads from into one deployable
//! contract so unit tests are fully deterministic (no fork required):
//!   - `IAdventurerStateSource::load_assets` (GameCore in prod)
//!   - `ITokenSettingsSource::settings_id`  (Denshokan in prod)
//!   - `IGameSettingsSource::settings_exist` (GameToken in prod)
//!
//! Plus setters to seed per-token adventurer/bag state and settings registrations.

use crate::types::{Adventurer, Bag};

#[starknet::interface]
pub trait IMockGame<TState> {
    fn set_assets(ref self: TState, token_id: felt252, adventurer: Adventurer, bag: Bag);
    fn set_token_settings(ref self: TState, token_id: felt252, settings_id: u32);
    fn set_settings_exists(ref self: TState, settings_id: u32, exists: bool);
}

#[starknet::contract]
pub mod MockGame {
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use crate::interface::{IAdventurerStateSource, IGameSettingsSource, ITokenSettingsSource};
    use crate::types::{Adventurer, Bag};
    use super::IMockGame;

    #[storage]
    struct Storage {
        adventurers: Map<felt252, Adventurer>,
        bags: Map<felt252, Bag>,
        token_settings: Map<felt252, u32>,
        settings_exists: Map<u32, bool>,
    }

    #[abi(embed_v0)]
    impl AdventurerStateSourceImpl of IAdventurerStateSource<ContractState> {
        fn load_assets(self: @ContractState, adventurer_id: felt252) -> (Adventurer, Bag) {
            (self.adventurers.read(adventurer_id), self.bags.read(adventurer_id))
        }
    }

    #[abi(embed_v0)]
    impl TokenSettingsSourceImpl of ITokenSettingsSource<ContractState> {
        fn settings_id(self: @ContractState, token_id: felt252) -> u32 {
            self.token_settings.read(token_id)
        }
    }

    #[abi(embed_v0)]
    impl GameSettingsSourceImpl of IGameSettingsSource<ContractState> {
        fn settings_exist(self: @ContractState, settings_id: u32) -> bool {
            self.settings_exists.read(settings_id)
        }
    }

    #[abi(embed_v0)]
    impl MockGameImpl of IMockGame<ContractState> {
        fn set_assets(
            ref self: ContractState, token_id: felt252, adventurer: Adventurer, bag: Bag,
        ) {
            self.adventurers.write(token_id, adventurer);
            self.bags.write(token_id, bag);
        }

        fn set_token_settings(ref self: ContractState, token_id: felt252, settings_id: u32) {
            self.token_settings.write(token_id, settings_id);
        }

        fn set_settings_exists(ref self: ContractState, settings_id: u32, exists: bool) {
            self.settings_exists.write(settings_id, exists);
        }
    }
}

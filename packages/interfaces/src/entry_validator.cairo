use starknet::ContractAddress;

pub const IENTRY_VALIDATOR_ID: felt252 =
    0x73b204ef90f88bbdf6a178473d1445e76fd9a48a188c6659cb93f988b8458a;

/// Legacy interface ID from when the trait used `budokan_address` instead of `owner_address`.
/// Registered alongside the current ID for backward compatibility with deployed tournament
/// contracts.
pub const LEGACY_IENTRY_VALIDATOR_ID: felt252 =
    0x01158754d5cc62137c4de2cbd0e65cbd163990af29f0182006f26fe0cac00bb6;

#[starknet::interface]
pub trait IEntryValidator<TState> {
    fn owner_address(self: @TState) -> ContractAddress;
    fn registration_only(self: @TState) -> bool;
    fn valid_entry(
        self: @TState,
        tournament_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> bool;
    fn should_ban(
        self: @TState,
        tournament_id: u64,
        game_token_id: u64,
        current_owner: ContractAddress,
        qualification: Span<felt252>,
    ) -> bool;
    fn entries_left(
        self: @TState,
        tournament_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> Option<u8>;
    fn add_config(ref self: TState, tournament_id: u64, entry_limit: u8, config: Span<felt252>);
    fn add_entry(
        ref self: TState,
        tournament_id: u64,
        game_token_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    );
    fn remove_entry(
        ref self: TState,
        tournament_id: u64,
        game_token_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    );
}

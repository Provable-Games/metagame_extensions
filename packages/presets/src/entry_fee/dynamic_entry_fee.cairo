// SPDX-License-Identifier: BUSL-1.1

/// DynamicEntryFee — linear early-bird pricing: the Nth entrant pays
/// `base + N * increment` of `token` (0-indexed N). Demonstrates that an
/// extension can implement state-dependent pricing the built-in fixed-amount
/// path cannot express.
///
/// Player responsibilities
/// -----------------------
/// 1. Approve this contract for at least the next computed fee.
///
/// Host responsibilities
/// ---------------------
/// 1. Set up with config = `[token_address, base_low, base_high, increment_low, increment_high]`.
///    `base` and `increment` are `u256` for token-amount precision.
/// 2. Forward `pay_entry_fee` with pay_params = `[payer]`. The extension
///    reads its own counter, computes the fee, and pulls it from the payer.
/// 3. After finalization, drain the pool with `claim_entry_fee` —
///    claim_params = `[recipient]` transfers the entire accumulated balance.
///    Single-shot only; subsequent calls revert.

#[starknet::interface]
pub trait IDynamicEntryFee<TState> {
    fn get_token(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64,
    ) -> starknet::ContractAddress;

    /// Returns the fee the *next* entrant will pay given the current counter.
    fn next_fee(self: @TState, context_owner: starknet::ContractAddress, context_id: u64) -> u256;

    fn entry_count(self: @TState, context_owner: starknet::ContractAddress, context_id: u64) -> u32;

    fn total_collected(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64,
    ) -> u256;

    fn is_claimed(self: @TState, context_owner: starknet::ContractAddress, context_id: u64) -> bool;
}

#[starknet::contract]
pub mod dynamic_entry_fee {
    use core::num::traits::Zero;
    use metagame_extensions_entry_fee::entry_fee_extension_component::EntryFeeExtensionComponent;
    use metagame_extensions_entry_fee::entry_fee_extension_component::EntryFeeExtensionComponent::EntryFeeExtension;
    use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use super::IDynamicEntryFee;

    component!(path: EntryFeeExtensionComponent, storage: entry_fee, event: EntryFeeEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl EntryFeeExtensionImpl =
        EntryFeeExtensionComponent::EntryFeeExtensionImpl<ContractState>;
    impl EntryFeeExtensionInternalImpl = EntryFeeExtensionComponent::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        entry_fee: EntryFeeExtensionComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        token: Map<(ContractAddress, u64), ContractAddress>,
        base: Map<(ContractAddress, u64), u256>,
        increment: Map<(ContractAddress, u64), u256>,
        entry_count: Map<(ContractAddress, u64), u32>,
        total_collected: Map<(ContractAddress, u64), u256>,
        claimed: Map<(ContractAddress, u64), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        EntryFeeEvent: EntryFeeExtensionComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.entry_fee.initializer();
    }

    fn compute_fee(base: u256, increment: u256, n: u32) -> u256 {
        let n_u256: u256 = n.into();
        base + (increment * n_u256)
    }

    #[abi(embed_v0)]
    impl DynamicEntryFeeViewImpl of IDynamicEntryFee<ContractState> {
        fn get_token(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> ContractAddress {
            self.token.read((context_owner, context_id))
        }

        fn next_fee(self: @ContractState, context_owner: ContractAddress, context_id: u64) -> u256 {
            let n = self.entry_count.read((context_owner, context_id));
            let base = self.base.read((context_owner, context_id));
            let increment = self.increment.read((context_owner, context_id));
            compute_fee(base, increment, n)
        }

        fn entry_count(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u32 {
            self.entry_count.read((context_owner, context_id))
        }

        fn total_collected(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u256 {
            self.total_collected.read((context_owner, context_id))
        }

        fn is_claimed(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> bool {
            self.claimed.read((context_owner, context_id))
        }
    }

    impl DynamicEntryFeeExtensionImpl of EntryFeeExtension<ContractState> {
        fn set_entry_fee_config(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            config: Span<felt252>,
        ) {
            assert!(
                config.len() == 5,
                "DynamicEntryFee: config must be [token, base_low, base_high, inc_low, inc_high]",
            );
            let token: ContractAddress = (*config.at(0)).try_into().unwrap();
            let base_low: u128 = (*config.at(1)).try_into().unwrap();
            let base_high: u128 = (*config.at(2)).try_into().unwrap();
            let inc_low: u128 = (*config.at(3)).try_into().unwrap();
            let inc_high: u128 = (*config.at(4)).try_into().unwrap();
            self.token.write((context_owner, context_id), token);
            self.base.write((context_owner, context_id), u256 { low: base_low, high: base_high });
            self
                .increment
                .write((context_owner, context_id), u256 { low: inc_low, high: inc_high });
        }

        fn pay_entry_fee(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            pay_params: Span<felt252>,
        ) {
            assert!(pay_params.len() == 1, "DynamicEntryFee: pay_params must be [payer]");
            let payer: ContractAddress = (*pay_params.at(0)).try_into().unwrap();

            let key = (context_owner, context_id);
            let n = self.entry_count.read(key);
            let base = self.base.read(key);
            let increment = self.increment.read(key);
            let fee = compute_fee(base, increment, n);

            let token = self.token.read(key);
            let erc20 = IERC20Dispatcher { contract_address: token };
            assert!(
                erc20.transfer_from(payer, get_contract_address(), fee),
                "DynamicEntryFee: transfer_from failed",
            );

            self.entry_count.write(key, n + 1);
            let prev_total = self.total_collected.read(key);
            self.total_collected.write(key, prev_total + fee);
        }

        /// Re-serialize the stored config back to the
        /// `[token, base_low, base_high, inc_low, inc_high]` shape
        /// passed to set_entry_fee_config. Returns an empty span when
        /// the context tuple is unknown (token unset).
        fn get_config(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> Span<felt252> {
            let key = (context_owner, context_id);
            let token = self.token.read(key);
            if token.is_zero() {
                return array![].span();
            }
            let base = self.base.read(key);
            let increment = self.increment.read(key);
            array![
                token.into(), base.low.into(), base.high.into(), increment.low.into(),
                increment.high.into(),
            ]
                .span()
        }

        /// DynamicEntryFee distributes the entire pool as a single payout
        /// to the host-supplied recipient. Position is unused (the pool
        /// isn't sliced by leaderboard); claim_params is empty.
        fn payout_entry_fee(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            recipient: ContractAddress,
            position: Option<u32>,
            claim_params: Span<felt252>,
        ) {
            let _ = (position, claim_params);

            let key = (context_owner, context_id);
            assert!(!self.claimed.read(key), "DynamicEntryFee: already claimed");
            self.claimed.write(key, true);

            let total = self.total_collected.read(key);
            if total > 0 {
                let token = self.token.read(key);
                let erc20 = IERC20Dispatcher { contract_address: token };
                assert!(erc20.transfer(recipient, total), "DynamicEntryFee: transfer failed");
            }
        }
    }
}

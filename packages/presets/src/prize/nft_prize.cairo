// SPDX-License-Identifier: BUSL-1.1

/// NFTPrize — sponsor escrows a set of ERC721 token IDs assigned to specific
/// leaderboard positions of a prize. The extension is fully sovereign: the
/// host dispatches with a `token_id` (or `None` for sponsor refunds) and
/// NFTPrize resolves the position and recipient from its own state +
/// the host's `ILeaderboard`.
///
/// This is the leaderboard-aware counterpart to the built-in single-ERC721
/// prize path: the built-in flow can hold at most one NFT per prize, while
/// this preset distributes N NFTs across N positions in one prize.
///
/// Sponsor responsibilities
/// ------------------------
/// 1. Transfer each of the assigned NFTs to this contract's address *before*
///    submitting the prize. The extension does NOT escrow on `add_prize`
///    because it cannot see the original sponsor — in the cross-contract
///    extension-dispatch model, `get_caller_address()` resolves to the host
///    contract, not the EOA that initiated the transaction. The contract
///    verifies ownership of each declared token ID at registration time
///    (sanity check) and rejects underfunded prizes.
/// 2. Submit the prize with config = `[token_address, sponsor_address,
///    num_positions, token_id_0_low, token_id_0_high, ...]`. `sponsor_address`
///    is the refund recipient for positions with no qualifying winner.
///    `num_positions` MUST equal the number of (low, high) pairs following.
///
/// Config layout (`add_prize`):
///   [token_address, sponsor_address, num_positions, id_0_low, id_0_high, id_1_low, id_1_high, ...]
///
/// Payout shapes (`payout_prize`)
/// ------------------------------
/// - Claim: `token_id = Some(game_token)`, `payout_params = []`.
///   NFTPrize queries `ILeaderboard::get_position(context_id, token_id)` to
///   find the position, derives the recipient as the current owner of the
///   game token, and transfers `prize_position_token_id[position]`.
/// - Refund: `token_id = None`, `payout_params = [slot_index]`.
///   NFTPrize verifies `slot_index > leaderboard_length` (no qualifying
///   winner for that slot), and transfers `prize_position_token_id[slot_index]`
///   to the recorded sponsor.

#[starknet::interface]
pub trait INFTPrize<TState> {
    fn get_token_address(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64, prize_id: u64,
    ) -> starknet::ContractAddress;

    fn get_sponsor(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64, prize_id: u64,
    ) -> starknet::ContractAddress;

    fn get_position_token_id(
        self: @TState,
        context_owner: starknet::ContractAddress,
        context_id: u64,
        prize_id: u64,
        position: u32,
    ) -> u256;

    fn is_position_claimed(
        self: @TState,
        context_owner: starknet::ContractAddress,
        context_id: u64,
        prize_id: u64,
        position: u32,
    ) -> bool;
}

#[starknet::contract]
pub mod nft_prize {
    use metagame_extensions_presets::externals::game_components::{
        ILeaderboardDispatcher, ILeaderboardDispatcherTrait, IMinigameDispatcher,
        IMinigameDispatcherTrait,
    };
    use metagame_extensions_prize::prize_extension_component::PrizeExtensionComponent;
    use metagame_extensions_prize::prize_extension_component::PrizeExtensionComponent::PrizeExtension;
    use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use super::INFTPrize;

    component!(path: PrizeExtensionComponent, storage: prize, event: PrizeEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl PrizeExtensionImpl =
        PrizeExtensionComponent::PrizeExtensionImpl<ContractState>;
    impl PrizeExtensionInternalImpl = PrizeExtensionComponent::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        prize: PrizeExtensionComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        prize_token_address: Map<(ContractAddress, u64, u64), ContractAddress>,
        /// Refund target for positions with no qualifying leaderboard entry.
        prize_sponsor: Map<(ContractAddress, u64, u64), ContractAddress>,
        prize_num_positions: Map<(ContractAddress, u64, u64), u32>,
        /// (context_owner, context_id, prize_id, 1-indexed position) -> token id
        prize_position_token_id: Map<(ContractAddress, u64, u64, u32), u256>,
        prize_position_claimed: Map<(ContractAddress, u64, u64, u32), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        PrizeEvent: PrizeExtensionComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.prize.initializer();
    }

    #[abi(embed_v0)]
    impl NFTPrizeViewImpl of INFTPrize<ContractState> {
        fn get_token_address(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, prize_id: u64,
        ) -> ContractAddress {
            self.prize_token_address.read((context_owner, context_id, prize_id))
        }

        fn get_sponsor(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, prize_id: u64,
        ) -> ContractAddress {
            self.prize_sponsor.read((context_owner, context_id, prize_id))
        }

        fn get_position_token_id(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            position: u32,
        ) -> u256 {
            self.prize_position_token_id.read((context_owner, context_id, prize_id, position))
        }

        fn is_position_claimed(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            position: u32,
        ) -> bool {
            self.prize_position_claimed.read((context_owner, context_id, prize_id, position))
        }
    }

    impl NFTPrizeExtensionImpl of PrizeExtension<ContractState> {
        fn add_prize(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            config: Span<felt252>,
        ) {
            // Minimum: [token, sponsor, num_positions] (3) + at least 1 NFT (2)
            assert!(
                config.len() >= 5,
                "NFTPrize: config must be [token, sponsor, num_positions, ...id_low_high pairs]",
            );
            let token: ContractAddress = (*config.at(0)).try_into().unwrap();
            let sponsor: ContractAddress = (*config.at(1)).try_into().unwrap();
            let num_positions: u32 = (*config.at(2)).try_into().unwrap();
            assert!(num_positions > 0, "NFTPrize: num_positions must be > 0");
            assert!(
                config.len() == 3 + (num_positions * 2),
                "NFTPrize: config length must equal 3 + num_positions * 2",
            );

            let key = (context_owner, context_id, prize_id);
            assert!(self.prize_num_positions.read(key) == 0, "NFTPrize: prize already configured");
            self.prize_token_address.write(key, token);
            self.prize_sponsor.write(key, sponsor);
            self.prize_num_positions.write(key, num_positions);

            let erc721 = IERC721Dispatcher { contract_address: token };
            let self_address = get_contract_address();
            let mut i: u32 = 0;
            while i < num_positions {
                let pair_base: u32 = 3 + (i * 2);
                let id_low: u128 = (*config.at(pair_base)).try_into().unwrap();
                let id_high: u128 = (*config.at(pair_base + 1)).try_into().unwrap();
                let token_id = u256 { low: id_low, high: id_high };
                let position = i + 1;
                self
                    .prize_position_token_id
                    .write((context_owner, context_id, prize_id, position), token_id);
                // Sanity: sponsor must have already transferred the NFT.
                assert!(
                    erc721.owner_of(token_id) == self_address,
                    "NFTPrize: token must be pre-transferred to extension",
                );
                i += 1;
            }
        }

        fn get_config(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, prize_id: u64,
        ) -> Span<felt252> {
            // Re-serialize the stored fields back to the original
            // `[token_address, sponsor_address, num_positions, id_0_lo,
            //   id_0_hi, ...]` shape passed to add_prize. Returns an empty
            // span for unknown prizes (num_positions == 0 — add_prize
            // asserts > 0 so unambiguous).
            let key = (context_owner, context_id, prize_id);
            let num_positions = self.prize_num_positions.read(key);
            if num_positions == 0 {
                return array![].span();
            }
            let token = self.prize_token_address.read(key);
            let sponsor = self.prize_sponsor.read(key);
            let mut out: Array<felt252> = array![];
            out.append(token.into());
            out.append(sponsor.into());
            out.append(num_positions.into());
            let mut i: u32 = 1;
            while i <= num_positions {
                let token_id = self
                    .prize_position_token_id
                    .read((context_owner, context_id, prize_id, i));
                out.append(token_id.low.into());
                out.append(token_id.high.into());
                i += 1;
            }
            out.span()
        }

        /// Dispatch a payout for this prize.
        ///
        /// Claim path (`token_id = Some(game_token)`):
        /// - Look up the token's leaderboard position via
        ///   `ILeaderboard::get_position`. Reverts if the token is not on
        ///   the leaderboard for `context_id` or its position exceeds
        ///   `num_positions` for this prize.
        /// - Derive recipient as `owner_of(game_token)` on the host's
        ///   game-token contract (resolved via `IMinigame::token_address`).
        /// - Transfer `prize_position_token_id[position]` to the recipient.
        ///
        /// Refund path (`token_id = None`, `payout_params = [slot_index]`):
        /// - `slot_index` must be 1-indexed and within
        ///   `1..=num_positions`. Reverts if `slot_index <= leaderboard_length`
        ///   (a qualifying winner exists for that slot — claim path applies
        ///   instead).
        /// - Transfer `prize_position_token_id[slot_index]` to the recorded
        ///   sponsor.
        fn payout_prize(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            token_id: Option<felt252>,
            payout_params: Span<felt252>,
        ) {
            let key = (context_owner, context_id, prize_id);
            let num_positions = self.prize_num_positions.read(key);
            assert!(num_positions > 0, "NFTPrize: prize not configured");

            let leaderboard = ILeaderboardDispatcher { contract_address: context_owner };

            // Resolve (position, recipient) from the dispatch shape.
            let (position, recipient): (u32, ContractAddress) = match token_id {
                Option::Some(claimant_token) => {
                    // Claim path. Token must hold a leaderboard position
                    // within the prize's distribution range.
                    let position = match leaderboard.get_position(context_id, claimant_token) {
                        Option::Some(p) => p,
                        Option::None => panic!("NFTPrize: token not on leaderboard"),
                    };
                    assert!(position <= num_positions, "NFTPrize: position out of prize range");

                    // Recipient = current owner of the game token. Resolve
                    // the game token contract via the host.
                    let game_token_address = IMinigameDispatcher { contract_address: context_owner }
                        .token_address();
                    let game_token = IERC721Dispatcher { contract_address: game_token_address };
                    let claimant_token_u256: u256 = claimant_token.into();
                    let owner = game_token.owner_of(claimant_token_u256);
                    (position, owner)
                },
                Option::None => {
                    // Refund path. `payout_params[0]` selects the slot.
                    assert!(
                        payout_params.len() == 1,
                        "NFTPrize: refund requires payout_params = [slot_index]",
                    );
                    let slot_index: u32 = (*payout_params.at(0)).try_into().unwrap();
                    assert!(slot_index > 0, "NFTPrize: slot_index must be 1-indexed");
                    assert!(slot_index <= num_positions, "NFTPrize: slot_index out of prize range");

                    // Refund is only valid when no qualifying winner exists
                    // at this slot — claim path applies otherwise.
                    let length = leaderboard.get_leaderboard_length(context_id);
                    assert!(
                        slot_index > length,
                        "NFTPrize: slot has a qualifying winner; use the claim path",
                    );

                    (slot_index, self.prize_sponsor.read(key))
                },
            };

            // Dedupe on the (prize, position) tuple — same slot can't be
            // paid out twice via either path.
            let claim_key = (context_owner, context_id, prize_id, position);
            assert!(
                !self.prize_position_claimed.read(claim_key), "NFTPrize: position already claimed",
            );
            self.prize_position_claimed.write(claim_key, true);

            let prize_token = self.prize_token_address.read(key);
            let prize_token_id = self.prize_position_token_id.read(claim_key);
            let erc721 = IERC721Dispatcher { contract_address: prize_token };
            erc721.transfer_from(get_contract_address(), recipient, prize_token_id);
        }
    }
}

//! Pure objective-evaluation logic. No storage, no syscalls — trivially unit/fuzz
//! testable and portable. The oracle contract layer only fetches state and delegates
//! the actual decision to `evaluate`.

use core::num::traits::Sqrt;
use crate::interface::{Comparator, Metric, ObjectiveConfig};
use crate::types::{Adventurer, Bag, Equipment, Item};

/// Max item greatness, mirrors `death_mountain` `ITEM_MAX_GREATNESS`.
pub const ITEM_MAX_GREATNESS: u8 = 20;

/// Adventurer level from xp: `sqrt(xp)`, with a floor of 1 (matches
/// `death_mountain` `ImplCombat::get_level_from_xp`).
pub fn level_from_xp(xp: u16) -> u64 {
    if xp == 0 {
        1
    } else {
        let lvl: u8 = xp.sqrt();
        lvl.into()
    }
}

/// Item greatness from item xp: `min(sqrt(xp), 20)`, floor of 1 for xp > 0, else 0.
/// (Matches `death_mountain` `ImplItem::get_greatness`, except an empty item — xp 0 —
/// is treated as greatness 0 here so an absent item never satisfies a threshold.)
pub fn item_greatness(xp: u16) -> u8 {
    if xp == 0 {
        0
    } else {
        let lvl: u8 = xp.sqrt();
        if lvl > ITEM_MAX_GREATNESS {
            ITEM_MAX_GREATNESS
        } else {
            lvl
        }
    }
}

/// True if `item_id` occupies any of the 8 equipment slots.
pub fn is_equipped(equipment: Equipment, item_id: u8) -> bool {
    equipment.weapon.id == item_id
        || equipment.chest.id == item_id
        || equipment.head.id == item_id
        || equipment.waist.id == item_id
        || equipment.foot.id == item_id
        || equipment.hand.id == item_id
        || equipment.neck.id == item_id
        || equipment.ring.id == item_id
}

/// True if `item_id` occupies any of the 15 bag slots.
pub fn is_in_bag(bag: Bag, item_id: u8) -> bool {
    bag.item_1.id == item_id
        || bag.item_2.id == item_id
        || bag.item_3.id == item_id
        || bag.item_4.id == item_id
        || bag.item_5.id == item_id
        || bag.item_6.id == item_id
        || bag.item_7.id == item_id
        || bag.item_8.id == item_id
        || bag.item_9.id == item_id
        || bag.item_10.id == item_id
        || bag.item_11.id == item_id
        || bag.item_12.id == item_id
        || bag.item_13.id == item_id
        || bag.item_14.id == item_id
        || bag.item_15.id == item_id
}

/// Highest greatness of any equipped-or-bagged copy of `item_id` (0 if absent).
pub fn max_item_greatness(adventurer: Adventurer, bag: Bag, item_id: u8) -> u8 {
    let mut best: u8 = 0;
    let e = adventurer.equipment;
    let candidates: Array<Item> = array![
        e.weapon, e.chest, e.head, e.waist, e.foot, e.hand, e.neck, e.ring, bag.item_1, bag.item_2,
        bag.item_3, bag.item_4, bag.item_5, bag.item_6, bag.item_7, bag.item_8, bag.item_9,
        bag.item_10, bag.item_11, bag.item_12, bag.item_13, bag.item_14, bag.item_15,
    ];
    for item in candidates {
        if item.id == item_id && item.id != 0 {
            let g = item_greatness(item.xp);
            if g > best {
                best = g;
            }
        }
    }
    best
}

/// Extract a scalar attribute. Panics on item-typed metrics (callers must route item
/// metrics through `evaluate`, which never calls this for them).
pub fn scalar_value(adventurer: Adventurer, metric: Metric) -> u64 {
    match metric {
        Metric::Xp => adventurer.xp.into(),
        Metric::Level => level_from_xp(adventurer.xp),
        Metric::Gold => adventurer.gold.into(),
        Metric::Health => adventurer.health.into(),
        Metric::BeastHealth => adventurer.beast_health.into(),
        Metric::StatUpgradesAvailable => adventurer.stat_upgrades_available.into(),
        Metric::Strength => adventurer.stats.strength.into(),
        Metric::Dexterity => adventurer.stats.dexterity.into(),
        Metric::Vitality => adventurer.stats.vitality.into(),
        Metric::Intelligence => adventurer.stats.intelligence.into(),
        Metric::Wisdom => adventurer.stats.wisdom.into(),
        Metric::Charisma => adventurer.stats.charisma.into(),
        Metric::Luck => adventurer.stats.luck.into(),
        // Item metrics are not scalars.
        Metric::ItemHeldAnywhere => core::panic_with_felt252('metric is not scalar'),
        Metric::ItemEquipped => core::panic_with_felt252('metric is not scalar'),
        Metric::ItemInBag => core::panic_with_felt252('metric is not scalar'),
        Metric::ItemGreatness => core::panic_with_felt252('metric is not scalar'),
        Metric::ItemSetHeldAnywhere => core::panic_with_felt252('metric is not scalar'),
        Metric::ItemSetEquipped => core::panic_with_felt252('metric is not scalar'),
        Metric::ItemSetInBag => core::panic_with_felt252('metric is not scalar'),
    }
}

/// True for the `ItemSet*` metrics, which carry a stored item id list and are evaluated
/// via `evaluate_item_set` (not `evaluate`).
pub fn is_item_set_metric(metric: Metric) -> bool {
    match metric {
        Metric::ItemSetHeldAnywhere => true,
        Metric::ItemSetEquipped => true,
        Metric::ItemSetInBag => true,
        _ => false,
    }
}

/// Whether a single item id is held per an item-set metric's base predicate. A zero id
/// is never considered held (empty slots share id 0). Returns false for non-set metrics.
pub fn set_item_held(adventurer: Adventurer, bag: Bag, item_id: u8, metric: Metric) -> bool {
    if item_id == 0 {
        return false;
    }
    match metric {
        Metric::ItemSetHeldAnywhere => is_equipped(adventurer.equipment, item_id)
            || is_in_bag(bag, item_id),
        Metric::ItemSetEquipped => is_equipped(adventurer.equipment, item_id),
        Metric::ItemSetInBag => is_in_bag(bag, item_id),
        _ => false,
    }
}

/// Number of items from `items` the adventurer holds under the set metric's predicate.
/// Duplicate ids in `items` are counted once each (the caller controls the list).
pub fn count_items_held(adventurer: Adventurer, bag: Bag, items: Span<u8>, metric: Metric) -> u64 {
    let mut count: u64 = 0;
    for item_id in items {
        if set_item_held(adventurer, bag, *item_id, metric) {
            count += 1;
        }
    }
    count
}

/// Evaluate an item-set objective: compare the count of held set items against the
/// configured `target` via `comparator`.
pub fn evaluate_item_set(
    adventurer: Adventurer, bag: Bag, items: Span<u8>, config: ObjectiveConfig,
) -> bool {
    let held = count_items_held(adventurer, bag, items, config.metric);
    compare(held, config.comparator, config.target)
}

/// Apply a comparator between an extracted value and the target.
pub fn compare(value: u64, comparator: Comparator, target: u64) -> bool {
    match comparator {
        Comparator::AtLeast => value >= target,
        Comparator::AtMost => value <= target,
        Comparator::Equal => value == target,
        Comparator::GreaterThan => value > target,
        Comparator::LessThan => value < target,
        Comparator::NotEqual => value != target,
    }
}

/// Evaluate an objective against a fully-loaded adventurer + bag.
pub fn evaluate(adventurer: Adventurer, bag: Bag, config: ObjectiveConfig) -> bool {
    match config.metric {
        // Boolean "holds item X" checks: target encodes the item id. A target that
        // does not fit in a u8 can never match an item id, so it is unsatisfiable.
        Metric::ItemHeldAnywhere => {
            let item_id: u8 = match config.target.try_into() {
                Option::Some(v) => v,
                Option::None => { return false; },
            };
            is_equipped(adventurer.equipment, item_id) || is_in_bag(bag, item_id)
        },
        Metric::ItemEquipped => {
            let item_id: u8 = match config.target.try_into() {
                Option::Some(v) => v,
                Option::None => { return false; },
            };
            is_equipped(adventurer.equipment, item_id)
        },
        Metric::ItemInBag => {
            let item_id: u8 = match config.target.try_into() {
                Option::Some(v) => v,
                Option::None => { return false; },
            };
            is_in_bag(bag, item_id)
        },
        Metric::ItemGreatness => {
            let item_id: u8 = match config.target.try_into() {
                Option::Some(v) => v,
                Option::None => { return false; },
            };
            let greatness: u64 = max_item_greatness(adventurer, bag, item_id).into();
            compare(greatness, config.comparator, config.aux)
        },
        // Item-set metrics need the stored item id list, which `evaluate` does not have;
        // the contract layer must route them through `evaluate_item_set`.
        Metric::ItemSetHeldAnywhere => core::panic_with_felt252('metric needs item set'),
        Metric::ItemSetEquipped => core::panic_with_felt252('metric needs item set'),
        Metric::ItemSetInBag => core::panic_with_felt252('metric needs item set'),
        // Everything else is a scalar comparison.
        _ => {
            let value = scalar_value(adventurer, config.metric);
            compare(value, config.comparator, config.target)
        },
    }
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Wad {
    pub val: u128,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Ray {
    pub val: u128,
}

pub impl WadInto of Into<u128, Wad> {
    fn into(self: u128) -> Wad {
        Wad { val: self }
    }
}

pub impl WadZero of core::num::traits::Zero<Wad> {
    fn zero() -> Wad {
        Wad { val: 0 }
    }
    fn is_zero(self: @Wad) -> bool {
        *self.val == 0
    }
    fn is_non_zero(self: @Wad) -> bool {
        *self.val != 0
    }
}

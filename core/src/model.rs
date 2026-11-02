#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Position {
    Unknown,
    Window,
    Aisle,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Seat {
    pub number: u16,
    pub free: bool,
    pub position: Position,
    pub special: bool,
    pub xy: Option<(i32, i32)>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Decor {
    pub kind: String,
    pub code: String,
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
    pub title: String,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Layout {
    pub width: i32,
    pub height: i32,
    pub decor: Vec<Decor>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WagonSeats {
    pub class: u8,
    pub wagon: i32,
    pub seats: Vec<Seat>,
    pub layout: Layout,
}

impl WagonSeats {
    pub fn free_count(&self) -> usize {
        self.seats.iter().filter(|s| s.free).count()
    }
    pub fn occupied_count(&self) -> usize {
        self.seats.iter().filter(|s| !s.free).count()
    }
    pub fn free_numbers(&self) -> Vec<u16> {
        self.seats
            .iter()
            .filter(|s| s.free)
            .map(|s| s.number)
            .collect()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Train {
    pub connection_id: i64,
    pub number: i64,
    pub category: String,
    pub name: String,
    pub dep: String,
    pub arr: String,
    pub from_kod: u32,
    pub to_kod: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Stop {
    pub name: String,
    pub eva: u32,
    pub arr: String,
    pub dep: String,
    pub can_board: bool,
    pub can_alight: bool,
    pub platform: String,
    pub track: String,
    pub arr_actual: String,
    pub dep_actual: String,
    pub messages: String,
}

pub const DISCOUNT_NORMAL: i32 = 1010;
pub const DISCOUNT_37: i32 = 1710;
pub const DISCOUNT_51: i32 = 1990;

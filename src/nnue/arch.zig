const base = @import("base");
const builtin = @import("builtin");

pub const Int = i16;

pub const color_n = base.types.Color.cnt;
pub const ptype_n = base.types.Ptype.cnt - 2;
pub const square_n = base.types.Square.cnt;

pub const inp_len = color_n * ptype_n * square_n;
pub const hl0_len = if (builtin.is_test) 64 else 32;
pub const out_len = 1;

pub const scale = 400;
pub const qa = 255;
pub const qb = 64;

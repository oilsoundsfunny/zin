const builtin = @import("builtin");
const types = @import("types");

pub const Int = i16;

pub const color_n = types.Color.cnt;
pub const ptype_n = types.Ptype.cnt;
pub const square_n = types.Square.cnt;

pub const inp_len = color_n * ptype_n * square_n;
pub const hl0_len = if (builtin.is_test) 64 else 256;
pub const out_len = 1;

pub const scale = 400;
pub const qa = 255;
pub const qb = 64;

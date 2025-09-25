const base = @import("base");
const std = @import("std");

pub const Int = i16;

pub const HL0Vec = @Vector(hl0_len, i16);
pub const OutVec = @Vector(out_len, i16);

pub const color_n = base.types.Color.cnt;
pub const ptype_n = base.types.Ptype.cnt - 2;
pub const square_n = base.types.Square.cnt;

pub const inp_len = color_n * ptype_n * square_n;
pub const hl0_len = 32;
pub const out_len = 1;

pub const scale = 400;
pub const qa = 255;
pub const qb = 64;

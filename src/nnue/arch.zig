const builtin = @import("builtin");
const std = @import("std");
const types = @import("types");

pub const Int = i16;
pub const Native = @Vector(native_len, Int);

pub const color_n = types.Color.cnt;
pub const ptype_n = types.Ptype.cnt;
pub const square_n = types.Square.cnt;

pub const inp_len = color_n * ptype_n * square_n;
pub const hl0_len = 320;
pub const out_len = 1;
pub const native_len = std.simd.suggestVectorLength(Int) orelse @compileError("unsupported cpu");

pub const scale = 400;
pub const qa = 255;
pub const qb = 64;

const builtin = @import("builtin");
const std = @import("std");

const has_bmi2 = builtin.cpu.has(.x86, .bmi2) and
    builtin.cpu.model != &std.Target.x86.cpu.znver1 and
    builtin.cpu.model != &std.Target.x86.cpu.znver2;
const impl = if (has_bmi2) @import("bmi2.zig") else @import("magic.zig");

pub const init = impl.init;
pub const bAtk = impl.bAtk;
pub const rAtk = impl.rAtk;

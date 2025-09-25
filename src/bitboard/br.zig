const builtin = @import("builtin");
const std = @import("std");

// Zen and Zen 2 has really shitty PDEP/PEXT perf
const has_bmi2 = std.Target.x86.featureSetHas(builtin.cpu.features, std.Target.x86.Feature.bmi2)
  and builtin.cpu.model != &std.Target.x86.cpu.znver1
  and builtin.cpu.model != &std.Target.x86.cpu.znver2;
const impl = if (has_bmi2) @import("bmi2.zig") else @import("magic.zig");

pub const prefetch = impl.prefetch;
pub const bAtkInit = impl.bAtkInit;
pub const rAtkInit = impl.rAtkInit;

pub const bAtk = impl.bAtk;
pub const rAtk = impl.rAtk;

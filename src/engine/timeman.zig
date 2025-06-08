const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const Thread = @import("Thread.zig");
const movegen = @import("movegen.zig");

pub var increment = std.EnumArray(misc.types.Color, usize);
pub var time = std.EnumArray(misc.types.Color, usize);

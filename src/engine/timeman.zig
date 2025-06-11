const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const Thread = @import("Thread.zig");
const movegen = @import("movegen.zig");

pub var depth: u8 = std.math.maxInt(u8);
pub var movetime: u64 = std.math.maxInt(u64);

pub var increment = std.EnumArray(misc.types.Color, u64).init(.{
  .white = std.math.maxInt(u64),
  .black = std.math.maxInt(u64),
});

pub var time = std.EnumArray(misc.types.Color, u64).init(.{
  .white = std.math.maxInt(u64),
  .black = std.math.maxInt(u64),
});

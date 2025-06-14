const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const Thread = @import("Thread.zig");
const movegen = @import("movegen.zig");

pub var depth: ?u8 = null;
pub var movetime: ?u64 = null;
pub var increment = std.EnumArray(misc.types.Color, ?u64).init(.{
  .white = null,
  .black = null,
});
pub var time = std.EnumArray(misc.types.Color, ?u64).init(.{
  .white = null,
  .black = null,
});

pub var start: ?u64 = null;
pub var stop: ?u64 = null;

pub fn hardStop() bool {
	const ms = misc.time.read(.ms);
	return stop != null and ms >= stop.?;
}

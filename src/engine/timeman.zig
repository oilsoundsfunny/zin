const misc = @import("misc");
const std = @import("std");

pub var depth: ?u8 = null;
pub var increment: ?u64 = null;
pub var movetime: ?u64 = null;
pub var overhead: ?u64 = null;
pub var time: ?u64 = null;

pub var start: ?u64 = null;
pub var stop: ?u64 = null;
pub var current: u64 = 0;

pub fn loop() void {
	const read = misc.time.read(.ms);
	@atomicStore(u64, &current, read, .monotonic);
}

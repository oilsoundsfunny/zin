const misc = @import("misc");
const std = @import("std");

pub var is_running: bool = true;
pub var is_searching: bool = false;

pub var depth: ?u8 = null;
pub var increment = std.EnumArray(misc.types.Color, ?u64).init(.{
	.white = null,
	.black = null,
});
pub var movetime: ?u64 = null;
pub var overhead: ?u64 = null;
pub var time = std.EnumArray(misc.types.Color, ?u64).init(.{
	.white = null,
	.black = null,
});

pub var start: u64 = 0;
pub var stop: ?u64 = null;

pub fn hardStop() bool {
	if (!is_searching) {
		return true;
	}

	const stop_time = stop orelse return false;
	const current_time = misc.time.read(.ms);
	return current_time >= stop_time;
}

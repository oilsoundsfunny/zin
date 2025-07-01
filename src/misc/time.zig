const std = @import("std");

var timer: std.time.Timer = undefined;

pub const Units = enum {
	ns,
	us,
	ms,
};

pub fn init() !void {
	timer = try std.time.Timer.start();
}

pub fn read(comptime unit: Units) u64 {
	const from_timer = timer.read();
	return switch (unit) {
		.ns => from_timer,
		.us => from_timer / std.time.ns_per_us,
		.ms => from_timer / std.time.ns_per_ms,
	};
}

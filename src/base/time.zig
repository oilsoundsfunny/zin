const std = @import("std");

var timer: std.time.Timer = undefined;

pub fn init() !void {
	timer = try std.time.Timer.start();
}

pub fn read(comptime scale: @Type(.enum_literal)) u64 {
	const from_timer = timer.read();
	return switch (scale) {
		.ns => from_timer,
		.us => from_timer / std.time.ns_per_us,
		.ms => from_timer / std.time.ns_per_ms,
		else => |t| @compileError("unexpected tag " ++ @tagName(t)),
	};
}

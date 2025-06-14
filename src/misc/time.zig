const std = @import("std");

var timer: std.time.Timer = undefined;

pub fn init() !void {
	timer = try std.time.Timer.start();
}

pub fn read(comptime lv: @TypeOf(.enum_literal)) u64 {
	return switch (lv) {
		.ns => timer.read(),
		.us => timer.read() / std.time.ns_per_us,
		.ms => timer.read() / std.time.ns_per_ms,
		else => @compileError("unexpected tag " ++ @tagName(lv)),
	};
}

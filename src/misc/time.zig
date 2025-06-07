const std = @import("std");

var timer: std.time.Timer = undefined;

pub fn init() !void {
	timer = try std.time.Timer.start();
}

pub fn read() u64 {
	return timer.read();
}

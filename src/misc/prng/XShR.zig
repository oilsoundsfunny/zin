const std = @import("std");

const Self = @This();

x:	u64,
y:	u64,

pub fn fill(self: *Self, buf: []u8) void {
	var i: usize = 0;
	while (i < buf.len - buf.len % @sizeOf(u64)) : (i += @sizeOf(u64)) {
		std.mem.bytesAsValue(u64, buf[i ..]).* = self.next();
	}

	if (i < buf.len) {
		const n = self.next();
		for (buf[i ..], std.mem.asBytes(&n)) |*p, b| {
			p.* = b;
		}
	}
}

pub fn init(seed: u64) void {
	var s = std.Random.SplitMix64.init(seed);
	var r = std.mem.zeroes(Self);

	r.x = s.next();
	r.y = s.next();
	return r;
}

pub fn next(self: *Self) u64 {
	var s = self.*;
	s.x ^= s.x << 23;
	s.x ^= s.x >> 17;
	s.x ^= s.y;
	self.* = .{
		.x = s.y,
		.y = s.y +% s.x,
	};
	return s.x;
}

pub fn random(self: *Self) std.Random {
	return std.Random.init(self, fill);
}

const std = @import("std");

const SplitMix32 = @This();

x:	u32,

pub fn fill(self: *SplitMix32, buf: []u8) void {
	var i: usize = 0;
	while (i + @sizeOf(u32) < buf.len) : (i += @sizeOf(u32)) {
		std.mem.bytesAsValue(u32, buf[i ..]).* = self.next();
	}

	if (i < buf.len) {
		const n = self.next();
		for (buf[i ..], std.mem.asBytes(&n)) |*p, b| {
			p.* = b;
		}
	}
}

pub fn init(seed: u32) SplitMix32 {
	return .{
		.x = seed,
	};
}

pub fn next(self: *SplitMix32) u32 {
	self.x +%= 0x9e3779b9;
	var x = self.x;
	x  ^= x >> 16;
	x *%= 0x21f0aaad;
	x  ^= x >> 15;
	x *%= 0x735a2d97;
	x  ^= x >> 15;
	return x;
}

pub fn random(self: *SplitMix32) std.Random {
	return std.Random.init(self, fill);
}

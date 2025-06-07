const std = @import("std");

const Self = @This();

state:	u64,

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
	return .{
		.state = seed,
	};
}

pub fn next(self: *Self) u64 {
	if (self.state == 0) {
		@branchHint(.unlikely);
		self.state -%= 1;
	}
	self.state ^= self.state << 7;
	self.state ^= self.state >> 9;
	return self.state;
}

pub fn random(self: *Self) std.Random {
	return std.Random.init(self, fill);
}

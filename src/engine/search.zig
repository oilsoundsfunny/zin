const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");

pub const Depth = u8;

pub const Info = struct {
	pos:	Position,

	depth:	Depth,
	nodes:	u64,
};

pub const manager = struct {
	fn func() !void {
	}

	pub fn spawn() !void {
	}
};

const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");

pub const Depth = u8;

pub const Info = struct {
	pos:	Position,

	depth:	Depth,
	nodes:	u64,
};

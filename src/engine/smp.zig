const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");

pub var pool: std.Thread.Pool = undefined;
pub var wait_group: std.Thread.WaitGroup = undefined;

pub const Info = struct {
	pos:	Position,
	depth:	u8,

	bfhist:	HistArray(Hist, 1),
	capthist:	HistArray(Hist, 2),
	conthist:	HistArray(Hist, 2),

	idx:	usize,
	cnt:	usize,

	max_depth:	?u8,
	increment:	?u64,
	movetime:	?u64,
	time:		?u64,

	starttime:	?u64 = null,
	stoptime:	?u64 = null,

	pub const Hist = i16;

	pub fn HistArray(comptime T: type, comptime n: comptime_int) type {
		return switch (n) {
			1 => std.EnumArray(misc.types.Piece, std.EnumArray(misc.types.Square, T)),
			2 => HistArray(HistArray(T, 1), 1),
			else => @compileError("unexpected integer " ++ std.fmt.comptimePrint("{d}", .{n})),
		};
	}
};

pub fn deinit() void {
	pool.deinit();
}

pub fn init(options: std.Thread.Pool.Options) !void {
	try pool.init(options);
}

const base = @import("base");
const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");

pub fn main() !void {
	try base.init();
	defer base.deinit();

	try engine.init();
	defer engine.deinit();

	const args = try std.process.argsAlloc(base.heap.allocator);
	var i: usize = 1;

	while (i < args.len) : (i += 1) {
		const arg = args[i];

		if (std.mem.eql(u8, arg, "--book")) {
		} else if (std.mem.eql(u8, arg, "--nodes")) {
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}
}

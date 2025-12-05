const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const bench = @import("bench.zig");

pub const author = "oilsoundsfunny";
pub const name = "zin";
pub const version = std.SemanticVersion {
	.major = 0,
	.minor = 1,
	.patch = 0,
};

pub const std_options = std.Options {
	.side_channels_mitigations = .basic,
};

pub fn main() !void {
	try bitboard.init();
	defer bitboard.deinit();

	try engine.init();
	defer engine.deinit();

	var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
	defer _ = gpa.deinit();

	const allocator = gpa.allocator();
	var args = try std.process.argsWithAllocator(allocator);
	defer args.deinit();

	_ = args.skip();
	while (args.next()) |arg| {
		if (std.mem.eql(u8, arg, "bench")) {
			const depth: ?engine.search.Depth
			  = if (args.next()) |aux| try std.fmt.parseUnsigned(u8, aux, 10) else null;
			return bench.run(allocator, depth);
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	} else try engine.uci.loop(allocator);
}

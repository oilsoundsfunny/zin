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

	const allocator = std.heap.page_allocator;
	const args = try std.process.argsAlloc(allocator);
	var i: usize = 1;

	while (i < args.len) : (i += 1) {
		const arg = args[i];

		if (std.mem.eql(u8, arg, "bench")) {
			i += 1;
			const depth: ?engine.search.Depth = if (i >= args.len) null
			  else try std.fmt.parseUnsigned(u8, args[i], 10);
			return bench.run(depth);
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	try engine.uci.loop();
}

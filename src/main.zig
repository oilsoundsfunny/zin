const bitboard = @import("bitboard");
const engine = @import("engine");
const params = @import("params");
const selfplay = @import("selfplay");
const std = @import("std");
const types = @import("types");

const bench = @import("bench.zig");

const help =
  \\zin [command] [options]
  \\
  \\commands:
  \\    bench [depth]:
  \\        run benchmark for openbench.
  \\
  \\    datagen [options]:
  \\        generate training data.
  \\        options:
  \\            --book [path]      opening book to read from. must be specified.
  \\            --data [path]      data file to write to. must be specified.
  \\            --games [num]      number of games to play.
  \\                               defaults to the number of openings in specified book.
  \\            --ply [num]        number of random moves to play. defaults to 4.
  \\            --nodes [num]      number of nodes to search.
  \\                               either this or --depth must be specified.
  \\            --depth [num]      depth to search to. either this or --nodes must be specified.
  \\            --hash [num]       size of the transposition table in mib. defaults to 64.
  \\            --threads [num]    number of threads to use. defaults to 1.
  \\
  \\    help:
  \\        print this message and exit.
  \\
;

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

	try params.init();
	defer params.deinit();

	try engine.init();
	defer engine.deinit();

	var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
	const allocator = gpa.allocator();
	defer _ = gpa.deinit();

	var args = try std.process.argsWithAllocator(allocator);
	defer args.deinit();

	_ = args.skip();
	while (args.next()) |arg| {
		if (std.mem.eql(u8, arg, "bench")) {
			const depth: ?engine.search.Depth
			  = if (args.next()) |aux| try std.fmt.parseUnsigned(u8, aux, 10) else null;
			return bench.run(allocator, depth);
		} else if (std.mem.eql(u8, arg, "datagen")) {
			return selfplay.run(allocator, &args);
		} else if (std.mem.eql(u8, arg, "help")) {
			try std.fs.File.stdout().writeAll(help);
			std.process.exit(0);
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	} else try engine.uci.loop(allocator);
}

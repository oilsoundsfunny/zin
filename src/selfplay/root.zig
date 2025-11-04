const base = @import("base");
const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");

const Player = @import("Player.zig");

pub const author = "oilsoundsfunny";
pub const name = "selfplay";

pub fn main() !void {
	const args = try std.process.argsAlloc(base.heap.allocator);
	var i: usize = 1;

	var book_path: ?[]const u8 = null;
	var data_path: ?[]const u8 = null;
	var depth: ?engine.search.Depth = null;
	var games: ?usize = null;
	var nodes: ?usize = null;
	var threads: ?usize = null;

	while (i < args.len) : (i += 1) {
		const arg = args[i];

		if (std.mem.eql(u8, arg, "--book")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (book_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			book_path = args[i];
		} else if (std.mem.eql(u8, arg, "--data")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (data_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			data_path = args[i];
		} else if (std.mem.eql(u8, arg, "--depth")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (depth) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			depth = try std.fmt.parseUnsigned(u8, args[i], 10);
		} else if (std.mem.eql(u8, arg, "--games")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (games) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			games = try std.fmt.parseUnsigned(usize, args[i], 10);
		} else if (std.mem.eql(u8, arg, "--nodes")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (nodes) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			nodes = try std.fmt.parseUnsigned(usize, args[i], 10);
		} else if (std.mem.eql(u8, arg, "--threads")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (threads) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			threads = try std.fmt.parseUnsigned(usize, args[i], 10);
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	var io = try base.Io.init(book_path orelse std.process.fatal("missing arg '{s}'", .{"--book"}),
	  data_path orelse std.process.fatal("missing arg '{s}'", .{"--data"}));
	defer io.deinit();

	try base.init();
	defer base.deinit();

	try bitboard.init();
	defer bitboard.deinit();

	try engine.init();
	defer engine.deinit();

	_ = try engine.uci.parseCommand("setoption name Clear Hash");
	_ = try engine.uci.parseCommand("setoption name UCI_Chess960 value true");

	var tourney = try Player.Tourney.init(.{
		.io = &io,
		.games = games,
		.depth = depth,
		.nodes = nodes,
		.threads = threads orelse 1,
	});
	try tourney.start();
	defer tourney.stop();
}

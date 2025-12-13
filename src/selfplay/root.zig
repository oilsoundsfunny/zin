const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const Player = @import("Player.zig");

pub const author = "oilsoundsfunny";
pub const name = "selfplay";

pub fn main() !void {
	try bitboard.init();
	defer bitboard.deinit();

	try params.init();
	defer params.deinit();

	try engine.init();
	defer engine.deinit();

	var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
	const allocator = std.heap.page_allocator;
	defer _ = gpa.deinit();

	var args = try std.process.argsWithAllocator(allocator);
	_ = args.skip();
	defer args.deinit();

	var book_path: ?[]const u8 = null;
	var data_path: ?[]const u8 = null;
	var depth: ?engine.search.Depth = null;
	var games: ?usize = null;
	var nodes: ?usize = null;
	var threads: ?usize = null;

	while (args.next()) |arg| {
		if (std.mem.eql(u8, arg, "--book")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (book_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			book_path = aux;
		} else if (std.mem.eql(u8, arg, "--data")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (data_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			data_path = aux;
		} else if (std.mem.eql(u8, arg, "--depth")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (depth) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			depth = try std.fmt.parseUnsigned(u8, aux, 10);
		} else if (std.mem.eql(u8, arg, "--games")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (games) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			games = try std.fmt.parseUnsigned(usize, aux, 10);
		} else if (std.mem.eql(u8, arg, "--nodes")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (nodes) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			nodes = try std.fmt.parseUnsigned(usize, aux, 10);
		} else if (std.mem.eql(u8, arg, "--threads")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (threads) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			threads = try std.fmt.parseUnsigned(usize, aux, 10);
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	var io = try types.Io.init(allocator,
	  book_path orelse std.process.fatal("missing arg '{s}'", .{"--book"}), 1 << 16,
	  data_path orelse std.process.fatal("missing arg '{s}'", .{"--data"}), 1 << 16);
	defer io.deinit();

	var tt = try engine.transposition.Table.init(allocator, 128);
	try tt.clear(threads orelse 1);
	defer tt.deinit();

	var tourney = try Player.Tourney.init(.{
		.allocator = allocator,
		.io = &io,
		.tt = &tt,
		.games = games,
		.depth = depth,
		.nodes = nodes,
		.threads = threads orelse 1,
	});
	defer tourney.deinit();

	try tourney.start();
	defer tourney.stop();
}

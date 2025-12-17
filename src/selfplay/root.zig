const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const Player = @import("Player.zig");

pub fn run(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
	var book_path: ?[]const u8 = null;
	var data_path: ?[]const u8 = null;
	var games: ?usize = null;
	var ply: ?usize = null;
	var nodes: ?usize = null;
	var depth: ?engine.search.Depth = null;
	var opt_hash: ?usize = null;
	var opt_threads: ?usize = null;

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
		} else if (std.mem.eql(u8, arg, "--games")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (games) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			games = try std.fmt.parseUnsigned(usize, aux, 10);
		} else if (std.mem.eql(u8, arg, "--ply")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (ply) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			ply = try std.fmt.parseUnsigned(usize, aux, 10);
		} else if (std.mem.eql(u8, arg, "--nodes")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (nodes) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			nodes = try std.fmt.parseUnsigned(usize, aux, 10);
		} else if (std.mem.eql(u8, arg, "--depth")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (depth) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			depth = try std.fmt.parseUnsigned(u8, aux, 10);
		} else if (std.mem.eql(u8, arg, "--hash")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (opt_hash) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			opt_hash = try std.fmt.parseUnsigned(usize, aux, 10);
		} else if (std.mem.eql(u8, arg, "--threads")) {
			const aux = if (args.next()) |next| next
			  else std.process.fatal("expected arg after '{s}'", .{arg});

			if (opt_threads) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			opt_threads = try std.fmt.parseUnsigned(usize, aux, 10);
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	const hash = opt_hash orelse 64;
	const threads = opt_threads orelse 1;

	const buffer_size = threads * 8 * 65536;
	var io = try types.Io.init(allocator,
	  book_path orelse std.process.fatal("missing arg '{s}'", .{"--book"}), buffer_size,
	  data_path orelse std.process.fatal("missing arg '{s}'", .{"--data"}), buffer_size);
	defer io.deinit();

	var tt = try engine.transposition.Table.init(allocator, hash);
	try tt.clear(threads);
	defer tt.deinit();

	var tourney = try Player.Tourney.init(.{
		.allocator = allocator,
		.io = &io,
		.tt = &tt,
		.games = games,
		.ply = ply,
		.nodes = nodes,
		.depth = depth,
		.threads = threads,
	});
	defer tourney.deinit();

	try tourney.spawn();
	tourney.join();
	try io.writer().flush();
}

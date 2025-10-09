const base = @import("base");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");

const Player = @import("Player.zig");

pub const author = "oilsoundsfunny";
pub const name = "selfplay";

pub fn main() !void {
	try base.init();
	defer base.deinit();

	try engine.init();
	engine.uci.options.frc = true;
	defer engine.deinit();

	const args = try std.process.argsAlloc(base.heap.allocator);
	var i: usize = 1;

	var book_paths = try bounded_array.BoundedArray([]const u8, 256).init(0);
	var data_paths = try bounded_array.BoundedArray([]const u8, 256).init(0);
	var games: ?u64 = null;
	var nodes: ?u64 = null;
	var threads: ?usize = null;

	while (i < args.len) : (i += 1) {
		const arg = args[i];

		if (std.mem.eql(u8, arg, "--book")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			try book_paths.append(args[i]);
		} else if (std.mem.eql(u8, arg, "--data")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			try data_paths.append(args[i]);
		} else if (std.mem.eql(u8, arg, "--games")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (games) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			games = try std.fmt.parseUnsigned(u64, args[i], 10);
		} else if (std.mem.eql(u8, arg, "--nodes")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (nodes) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			nodes = try std.fmt.parseUnsigned(u64, args[i], 10);
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

	threads = threads orelse 1;
	if (book_paths.len < threads.?) {
		std.process.fatal("too few books", .{});
	} else if (book_paths.len > threads.?) {
		std.process.fatal("too many books", .{});
	}
	if (data_paths.len < threads.?) {
		std.process.fatal("too few files", .{});
	} else if (data_paths.len > threads.?) {
		std.process.fatal("too many files", .{});
	}

	var tourney = try Player.Tourney.alloc(threads.?, book_paths, data_paths,
	  games, nodes orelse std.process.fatal("missing arg '--nodes'", .{}));
	try tourney.start();
}

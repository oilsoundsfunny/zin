const bitboard = @import("bitboard");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

pub const thread = @import("thread.zig");
pub const viri = @import("viri.zig");

pub const Request = struct {
	games:	?usize = null,
	repeat:	 usize = 1,
	played:	 usize = 0,
};

const Options = struct {
	book:	?[]const u8 = null,
	data:	?[]const u8 = null,
	games:	?usize = null,
	depth:	?engine.Thread.Depth = null,
	soft_nodes:	?usize = null,
	hard_nodes:	?usize = null,
	hash:	?usize = null,
	threads:	?usize = null,
};

pub fn run(pool: *engine.Thread.Pool, args: *std.process.ArgIterator) !void {
	var options: Options = .{};
	while (args.next()) |arg| {
		if (std.mem.eql(u8, arg, "--book")) {
			if (options.book) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}

			options.book = args.next() orelse std.process.fatal("expected arg after '{s}'", .{arg});
		} else if (std.mem.eql(u8, arg, "--data")) {
			if (options.data) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}

			options.data = args.next() orelse std.process.fatal("expected arg after '{s}'", .{arg});
		} else if (std.mem.eql(u8, arg, "--games")) {
			if (options.games) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}

			const token = args.next() orelse std.process.fatal("expected arg after '{s}'", .{arg});
			options.games = try std.fmt.parseUnsigned(usize, token, 10);
		} else if (std.mem.eql(u8, arg, "--depth")) {
			if (options.depth) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}

			const token = args.next() orelse std.process.fatal("expected arg after '{s}'", .{arg});
			options.depth = try std.fmt.parseUnsigned(engine.Thread.Depth, token, 10);
		} else if (std.mem.eql(u8, arg, "--soft-nodes")) {
			if (options.soft_nodes) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}

			const token = args.next() orelse std.process.fatal("expected arg after '{s}'", .{arg});
			options.soft_nodes = try std.fmt.parseUnsigned(usize, token, 10);
		} else if (std.mem.eql(u8, arg, "--hard-nodes")) {
			if (options.hard_nodes) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}

			const token = args.next() orelse std.process.fatal("expected arg after '{s}'", .{arg});
			options.hard_nodes = try std.fmt.parseUnsigned(usize, token, 10);
		} else if (std.mem.eql(u8, arg, "--hash")) {
			if (options.hash) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}

			const token = args.next() orelse std.process.fatal("expected arg after '{s}'", .{arg});
			options.hash = try std.fmt.parseUnsigned(usize, token, 10);
		} else if (std.mem.eql(u8, arg, "--threads")) {
			if (options.threads) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}

			const token = args.next() orelse std.process.fatal("expected arg after '{s}'", .{arg});
			options.threads = try std.fmt.parseUnsigned(usize, token, 10);
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	const hash = options.hash orelse 128;
	const threads = options.threads orelse 1;

	try pool.realloc(threads);
	pool.tt.deinit(pool.allocator);
	pool.tt = try engine.transposition.Table.init(pool.allocator, hash);
	pool.clearHash();

	const book = options.book orelse std.process.fatal("missing arg '--book'", .{});
	const data = options.data orelse std.process.fatal("missing arg '--data'", .{});

	pool.io.deinit(pool.allocator);
	pool.io = try types.IO.init(pool.allocator, book, 4096, data, 4096);

	pool.options.depth = options.depth;
	pool.options.soft_nodes = options.soft_nodes orelse 5000;
	pool.options.hard_nodes = options.hard_nodes orelse 100000;
	pool.options.setLimits(.white);

	pool.datagen(.{
		.games = options.games orelse std.math.maxInt(usize),
	});
	pool.waitSleep();
}

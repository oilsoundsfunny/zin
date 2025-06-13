const config = @import("config");
const misc = @import("misc");
const std = @import("std");

const Thread = @import("Thread.zig");
const search = @import("search.zig");
const timeman = @import("timeman.zig");

const Command = enum {
	go,
	none,
	printpos,
	position,
	setoption,
	stop,
	quit,
};

pub const Error = error {
	UnknownCommand,
};

fn parseGo(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const main_worker = try Thread.Pool.global.getMainWorker();
	const stm = main_worker.pos.stm;

	timeman.depth = std.math.maxInt(@TypeOf(timeman.depth));
	timeman.movetime = std.math.maxInt(@TypeOf(timeman.movetime));
	timeman.increment = @TypeOf(timeman.increment).init(.{
	  .white = std.math.maxInt(@TypeOf(timeman.increment.get(.white))),
	  .black = std.math.maxInt(@TypeOf(timeman.increment.get(.black))),
	});
	timeman.time = @TypeOf(timeman.time).init(.{
	  .white = std.math.maxInt(@TypeOf(timeman.time.get(.white))),
	  .black = std.math.maxInt(@TypeOf(timeman.time.get(.black))),
	});

	while (tokens.next()) |token| {
		if (std.mem.eql(u8, token, "depth")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.depth = try std.fmt.parseUnsigned(@TypeOf(timeman.depth), aux_token, 10);
		} else if (std.mem.eql(u8, token, "movetime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.movetime = try std.fmt.parseUnsigned(@TypeOf(timeman.movetime), aux_token, 10);
		} else if (stm == .white and std.mem.eql(u8, token, "winc")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.increment.set(.white,
			  try std.fmt.parseUnsigned(@TypeOf(timeman.increment.get(.white)), aux_token, 10));
		} else if (stm == .white and std.mem.eql(u8, token, "wtime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.time.set(.white,
			  try std.fmt.parseUnsigned(@TypeOf(timeman.time.get(.white)), aux_token, 10));
		} else if (stm == .black and std.mem.eql(u8, token, "binc")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.increment.set(.black,
			  try std.fmt.parseUnsigned(@TypeOf(timeman.increment.get(.black)), aux_token, 10));
		} else if (stm == .black and std.mem.eql(u8, token, "btime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.time.set(.black,
			  try std.fmt.parseUnsigned(@TypeOf(timeman.time.get(.black)), aux_token, 10));
		} else return error.UnknownCommand;
	}

	try Thread.Pool.global.prepare();
	try Thread.Pool.global.startMainWorker(search.onThread, .{});
}

fn parsePosition(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const main_worker = try Thread.Pool.global.getMainWorker();
	const first = tokens.next() orelse return error.UnknownCommand;
	if (std.mem.eql(u8, first, "fen")) {
	} else if (std.mem.eql(u8, first, "kiwipete")) {
		try main_worker.pos.parseFen(
		  \\r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R
		  \\ w KQkq - 0 1
		);
	} else if (std.mem.eql(u8, first, "startpos")) {
		try main_worker.pos.parseFen(
		  \\rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR
		  \\ w KQkq - 0 1
		);
	} else return error.UnknownCommand;

	try Thread.Pool.global.genRootMoves();
}

pub fn parseCommand(comm: []const u8) !Command {
	var tokens = std.mem.tokenizeAny(u8, comm, "\t\n\r ");
	const first_token = tokens.next() orelse return error.UnknownCommand;
	const main_worker = try Thread.Pool.global.getMainWorker();

	if (std.mem.eql(u8, first_token, @tagName(.go))) {
		try parseGo(&tokens);
		return .go;
	} else if (std.mem.eql(u8, first_token, @tagName(.printpos))) {
		if (tokens.next() != null) {
			return error.UnknownCommand;
		}
		try main_worker.pos.printSelf();
		return .printpos;
	} else if (std.mem.eql(u8, first_token, @tagName(.position))) {
		try parsePosition(&tokens);
		return .position;
	} else if (std.mem.eql(u8, first_token, @tagName(.setoption))) {
		return .setoption;
	} else if (std.mem.eql(u8, first_token, @tagName(.stop))) {
		if (tokens.next() != null) {
			return error.UnknownCommand;
		}
		search.execing = false;
		return .stop;
	} else if (std.mem.eql(u8, first_token, @tagName(.quit))) {
		if (tokens.next() != null) {
			return error.UnknownCommand;
		}
		return .quit;
	}
	return error.UnknownCommand;
}

pub fn printEngine() !void {
	const stdout = std.io.getStdOut();
	try stdout.writer().print("{s} {d}.{d}.{d} by {s}\n", .{
	  config.name, config.version.major, config.version.minor, config.version.patch, config.author,
	});
}

pub fn readInput() !void {
	const stdin = std.io.getStdIn();
	const stdout = std.io.getStdOut();
	var buffer = std.mem.zeroes([16384]u8);

	while (true) {
		const read = (try stdin.reader().readUntilDelimiterOrEof(buffer[0 ..], '\n'))
			orelse continue;
		const command = parseCommand(read) catch |err| blk: {
			if (err == error.UnknownCommand) {
				try stdout.writer().print("Unknown command {s}\n", .{read});
				break :blk .none;
			} else return err;
		};

		if (command == .quit) {
			break;
		}
	}
}

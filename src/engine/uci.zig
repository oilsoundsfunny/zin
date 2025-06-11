const config = @import("config");
const misc = @import("misc");
const std = @import("std");

const Thread = @import("Thread.zig");
const timeman = @import("timeman.zig");

pub const Error = error {
	UnknownCommand,
};

fn parseGo(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const main_worker = try Thread.Pool.global.getMainWorker();
	const stm = main_worker.pos.stm;

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
}

pub fn printEngine() !void {
	const stdout = std.io.getStdOut();
	try stdout.writer().print("{s} {d}.{d}.{d} by {s}\n", .{
	  config.name, config.version.major, config.version.minor, config.version.patch, config.author,
	});
}

pub fn parseInput() !void {
	const main_worker = try Thread.Pool.global.getMainWorker();
	const stdin = std.io.getStdIn();
	const stdout = std.io.getStdOut();
	var buffer = std.mem.zeroes([16384]u8);

	while (true) {
		const read = (try stdin.reader().readUntilDelimiterOrEof(buffer[0 ..], '\n'))
			orelse continue;
		var token_itr = std.mem.tokenizeAny(u8, read, "\t\n\r ");

		const first_token = token_itr.next() orelse continue;
		if (std.mem.eql(u8, first_token, "go")) {
		} else if (std.mem.eql(u8, first_token, "printpos")) {
			if (token_itr.next() != null) {
				try stdout.writer().print("Unknown command {s}\n", .{read});
			}
			try main_worker.pos.printSelf();
		} else if (std.mem.eql(u8, first_token, "position")) {
			try parsePosition(&token_itr);
		} else if (std.mem.eql(u8, first_token, "setoption")) {
		} else if (std.mem.eql(u8, first_token, "stop")) {
		} else if (std.mem.eql(u8, first_token, "quit")) {
			break;
		} else try stdout.writer().print("Unknown command {s}\n", .{read});
	}
}

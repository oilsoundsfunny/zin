const config = @import("config");
const misc = @import("misc");
const std = @import("std");

const Thread = @import("Thread.zig");

fn setPosition(fen: []const u8) !void {
	const main_worker = Thread.Pool.global.getMainWorker() orelse return error.OutOfMemory;
	try main_worker.pos.parseFen(fen);
}

pub fn printEngine() !void {
	const stdout = std.io.getStdOut();
	try stdout.writer().print("{s} {d}.{d}.{d} by {s}\n", .{
	  config.name, config.version.major, config.version.minor, config.version.patch, config.author,
	});
}

pub fn parseInput() !void {
	const main_worker = Thread.Pool.global.getMainWorker() orelse return error.Uninitialized;
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
			const second_token = token_itr.next() orelse continue;
			if (std.mem.eql(u8, second_token, "fen")) {
			} else if (std.mem.eql(u8, second_token, "kiwipete")) {
				try setPosition(
				  \\r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R
				  \\w KQkq - 0 1
				);
			} else if (std.mem.eql(u8, second_token, "startpos")) {
				try setPosition(
				  \\rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR
				  \\w KQkq - 0 1
				);
			} else {
			}
		} else if (std.mem.eql(u8, first_token, "setoption")) {
		} else if (std.mem.eql(u8, first_token, "stop")) {
		} else if (std.mem.eql(u8, first_token, "quit")) {
			break;
		} else try stdout.writer().print("Unknown command {s}\n", .{read});
	}
}

const config = @import("config");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const search = @import("search.zig");
const smp = @import("smp.zig");
const transposition = @import("transposition.zig");

const Command = enum {
	go,
	none,
	printhash,
	printpos,
	printthreads,
	position,
	setoption,
	stop,
	quit,
};

pub const Error = error {
	UnknownCommand,
};

var input_info = std.mem.zeroes(smp.Info);

fn parseGo(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const stm = input_info.pos.stm;

	input_info.max_depth = null;
	input_info.movetime = null;
	input_info.increment = null;
	input_info.time = null;
	input_info.starttime = null;
	input_info.stoptime = null;

	while (tokens.next()) |token| {
		if (std.mem.eql(u8, token, "max_depth")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			input_info.max_depth = try std.fmt.parseUnsigned(u8, aux_token, 10);
		} else if (std.mem.eql(u8, token, "movetime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			input_info.movetime = try std.fmt.parseUnsigned(u64, aux_token, 10);
		} else if (stm == .white and std.mem.eql(u8, token, "winc")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			input_info.increment = try std.fmt.parseUnsigned(u64, aux_token, 10);
		} else if (stm == .white and std.mem.eql(u8, token, "wtime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			input_info.time = try std.fmt.parseUnsigned(u64, aux_token, 10);
		} else if (stm == .black and std.mem.eql(u8, token, "binc")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			input_info.increment = try std.fmt.parseUnsigned(u64, aux_token, 10);
		} else if (stm == .black and std.mem.eql(u8, token, "btime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			input_info.time = try std.fmt.parseUnsigned(u64, aux_token, 10);
		} else return error.UnknownCommand;
	}
}

fn parseOption(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const first_token = tokens.next() orelse return error.UnknownCommnad;
	if (!std.mem.eql(u8, first_token, "name")) {
		return error.UnknownCommand;
	}

	const second_token = tokens.next() orelse return error.UnknownCommand;
	if (std.mem.eql(u8, second_token, "Clear")) {
		const aux_token = tokens.next() orelse return error.UnknownCommand;
		if (!std.mem.eql(u8, aux_token, "Hash") or tokens.peek() != null) {
			return error.UnknownCommand;
		}
		transposition.Table.global.clear();
	} else if (std.mem.eql(u8, second_token, "Hash")) {
		const third_token = tokens.next() orelse return error.UnknownCommand;
		if (!std.mem.eql(u8, third_token, "value")) {
			return error.UnknownCommand;
		}

		const fourth_token = tokens.next() orelse return error.UnknownCommand;
		const value = std.fmt.parseUnsigned(usize, fourth_token, 10)
			catch return error.UnknownCommand;
		try transposition.Table.global.allocate(value);
	} else if (std.mem.eql(u8, second_token, "Threads")) {
		const third_token = tokens.next() orelse return error.UnknownCommand;
		if (!std.mem.eql(u8, third_token, "value")) {
			return error.UnknownCommand;
		}

		const fourth_token = tokens.next() orelse return error.UnknownCommand;
		const value = std.fmt.parseUnsigned(usize, fourth_token, 10)
			catch return error.UnknownCommand;

		try smp.init(.{
			.allocator = misc.heap.allocator,
			.n_jobs = value,
		});
	} else return error.UnknownCommand;
}

fn parsePosition(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const first = tokens.next() orelse return error.UnknownCommand;

	if (std.mem.eql(u8, first, "fen")) {
		try input_info.pos.parseFenTokens(tokens);
	} else if (std.mem.eql(u8, first, "kiwipete")) {
		try input_info.pos.parseFen(
		  \\r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R
		  \\ w KQkq - 0 1
		);
	} else if (std.mem.eql(u8, first, "startpos")) {
		try input_info.pos.parseFen(
		  \\rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR
		  \\ w KQkq - 0 1
		);
	} else return error.UnknownCommand;
}

pub fn parseCommand(comm: []const u8) !Command {
	var tokens = std.mem.tokenizeAny(u8, comm, "\t\n\r ");
	const first_token = tokens.next() orelse return error.UnknownCommand;

	if (std.mem.eql(u8, first_token, @tagName(.go))) {
		try parseGo(&tokens);
		return .go;
	} else if (std.mem.eql(u8, first_token, @tagName(.printhash))) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		const stdout = std.io.getStdOut();
		try stdout.writer().print("info string Hash: {*}[0 .. {d}]\n",
		  .{transposition.Table.global.tbl.?, transposition.Table.global.tbl.?.len});
		return .printhash;
	} else if (std.mem.eql(u8, first_token, @tagName(.printpos))) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		try input_info.pos.printSelf();
		return .printpos;
	} else if (std.mem.eql(u8, first_token, @tagName(.printthreads))) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		const stdout = std.io.getStdOut();
		try stdout.writer().print("info string Threads: {*}[0 .. {d}]\n",
		  .{smp.pool.threads, smp.pool.threads.len});
		return .printthreads;
	} else if (std.mem.eql(u8, first_token, @tagName(.position))) {
		try parsePosition(&tokens);
		return .position;
	} else if (std.mem.eql(u8, first_token, @tagName(.setoption))) {
		try parseOption(&tokens);
		return .setoption;
	} else if (std.mem.eql(u8, first_token, @tagName(.stop))) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}
		return .stop;
	} else if (std.mem.eql(u8, first_token, @tagName(.quit))) {
		if (tokens.peek() != null) {
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

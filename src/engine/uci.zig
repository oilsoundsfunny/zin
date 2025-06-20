const config = @import("config");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const movegen = @import("movegen.zig");
const search = @import("search.zig");
const timeman = @import("timeman.zig");
const transposition = @import("transposition.zig");

const Command = enum {
	go,
	isready,
	none,
	perft,
	printhash,
	printpos,
	printthreads,
	position,
	setoption,
	stop,
	quit,
	uci,
	ucinewgame,
};

pub const Error = error {
	UnknownCommand,
	UnknownPosition,
};

fn parseGo(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const main_info = try search.Info.ofMain();
	const stm = main_info.pos.stm;

	timeman.depth = null;
	timeman.movetime = null;
	timeman.increment = null;
	timeman.time = null;
	timeman.stop = null;

	while (tokens.next()) |token| {
		if (std.ascii.eqlIgnoreCase(token, "depth")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.depth = try std.fmt.parseUnsigned(u8, aux_token, 10);
		} else if (std.ascii.eqlIgnoreCase(token, "movetime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.movetime = try std.fmt.parseUnsigned(u64, aux_token, 10);
		} else if (std.ascii.eqlIgnoreCase(token, "winc")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			const value = try std.fmt.parseUnsigned(u64, aux_token, 10);
			if (stm == .white) {
				timeman.increment = value;
			}
		} else if (std.ascii.eqlIgnoreCase(token, "wtime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			const value = try std.fmt.parseUnsigned(u64, aux_token, 10);
			if (stm == .white) {
				timeman.time = value;
			}
		} else if (std.ascii.eqlIgnoreCase(token, "binc")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			const value = try std.fmt.parseUnsigned(u64, aux_token, 10);
			if (stm == .black) {
				timeman.increment = value;
			}
		} else if (std.ascii.eqlIgnoreCase(token, "btime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			const value = try std.fmt.parseUnsigned(u64, aux_token, 10);
			if (stm == .black) {
				timeman.time = value;
			}
		} else return error.UnknownCommand;
	}

	try search.manager.spawn();
}

fn parseOption(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const first_token = tokens.next() orelse return error.UnknownCommnad;
	if (!std.ascii.eqlIgnoreCase(first_token, "name")) {
		return error.UnknownCommand;
	}

	const second_token = tokens.next() orelse return error.UnknownCommand;
	if (std.ascii.eqlIgnoreCase(second_token, "Clear")) {
		const aux_token = tokens.next() orelse return error.UnknownCommand;
		if (!std.ascii.eqlIgnoreCase(aux_token, "Hash") or tokens.peek() != null) {
			return error.UnknownCommand;
		}
		transposition.Table.global.clear();
	} else if (std.ascii.eqlIgnoreCase(second_token, "Hash")) {
		const third_token = tokens.next() orelse return error.UnknownCommand;
		if (!std.ascii.eqlIgnoreCase(third_token, "value")) {
			return error.UnknownCommand;
		}

		const fourth_token = tokens.next() orelse return error.UnknownCommand;
		const value = std.fmt.parseUnsigned(usize, fourth_token, 10)
			catch return error.UnknownCommand;

		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}
		try transposition.Table.global.allocate(value);
	} else if (std.ascii.eqlIgnoreCase(second_token, "Move")) {
		const aux_token = tokens.next() orelse return error.UnknownCommand;
		if (!std.ascii.eqlIgnoreCase(aux_token, "Overhead")) {
			return error.UnknownCommand;
		}

		const value_token = tokens.next() orelse return error.UnknownCommand;
		const value = std.fmt.parseUnsigned(usize, value_token, 10)
			catch return error.UnknownCommand;

		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}
		timeman.overhead = value;
	} else if (std.ascii.eqlIgnoreCase(second_token, "Threads")) {
		const third_token = tokens.next() orelse return error.UnknownCommand;
		if (!std.ascii.eqlIgnoreCase(third_token, "value")) {
			return error.UnknownCommand;
		}

		const fourth_token = tokens.next() orelse return error.UnknownCommand;
		const value = std.fmt.parseUnsigned(usize, fourth_token, 10)
			catch return error.UnknownCommand;

		if (search.Info.global) |old| {
			search.Info.global = try misc.heap.allocator.realloc(old, value);
		} else {
			search.Info.global = try misc.heap.allocator.alignedAlloc(search.Info, .@"64", value);
		}
	} else return error.UnknownCommand;
}

fn parsePosition(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const first = tokens.next() orelse return error.UnknownCommand;
	const main_info = try search.Info.ofMain();

	if (std.ascii.eqlIgnoreCase(first, "fen")) {
		main_info.pos.parseFenTokens(tokens) catch return error.UnknownPosition;
	} else if (std.ascii.eqlIgnoreCase(first, "kiwipete")) {
		main_info.pos.parseFen(
		  \\r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R
		  \\ w KQkq - 0 1
		) catch return error.UnknownPosition;
	} else if (std.ascii.eqlIgnoreCase(first, "startpos")) {
		main_info.pos.parseFen(
		  \\rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR
		  \\ w KQkq - 0 1
		) catch return error.UnknownPosition;
	} else return error.UnknownPosition;

	if (tokens.next()) |second| {
		if (!std.ascii.eqlIgnoreCase(second, "moves")) {
			return error.UnknownPosition;
		}

		move_loop: while (tokens.next()) |move_token| {
			var list = std.mem.zeroes(movegen.ScoredMove.List);
			_ = list.gen(main_info.pos, true);
			_ = list.gen(main_info.pos, false);
			for (list.constSlice()) |sm| {
				const move = sm.move;
				const len: usize = if (move.promotion() != .nil) 5 else 4;
				if (std.ascii.eqlIgnoreCase(move_token, move.print()[0 .. len])) {
					main_info.pos.doMove(move) catch return error.UnknownPosition;
					continue :move_loop;
				}
			}
			return error.UnknownPosition;
		}
	}
}

pub fn parseCommand(comm: []const u8) !Command {
	var tokens = std.mem.tokenizeAny(u8, comm, "\t\n\r ");
	const first = tokens.next() orelse return error.UnknownCommand;

	if (std.ascii.eqlIgnoreCase(first, "go")) {
		try parseGo(&tokens);
		return .go;
	} else if (std.ascii.eqlIgnoreCase(first, "isready")) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		const stdout = std.io.getStdOut();
		try stdout.lock(.exclusive);
		try stdout.writer().print("readyok\n", .{});
		stdout.unlock();

		return .isready;
	} else if (std.ascii.eqlIgnoreCase(first, "printhash")) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		const stdout = std.io.getStdOut();
		try stdout.writer().print("info string Hash: {*}[0 .. {d}]\n",
		  .{transposition.Table.global.tbl.?, transposition.Table.global.tbl.?.len});
		return .printhash;
	} else if (std.ascii.eqlIgnoreCase(first, "printpos")) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		const main_info = try search.Info.ofMain();
		try main_info.pos.printSelf();
		return .printpos;
	} else if (std.ascii.eqlIgnoreCase(first, "position")) {
		try parsePosition(&tokens);
		return .position;
	} else if (std.ascii.eqlIgnoreCase(first, "setoption")) {
		try parseOption(&tokens);
		return .setoption;
	} else if (std.ascii.eqlIgnoreCase(first, "stop")) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		@atomicStore(bool, &timeman.is_searching, false, .monotonic);
		return .stop;
	} else if (std.ascii.eqlIgnoreCase(first, "quit")) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}
		return .quit;
	} else if (std.ascii.eqlIgnoreCase(first, "uci")) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		const stdout = std.io.getStdOut();
		try stdout.writer().print("id name {s}\n", .{config.name});
		try stdout.writer().print("id author {s}\n", .{config.author});
		try stdout.writer().print("option name Clear Hash type button\n", .{});
		try stdout.writer()
		  .print("option name Hash type spin default 64 min 1 max {d}\n", .{1 << 22});
		try stdout.writer().print("option name Threads type spin default 1 min 1 max 16\n", .{});
		try stdout.writer().print("uciok\n", .{});
		return .uci;
	} else if (std.ascii.eqlIgnoreCase(first, "ucinewgame")) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		transposition.Table.global.clear();
		const infos = try search.Info.ofThreads();
		const pos = infos[0].pos;
		for (infos) |*info| {
			info.* = .{};
			info.pos = pos;
		}
		return .ucinewgame;
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

	defer @atomicStore(bool, &timeman.is_running, false, .monotonic);
	while (true) {
		const read = (try stdin.reader().readUntilDelimiterOrEof(buffer[0 ..], '\n'))
			orelse continue;
		const command = parseCommand(read) catch |err| sw: switch (err) {
			error.UnknownCommand, error.UnknownPosition => {
				try stdout.writer().print("Unknown command {s}\n", .{read});
				break :sw .none;
			},
			else => return err,
		};

		if (command == .quit) {
			break;
		}
	}
}

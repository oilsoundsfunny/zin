const config = @import("config");
const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const movegen = @import("movegen.zig");
const search = @import("search.zig");
const timeman = @import("timeman.zig");
const transposition = @import("transposition.zig");

const stdin  = std.io.getStdIn();
const stdout = std.io.getStdOut();

var buffered_inp = std.io.bufferedReader(stdin.reader());
var buffered_out = std.io.bufferedWriter(stdout.writer());

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
	timeman.depth = null;
	timeman.movetime = null;
	timeman.increment = @TypeOf(timeman.increment).init(.{
		.white = null,
		.black = null,
	});
	timeman.time = @TypeOf(timeman.time).init(.{
		.white = null,
		.black = null,
	});
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
			timeman.increment.set(.white, try std.fmt.parseUnsigned(u64, aux_token, 10));
		} else if (std.ascii.eqlIgnoreCase(token, "wtime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.time.set(.white, try std.fmt.parseUnsigned(u64, aux_token, 10));
		} else if (std.ascii.eqlIgnoreCase(token, "binc")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.increment.set(.black, try std.fmt.parseUnsigned(u64, aux_token, 10));
		} else if (std.ascii.eqlIgnoreCase(token, "btime")) {
			const aux_token = tokens.next() orelse return error.UnknownCommand;
			timeman.time.set(.black, try std.fmt.parseUnsigned(u64, aux_token, 10));
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
		try transposition.Table.global.clear();
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

	var pos = Position {};
	if (std.ascii.eqlIgnoreCase(first, "fen")) {
		pos.parseFenTokens(tokens) catch return error.UnknownPosition;
	} else if (std.ascii.eqlIgnoreCase(first, "kiwipete")) {
		pos.parseFen(
		  \\r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R
		  \\ w KQkq - 0 1
		) catch return error.UnknownPosition;
	} else if (std.ascii.eqlIgnoreCase(first, "startpos")) {
		pos.parseFen(
		  \\rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR
		  \\ w KQkq - 0 1
		) catch return error.UnknownPosition;
	} else return error.UnknownPosition;

	if (tokens.next()) |second| {
		if (!std.ascii.eqlIgnoreCase(second, "moves")) {
			return error.UnknownPosition;
		}

		move_loop: while (tokens.next()) |move_token| {
			var list = std.mem.zeroes(movegen.Move.List);
			_ = list.genNoisy(pos);
			_ = list.genQuiet(pos);
			for (list.constSlice()) |move| {
				const str = move.print();
				const len: usize = if (move.promotion() != .nil) 5 else 4;
				if (std.ascii.eqlIgnoreCase(move_token, str[0 .. len])) {
					pos.doMove(move) catch return error.UnknownPosition;
					continue :move_loop;
				}
			}
			return error.UnknownPosition;
		}
	}

	main_info.pos = pos;
	main_info.pos.ss = @TypeOf(main_info.pos.ss).default;
	main_info.pos.ssTopPtr()[0] = pos.ssTop();
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

		try buffered_out.writer().print("readyok\n", .{});
		return .isready;
	} else if (std.ascii.eqlIgnoreCase(first, "printhash")) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		try buffered_out.writer().print("info string Hash: {*}[0 .. {d}]\n",
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

		try buffered_out.writer().print("id name {s}\n", .{config.name});
		try buffered_out.writer().print("id author {s}\n", .{config.author});
		try buffered_out.writer().print("option name Clear Hash type button\n", .{});
		try buffered_out.writer()
		  .print("option name Hash type spin default 64 min 1 max {d}\n", .{1 << 22});
		try buffered_out.writer().print("option name Threads type spin default 1 min 1 max 16\n", .{});
		try buffered_out.writer().print("uciok\n", .{});
		return .uci;
	} else if (std.ascii.eqlIgnoreCase(first, "ucinewgame")) {
		if (tokens.peek() != null) {
			return error.UnknownCommand;
		}

		try transposition.Table.global.clear();
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
	try buffered_out.writer().print("{s} {d}.{d}.{d} by {s}\n", .{
	  config.name, config.version.major, config.version.minor, config.version.patch, config.author,
	});
	try buffered_out.flush();
}

pub fn readInput() !void {
	var buffer: [4096]u8 = undefined;

	defer @atomicStore(bool, &timeman.is_running, false, .monotonic);
	while (true) {
		buffer = std.mem.zeroes([4096]u8);
		const read = (try buffered_inp.reader().readUntilDelimiterOrEof(buffer[0 ..], '\n'))
			orelse continue;
		const command = parseCommand(read) catch |err| sw: switch (err) {
			error.UnknownCommand, error.UnknownPosition => {
				try buffered_out.writer().print("Unknown command {s}\n", .{read});
				break :sw .none;
			},
			else => return err,
		};

		if (command == .quit) {
			break;
		}
		try buffered_out.flush();
	}
}

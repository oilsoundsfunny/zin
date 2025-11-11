const std = @import("std");
const types = @import("types");

const movegen = @import("movegen.zig");
const Position = @import("Position.zig");
const search = @import("search.zig");
const transposition = @import("transposition.zig");

const Error = error {
	UnknownCommand,
};

const Command = enum {
	debug,
	go,
	isready,
	none,
	position,
	quit,
	setoption,
	stop,
	uci,
	ucinewgame,
};

fn parseGo(tokens: *std.mem.TokenIterator(u8, .any), pool: *search.Pool) !Command {
	const options = &pool.options;
	const stm = pool.threads[0].pos.stm;

	options.reset();
	errdefer options.reset();

	while (tokens.next()) |token| {
		if (std.mem.eql(u8, token, "infinite")) {
			options.reset();
			continue;
		}
		defer options.infinite = false;

		const aux = tokens.next() orelse return error.UnknownCommand;
		if (std.mem.eql(u8, token, "depth")) {
			options.depth = std.fmt.parseUnsigned(u8, aux, 10)
			  catch return error.UnknownCommand;
		} else if (std.mem.eql(u8, token, "movetime")) {
			options.movetime = std.fmt.parseUnsigned(u64, aux, 10)
			  catch return error.UnknownCommand;
		} else if (std.mem.eql(u8, token, "nodes")) {
			options.nodes = std.fmt.parseUnsigned(u64, aux, 10)
			  catch return error.UnknownCommand;
		} else if (std.mem.eql(u8, token, "winc")) {
			options.incr.put(.white,
			  std.fmt.parseUnsigned(u64, aux, 10) catch return error.UnknownCommand);
		} else if (std.mem.eql(u8, token, "wtime")) {
			options.time.put(.white,
			  std.fmt.parseUnsigned(u64, aux, 10) catch return error.UnknownCommand);
		} else if (std.mem.eql(u8, token, "binc")) {
			options.incr.put(.black,
			  std.fmt.parseUnsigned(u64, aux, 10) catch return error.UnknownCommand);
		} else if (std.mem.eql(u8, token, "btime")) {
			options.time.put(.black,
			  std.fmt.parseUnsigned(u64, aux, 10) catch return error.UnknownCommand);
		} else return error.UnknownCommand;
	} else options.calcStop(stm);

	try pool.start();
	return .go;
}

fn parseOption(tokens: *std.mem.TokenIterator(u8, .any), pool: *search.Pool) !Command {
	const options = &pool.options;
	const tt = pool.tt;

	const first = tokens.next() orelse return error.UnknownCommand;
	if (!std.mem.eql(u8, first, "name")) {
		return error.UnknownCommand;
	}

	const name = tokens.next() orelse return error.UnknownCommand;
	const aux = tokens.next() orelse return error.UnknownCommand;
	if (std.ascii.eqlIgnoreCase(name, "Clear")) {
		if (!std.ascii.eqlIgnoreCase(aux, "Hash")) {
			return error.UnknownCommand;
		}

		try tt.clear(pool.threads.len);
	} else if (std.ascii.eqlIgnoreCase(name, "Hash")) {
		if (!std.mem.eql(u8, aux, "value")) {
			return error.UnknownCommand;
		}

		const value = tokens.next() orelse return error.UnknownCommand;
		options.hash = std.fmt.parseUnsigned(usize, value, 10)
		  catch return error.UnknownCommand;
		try tt.realloc(options.hash);
	} else if (std.ascii.eqlIgnoreCase(name, "Threads")) {
		if (!std.mem.eql(u8, aux, "value")) {
			return error.UnknownCommand;
		}

		const value = tokens.next() orelse return error.UnknownCommand;
		options.threads = std.fmt.parseUnsigned(usize, value, 10)
		  catch return error.UnknownCommand;
		try pool.realloc(options.threads);
	} else if (std.ascii.eqlIgnoreCase(name, "UCI_Chess960")) {
		if (!std.mem.eql(u8, aux, "value")) {
			return error.UnknownCommand;
		}

		const value = tokens.next() orelse return error.UnknownCommand;
		const frc = if (std.mem.eql(u8, value, "false")) false
		  else if (std.mem.eql(u8, value, "true")) true
		  else return error.UnknownCommand;
		pool.setFRC(frc);
	} else return error.UnknownCommand;

	return .setoption;
}

fn parsePosition(tokens: *std.mem.TokenIterator(u8, .any), pool: *search.Pool) !Command {
	const frc = pool.threads[0].pos.frc;
	var pos: Position = .{};
	defer {
		pos.frc = frc;
		pool.setPosition(&pos);
	}

	errdefer {
		pos.parseFen(Position.startpos) catch std.debug.panic("invalid startpos", .{});
		pos.frc = frc;
	}

	const first = tokens.next() orelse return error.UnknownCommand;
	if (std.mem.eql(u8, first, "fen")) {
		try pos.parseFenTokens(tokens);
	} else if (std.mem.eql(u8, first, "kiwipete")) {
		try pos.parseFen(Position.kiwipete);
	} else if (std.mem.eql(u8, first, "startpos")) {
		try pos.parseFen(Position.startpos);
	} else return error.UnknownCommand;

	const aux = tokens.next() orelse return .position;
	if (!std.mem.eql(u8, aux, "moves")) {
		return error.UnknownCommand;
	}

	pos.frc = frc;
	move_loop: while (tokens.next()) |token| {
		var i: usize = 0;
		var n: usize = 0;
		var list: movegen.Move.Scored.List = .{};

		n += list.genNoisy(&pos);
		n += list.genQuiet(&pos);
		while (i < n) : (i += 1) {
			const m = list.constSlice()[i].move;
			const s = m.toString(&pos);
			const l = m.toStringLen();
			if (!std.mem.eql(u8, token, s[0 .. l])) {
				continue;
			}

			pos.doMove(m) catch return error.UnknownCommand;
			continue :move_loop;
		} else return error.UnknownCommand;
	} else return .position;
}

pub fn parseCommand(command: []const u8, pool: *search.Pool) !Command {
	var tokens = std.mem.tokenizeAny(u8, command, &std.ascii.whitespace);
	const first = tokens.next() orelse return error.UnknownCommand;

	if (std.mem.eql(u8, first, "debug")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		return .debug;
	} else if (std.mem.eql(u8, first, "go")) {
		return parseGo(&tokens, pool);
	} else if (std.mem.eql(u8, first, "isready")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		pool.io.lockWriter();
		defer pool.io.unlockWriter();

		try pool.io.writer().print("readyok\n", .{});
		try pool.io.writer().flush();

		return .isready;
	} else if (std.mem.eql(u8, first, "position")) {
		return parsePosition(&tokens, pool);
	} else if (std.mem.eql(u8, first, "quit")) {
		return if (tokens.peek()) |_| error.UnknownCommand else .quit;
	} else if (std.mem.eql(u8, first, "setoption")) {
		return parseOption(&tokens, pool);
	} else if (std.mem.eql(u8, first, "stop")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		pool.stop();
		return .stop;
	} else if (std.mem.eql(u8, first, "uci")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		pool.io.lockWriter();
		defer pool.io.unlockWriter();

		try pool.io.writer().print("id author {s}\n", .{@import("root").author});
		try pool.io.writer().print("id name {s}\n", .{@import("root").name});

		try pool.io.writer().print("option name {s} type {s}\n", .{"Clear Hash", "button"});
		try pool.io.writer().print("option name {s} type {s} default {d} min {d} max {d}\n",
		    .{"Hash", "spin", 64, 1, 1 << 30});
		try pool.io.writer().print("option name {s} type {s} default {d} min {d} max {d}\n",
		    .{"Threads", "spin", 1, 1, 256});
		try pool.io.writer().print("option name {s} type {s} default {s}\n",
		    .{"UCI_Chess960", "check", "false"});

		try pool.io.writer().print("uciok\n", .{});
		try pool.io.writer().flush();

		return .uci;
	} else if (std.mem.eql(u8, first, "ucinewgame")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		try pool.reset();
		return .ucinewgame;
	} else return error.UnknownCommand;
}

pub fn loop() !void {
	const allocator = std.heap.page_allocator;

	var io = try types.Io.init(allocator, null, 16384, null, 16384);
	var tt = try transposition.Table.init(allocator, null);
	var pool = try search.Pool.init(allocator, null, false, &io, &tt);

	try pool.reset();
	try pool.tt.clear(pool.options.threads);

	defer io.deinit();
	defer tt.deinit();
	defer pool.deinit();

	const reader = io.reader();
	const writer = io.writer();

	while (reader.takeDelimiterInclusive('\n')) |read| {
		const comm = parseCommand(read, &pool) catch |err| sw: switch (err) {
			error.UnknownCommand => {
				try writer.print("Unknown command: '{s}'\n", .{read[0 .. read.len - 1]});
				try writer.flush();
				break :sw Command.none;
			},
			else => return err,
		};

		if (comm == .quit) {
			if (pool.searching) {
				pool.stop();
				pool.waitFinish();
			}
			break;
		}
	} else |err| return err;
}

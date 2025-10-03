const base = @import("base");
const std = @import("std");

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

const io = struct {
	const stdin = std.fs.File.stdin();
	const stdout = std.fs.File.stdout();

	var reader_buf = std.mem.zeroes([4096]u8);
	var writer_buf = std.mem.zeroes([4096]u8);

	var std_reader = stdin.reader(&reader_buf);
	var std_writer = stdout.writer(&writer_buf);

	const reader = &std_reader.interface;
	const writer = &std_writer.interface;
};

pub const options = struct {
	pub var frc = false;
	pub var hash: usize = 64;
	pub var threads: usize = 1;
	pub var overhead: u64 = 10;
};

pub var instance = std.mem.zeroInit(search.Instance, .{});

fn parseCommand(command: []const u8) !Command {
	var tokens = std.mem.tokenizeAny(u8, command, &std.ascii.whitespace);
	const first = tokens.next() orelse return error.UnknownCommand;

	if (std.mem.eql(u8, first, "debug")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		return .debug;
	} else if (std.mem.eql(u8, first, "go")) {
		return parseGo(&tokens);
	} else if (std.mem.eql(u8, first, "isready")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		try io.writer.print("readyok\n", .{});
		try io.writer.flush();
		return .isready;
	} else if (std.mem.eql(u8, first, "position")) {
		return parsePosition(&tokens);
	} else if (std.mem.eql(u8, first, "quit")) {
		return if (tokens.peek()) |_| error.UnknownCommand else .quit;
	} else if (std.mem.eql(u8, first, "setoption")) {
		return parseOption(&tokens);
	} else if (std.mem.eql(u8, first, "stop")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		@atomicStore(bool, &instance.options.is_searching, false, .monotonic);
		return .stop;
	} else if (std.mem.eql(u8, first, "uci")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		try io.writer.print("id author {s}\n", .{@import("root").author});
		try io.writer.print("id name {s}\n", .{@import("root").name});

		try io.writer.print("option name {s} type {s}\n", .{"Clear Hash", "button"});
		try io.writer.print("option name {s} type {s} default {d} min {d} max {d}\n",
		    .{"Hash", "spin", 64, 1, 1 << 38});
		try io.writer.print("option name {s} type {s} default {d} min {d} max {d}\n",
		    .{"Threads", "spin", 1, 1, 64});
		try io.writer.print("option name {s} type {s} default {s}\n",
		    .{"UCI_Chess960", "check", "false"});
		try io.writer.print("uciok\n", .{});
		try io.writer.flush();
		return .uci;
	} else if (std.mem.eql(u8, first, "ucinewgame")) {
		if (tokens.peek()) |_| {
			return error.UnknownCommand;
		}

		instance.reset();
		return .ucinewgame;
	} else return error.UnknownCommand;

	return error.UnknownCommand;
}

fn parseGo(tokens: *std.mem.TokenIterator(u8, .any)) !Command {
	const opt = &instance.options;
	opt.reset();
	errdefer opt.reset();

	while (tokens.next()) |token| {
		if (std.mem.eql(u8, token, "infinite")) {
			opt.reset();
			continue;
		}

		const aux = tokens.next() orelse return error.UnknownCommand;
		if (std.mem.eql(u8, token, "depth")) {
			opt.depth = std.fmt.parseUnsigned(search.Depth, aux, 10)
			  catch return error.UnknownCommand;
		} else if (std.mem.eql(u8, token, "movetime")) {
			opt.movetime = std.fmt.parseUnsigned(u64, aux, 10)
			  catch return error.UnknownCommand;
		} else if (std.mem.eql(u8, token, "nodes")) {
			opt.nodes = std.fmt.parseUnsigned(u64, aux, 10)
			  catch return error.UnknownCommand;
		} else if (std.mem.eql(u8, token, "winc")) {
			opt.incr.set(.white,
			  std.fmt.parseUnsigned(u64, aux, 10) catch return error.UnknownCommand);
		} else if (std.mem.eql(u8, token, "wtime")) {
			opt.time.set(.white,
			  std.fmt.parseUnsigned(u64, aux, 10) catch return error.UnknownCommand);
		} else if (std.mem.eql(u8, token, "binc")) {
			opt.incr.set(.black,
			  std.fmt.parseUnsigned(u64, aux, 10) catch return error.UnknownCommand);
		} else if (std.mem.eql(u8, token, "btime")) {
			opt.time.set(.black,
			  std.fmt.parseUnsigned(u64, aux, 10) catch return error.UnknownCommand);
		} else return error.UnknownCommand;
		opt.infinite = false;
	}

	if (!opt.infinite) {
		var timeset = false;
		opt.stop = std.math.maxInt(u64);

		if (opt.movetime) |movetime| {
			opt.stop = @min(opt.stop.?, opt.start + movetime - options.overhead);
			timeset = true;
		}

		const stm = instance.infos[0].pos.stm;
		if (opt.incr.get(stm) != null and opt.time.get(stm) != null) {
			const incr = opt.incr.get(stm).?;
			const time = opt.time.get(stm).?;

			opt.stop = @min(opt.stop.?,
			  opt.start + incr / 2 + time / 20 - options.overhead);
			timeset = true;
		}

		if (opt.stop.? <= opt.start) {
			opt.stop = if (timeset) opt.start + 1 else null;
		}
	}

	try instance.spawn();
	return .go;
}

fn parseOption(tokens: *std.mem.TokenIterator(u8, .any)) !Command {
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

		try transposition.table.clear();
	} else if (std.ascii.eqlIgnoreCase(name, "Hash")) {
		if (!std.mem.eql(u8, aux, "value")) {
			return error.UnknownCommand;
		}

		const value = tokens.next() orelse return error.UnknownCommand;
		options.hash = std.fmt.parseUnsigned(usize, value, 10)
		  catch return error.UnknownCommand;
		try transposition.table.alloc(options.hash);
	} else if (std.ascii.eqlIgnoreCase(name, "Threads")) {
		if (!std.mem.eql(u8, aux, "value")) {
			return error.UnknownCommand;
		}

		const value = tokens.next() orelse return error.UnknownCommand;
		options.threads = std.fmt.parseUnsigned(usize, value, 10)
		  catch return error.UnknownCommand;
		try instance.alloc(options.threads);
	} else if (std.ascii.eqlIgnoreCase(name, "UCI_Chess960")) {
		if (!std.mem.eql(u8, aux, "value")) {
			return error.UnknownCommand;
		}

		const value = tokens.next() orelse return error.UnknownCommand;
		options.frc = if (std.mem.eql(u8, value, "false")) false
		  else if (std.mem.eql(u8, value, "true")) true
		  else return error.UnknownCommand;
	} else return error.UnknownCommand;

	return .setoption;
}

fn parsePosition(tokens: *std.mem.TokenIterator(u8, .any)) !Command {
	var pos = std.mem.zeroInit(Position, .{});
	defer for (instance.infos) |*info| {
		const d_pos = &info.pos;
		const s_pos = &pos;
		@memcpy(d_pos[0 .. 1], s_pos[0 .. 1]);
	};

	errdefer pos.parseFen(Position.startpos)
	  catch std.debug.panic("invalid startpos", .{});

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

	move_loop: while (tokens.next()) |token| {
		var list: movegen.Move.Scored.List = .{};
		_ = list.genNoisy(&pos);
		_ = list.genQuiet(&pos);
		for (list.slice()) |sm| {
			const m = sm.move;
			const s = m.toString();
			const l = m.toStringLen();
			if (!std.mem.eql(u8, token, s[0 .. l])) {
				continue;
			}
			pos.doMove(m) catch return error.UnknownCommand;
			continue :move_loop;
		}
		return error.UnknownCommand;
	}

	return .position;
}

pub fn init() !void {
	_ = try parseCommand("setoption name Hash value 64");
	_ = try parseCommand("setoption name Threads value 1");
	_ = try parseCommand("setoption name UCI_Chess960 value false");
	_ = try parseCommand("setoption name Clear Hash");
	_ = try parseCommand("position startpos");
}

pub fn loop() !void {
	while (true) {
		const read = try io.reader.takeDelimiterExclusive('\n');
		const comm = parseCommand(read) catch |err| sw: switch (err) {
			error.UnknownCommand => {
				try io.writer.print("Unknown command: '{s}'\n", .{read});
				try io.writer.flush();
				break :sw Command.none;
			},
			else => return err,
		};

		if (comm == .quit) {
			if (@atomicLoad(bool, &instance.options.is_searching, .monotonic)) {
				@atomicStore(bool, &instance.options.is_searching, false, .monotonic);
				std.Thread.sleep(options.overhead * std.time.ns_per_ms);
			}
			break;
		}
	}
}

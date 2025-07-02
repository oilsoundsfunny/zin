const misc = @import("misc");
const std = @import("std");

const search = @import("search.zig");
const timeman = @import("timeman.zig");

const Command = enum {
	debug,
	go,
	none,
	position,
	quit,
	setoption,
	stop,
};

const Error = error {
	InvalidPosition,
	UnknownCommand,
};

const stdin  = std.io.getStdIn();
const stdout = std.io.getStdOut();

var buffered_inp = std.io.bufferedReader(stdin.reader());
var buffered_out = std.io.bufferedWriter(stdout.writer());

fn parseGo(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	timeman.depth = null;
	timeman.increment = @TypeOf(timeman.increment).initFill(null);
	timeman.movetime = null;
	timeman.time = @TypeOf(timeman.time).initFill(null);
	timeman.start = null;
	timeman.stop = null;

	while (tokens.next()) |token| {
		if (std.ascii.eqlIgnoreCase(token, "depth")) {
			const aux = tokens.next() orelse return error.UnknownCommand;
			timeman.depth = try std.fmt.parseUnsigned(search.Depth, aux, 10);
		} else if (std.ascii.eqlIgnoreCase(token, "movetime")) {
			const aux = tokens.next() orelse return error.UnknownCommand;
			timeman.movetime = try std.fmt.parseUnsigned(u64, aux, 10);
		} else if (std.ascii.eqlIgnoreCase(token, "winc")) {
			const aux = tokens.next() orelse return error.UnknownCommand;
			timeman.increment.set(.white, try std.fmt.parseUnsigned(u64, aux, 10));
		} else if (std.ascii.eqlIgnoreCase(token, "wtime")) {
			const aux = tokens.next() orelse return error.UnknownCommand;
			timeman.time.set(.white, try std.fmt.parseUnsigned(u64, aux, 10));
		} else if (std.ascii.eqlIgnoreCase(token, "binc")) {
			const aux = tokens.next() orelse return error.UnknownCommand;
			timeman.increment.set(.black, try std.fmt.parseUnsigned(u64, aux, 10));
		} else if (std.ascii.eqlIgnoreCase(token, "btime")) {
			const aux = tokens.next() orelse return error.UnknownCommand;
			timeman.time.set(.black, try std.fmt.parseUnsigned(u64, aux, 10));
		} else return error.UnknownCommand;
	}
}

fn parseOption(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const first = tokens.next() orelse return error.UnknownCommand;
	if (!std.ascii.eqlIgnoreCase(first, "name")) {
		return error.UnknownCommand;
	}
}

fn parsePosition(tokens: *std.mem.TokenIterator(u8, .any)) !void {
	const first = tokens.next() orelse return error.UnknownCommand;

	if (std.ascii.eqlIgnoreCase(first, "fen")) {
	} else if (std.ascii.eqlIgnoreCase(first, "kiwipete")) {
	} else if (std.ascii.eqlIgnoreCase(first, "startpos")) {
	} else return error.UnknownCommand;
}

pub fn parseCommand(tokens: *std.mem.TokenIterator(u8, .any)) !Command {
	const first = tokens.next() orelse return .none;

	if (std.ascii.eqlIgnoreCase(first, "go")) {
		try parseGo(tokens);
	} else if (std.ascii.eqlIgnoreCase(first, "position")) {
		try parsePosition(tokens);
	} else if (std.ascii.eqlIgnoreCase(first, "quit")) {
		return if (tokens.peek()) |_| error.UnknownCommand else .quit;
	} else if (std.ascii.eqlIgnoreCase(first, "setoption")) {
		try parseOption(tokens);
	} else if (std.ascii.eqlIgnoreCase(first, "stop")) {
		return if (tokens.peek()) |_| error.UnknownCommand else .stop;
	}
	return error.UnknownCommand;
}

pub fn loop() !void {
	while (true) {
		const read = try buffered_inp.reader().readUntilDelimiter(buffered_inp.buf[0 ..], '\n');
		var tokens = std.mem.tokenizeAny(u8, read, &.{'\r', '\t', ' '});

		const command = parseCommand(&tokens) catch Command.none;

		if (command == .quit) {
			break;
		}
	}
}

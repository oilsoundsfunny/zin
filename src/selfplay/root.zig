const base = @import("base");
const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");

const Player = @import("Player.zig");

pub const author = "oilsoundsfunny";
pub const name = "selfplay";

pub const io = struct {
	var inp: std.fs.File = undefined;
	var out: std.fs.File = undefined;

	var reader_buf = std.mem.zeroes([4096]u8);
	var writer_buf = std.mem.zeroes([4096]u8);

	var std_reader: std.fs.File.Reader = undefined;
	var std_writer: std.fs.File.Writer = undefined;

	pub var reader: *std.Io.Reader = undefined;
	pub var writer: *std.Io.Writer = undefined;

	fn deinit() void {
		inp.close();
		out.close();
	}

	fn init(inp_path: []const u8, out_path: []const u8) !void {
		const cwd = std.fs.cwd();
		inp = try cwd.openFile(inp_path, .{});
		out = try cwd.createFile(out_path, .{});

		std_reader = inp.reader(&reader_buf);
		std_writer = out.writer(&writer_buf);

		reader = &std_reader.interface;
		writer = &std_writer.interface;
	}
};

pub fn main() !void {
	try base.init();
	defer base.deinit();

	try engine.init();
	defer engine.deinit();

	const args = try std.process.argsAlloc(base.heap.allocator);
	var i: usize = 1;

	var book_path: ?[]const u8 = null;
	var games: ?u64 = null;
	var nodes: ?u64 = null;
	var threads: ?usize = null;

	while (i < args.len) : (i += 1) {
		const arg = args[i];

		if (std.mem.eql(u8, arg, "--book")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (book_path) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			book_path = args[i];
		} else if (std.mem.eql(u8, arg, "--games")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (games) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			games = try std.fmt.parseUnsigned(u64, args[i], 10);
		} else if (std.mem.eql(u8, arg, "--nodes")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (nodes) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			nodes = try std.fmt.parseUnsigned(u64, args[i], 10);
		} else if (std.mem.eql(u8, arg, "--threads")) {
			i += 1;
			if (i > args.len) {
				std.process.fatal("expected arg after '{s}'", .{arg});
			}

			if (threads) |_| {
				std.process.fatal("duplicated arg '{s}'", .{arg});
			}
			threads = try std.fmt.parseUnsigned(usize, args[i], 10);
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	try io.init(book_path orelse std.process.fatal("missing arg '--book'", .{}), "baseline.data");
	defer io.deinit();

	var tourney = try Player.Tourney.alloc(threads orelse 1, games,
	  nodes orelse std.process.fatal("missing arg '--nodes'", .{}));
	while (true) {
		try tourney.round();
		if (tourney.max) |lim| {
			if (tourney.played >= lim) {
				break;
			}
		}
	}
}

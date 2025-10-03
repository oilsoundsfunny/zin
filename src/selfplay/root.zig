const base = @import("base");
const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");

const Player = @import("Player.zig");

pub const author = "oilsoundsfunny";
pub const name = "selfplay";

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
		} else std.process.fatal("unknown arg '{s}'", .{arg});
	}

	const book = try std.fs
	  .cwd()
	  .openFile(book_path orelse std.process.fatal("missing arg '--book'", .{}), .{});
	defer book.close();

	var tourney = try Player.Tourney.alloc(4, games,
	  nodes orelse std.process.fatal("missing arg '--nodes'", .{}));
	while (tourney.round(book)) {
	} else |_| return;
}

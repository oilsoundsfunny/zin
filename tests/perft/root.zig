const base = @import("base");
const bitboard = @import("bitboard");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");

pub const Result = struct {
	fen:	[]const u8,
	nodes:	[6]usize,
};

const io = struct {
	const stdin = std.fs.File.stdin();
	const stdout = std.fs.File.stdout();

	const reader = &std_reader.interface;
	const writer = &std_writer.interface;

	var reader_buf = std.mem.zeroes([4096]u8);
	var writer_buf = std.mem.zeroes([4096]u8);

	var std_reader = stdin.reader(&reader_buf);
	var std_writer = stdout.writer(&writer_buf);
};

fn divRecursive(pos: *engine.Position, depth: isize, recur: isize) usize {
	if (depth <= recur) {
		return 1;
	}

	var ml: engine.movegen.Move.Scored.List = .{};
	var sum: usize = 0;
	_ = ml.genNoisy(pos);
	_ = ml.genQuiet(pos);

	for (ml.slice()) |sm| {
		const m = sm.move;
		pos.doMove(m) catch continue;
		defer pos.undoMove();

		const this = divRecursive(pos, depth, recur + 1);
		sum += this;

		if (recur == 0) {
			const s = m.toString();
			const l = m.toStringLen();
			std.debug.print("{s}:\t{d}\n", .{s[0 .. l], this});
		}
	}

	if (recur == 0) {
		std.debug.print("perft {d}: {d}\n", .{depth, sum});
	}
	return sum;
}

pub fn div(pos: *engine.Position, depth: isize) usize {
	return divRecursive(pos, depth, 0);
}

test {
	_ = @import("standard.zig");
	_ = @import("frc.zig");
}

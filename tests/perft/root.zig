const bitboard = @import("bitboard");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

pub const Result = struct {
	fen:	[]const u8,
	nodes:	[6]usize,
};

fn divRecursive(comptime root: bool, pos: *engine.Position, depth: engine.search.Depth) usize {
	if (depth <= 0) {
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

		const this = divRecursive(false, pos, depth - 1);
		sum += this;

		if (root) {
			const s = m.toString(pos);
			const l = m.toStringLen();
			std.debug.print("{s}:\t{d}\n", .{s[0 .. l], this});
		}
	}

	return sum;
}

pub fn div(pos: *engine.Position, depth: isize) !usize {
	var timer = try std.time.Timer.start();

	timer.reset();
	const nodes = divRecursive(true, pos, depth);
	const time = timer.lap();
	const nps = nodes * std.time.ns_per_s / time;

	std.debug.print("info perft depth {d} nodes {d} nps {d}\n", .{depth, nodes, nps});
	return nodes;
}

test {
	_ = @import("standard.zig");
	_ = @import("frc.zig");
}

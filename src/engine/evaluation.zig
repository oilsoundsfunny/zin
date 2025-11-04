const base = @import("base");
const bitboard = @import("bitboard");
const nnue = @import("nnue");
const params = @import("params");
const std = @import("std");

const Position = @import("Position.zig");

pub const score = struct {
	pub const Int = base.defs.score.Int;

	pub const none = base.defs.score.none;
	pub const unit = base.defs.score.unit;

	pub const win  = base.defs.score.win;
	pub const draw = base.defs.score.draw;
	pub const lose = base.defs.score.lose;

	pub const tbwin  = base.defs.score.tbwin;
	pub const tblose = base.defs.score.tblose;

	pub const centipawns = base.defs.score.centipawns;

	pub fn fromPosition(pos: *const Position) Int {
		var ev = nnue.net.default.infer(pos);
		ev *= 128 - pos.ss.top().rule50;
		ev = @divTrunc(ev, 128);
		ev = std.math.clamp(ev, score.tblose + 1, score.tbwin - 1);
		return ev;
	}
};

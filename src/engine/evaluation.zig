const base = @import("base");
const bitboard = @import("bitboard");
const nnue = @import("nnue");
const params = @import("params");
const std = @import("std");

const Position = @import("Position.zig");

const Features = struct {
};

const phase = struct {
	const init_max
	  = @as(comptime_int, params.evaluation.ptsc.getPtrConst(.pawn).avg()) * 16
	  + @as(comptime_int, params.evaluation.ptsc.getPtrConst(.knight).avg()) * 4
	  + @as(comptime_int, params.evaluation.ptsc.getPtrConst(.bishop).avg()) * 4
	  + @as(comptime_int, params.evaluation.ptsc.getPtrConst(.rook).avg())  * 4
	  + @as(comptime_int, params.evaluation.ptsc.getPtrConst(.queen).avg()) * 2;
	const min = init_max *  1 / 16;
	const max = init_max * 15 / 16;

	fn fromPosition(pos: *const Position) score.Int {
		const ptsc: Pair = .{
			.mg = pos.ss.top().ptsc.getPtrConst(.white).mg
			  + pos.ss.top().ptsc.getPtrConst(.black).mg,
			.eg = pos.ss.top().ptsc.getPtrConst(.white).eg
			  + pos.ss.top().ptsc.getPtrConst(.black).eg,
		};
		const from_pos = ptsc.avg();
		const clamped: isize = std.math.clamp(from_pos, min, max);
		const m = (clamped - min) * score.unit;
		const d = @divTrunc(m, max - min);
		return @intCast(d);
	}
};

pub const Pair = extern struct {
	mg:	score.Int,
	eg:	score.Int,

	pub fn avg(self: Pair) score.Int {
		return self.taper(score.unit);
	}

	pub fn taper(self: Pair, p: score.Int) score.Int {
		const mg = @as(isize, self.mg) * @as(isize, p);
		const eg = @as(isize, self.eg) * @as(isize, score.unit - p);
		return @intCast(@divTrunc(mg + eg, score.unit));
	}
};

pub const score = struct {
	pub const Int = base.defs.score.Int;

	pub const none = base.defs.score.none;
	pub const unit = base.defs.score.unit;

	pub const win  = base.defs.score.win;
	pub const draw = base.defs.score.draw;
	pub const lose = base.defs.score.lose;

	pub const tbwin  = base.defs.score.tbwin;
	pub const tblose = base.defs.score.tblose;

	pub const fromCentipawns = base.defs.score.fromCentipawns;
	pub const toCentipawns = base.defs.score.toCentipawns;

	pub fn fromPosition(pos: *const Position) Int {
		var ev = nnue.net.default.infer(pos);
		// ev *= 100 - pos.ss.top().rule50;
		// ev = @divTrunc(ev, 100);
		ev = std.math.clamp(ev, score.tblose, score.tbwin);
		return ev;
	}
};

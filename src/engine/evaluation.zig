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

pub const Pair = struct {
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
	const min = std.math.minInt(i16);
	const max = std.math.maxInt(i16);

	pub const Int = isize;

	pub const none = min;
	pub const unit = 256;

	pub const win  = 0 + max;
	pub const draw = 0;
	pub const lose = 0 - max;

	pub const tbwin  = 0 + (max - 247);
	pub const tblose = 0 - (max - 247);

	pub fn fromCentipawns(c: Int) Int {
		const i = std.math.clamp(c, lose, win);
		const m = i * unit;
		const d = @divTrunc(m, 100);
		return @intCast(d);
	}

	pub fn toCentipawns(s: Int) Int {
		const i = std.math.clamp(s, lose, win);
		const m = i * 100;
		const d = @divTrunc(m, unit);
		return @intCast(d);
	}

	pub fn fromPosition(pos: *const Position) Int {
		// const inferred = nnue.net.infer(&pos.ss.top().accumulators);
		// return std.math.clamp(inferred, score.tblose, score.tbwin);

		const stm = pos.stm;
		const psqt = &pos.ss.top().psqt;
		const ptsc = &pos.ss.top().ptsc;

		const accumulator: Pair = .{
			.mg = psqt.getPtrConst(stm).mg - psqt.getPtrConst(stm.flip()).mg
			 + ptsc.getPtrConst(stm).mg - ptsc.getPtrConst(stm.flip()).mg,
			.eg = psqt.getPtrConst(stm).eg - psqt.getPtrConst(stm.flip()).eg
			 + ptsc.getPtrConst(stm).eg - ptsc.getPtrConst(stm.flip()).eg,
		};
		const game_phase = phase.fromPosition(pos);

		var ev = accumulator.taper(game_phase) + 16;
		ev *= 100 - pos.ss.top().rule50;
		ev = @divTrunc(ev, 100);
		ev = std.math.clamp(ev, score.tblose, score.tbwin);
		return ev;
	}
};

const misc = @import("misc");
const params = @import("params");
const std = @import("std");

const Position = @import("Position.zig");
const transposition = @import("transposition.zig");

pub const Pair = struct {
	mg:	Int,
	eg:	Int,

	pub const Int = score.Int;

	pub const phase = struct {
		pub const max = params.pts.get(.pawn).avg() * 16
		  + params.pts.get(.knight).avg() * 4
		  + params.pts.get(.bishop).avg() * 4
		  + params.pts.get(.rook).avg()  * 4
		  + params.pts.get(.queen).avg() * 2;
		pub const min = 0;

		pub fn fromPosition(pos: Position) Int {
			return pos.ss.top().pts.avg();
		}

		pub fn fromScore(s: Int) Int {
			const clamped: isize = std.math.clamp(s, min, max);
			return @intCast(@divTrunc(clamped * score.pawn, max));
		}
	};

	pub fn taper(self: Pair, p: Int) Int {
		const mg = @as(isize, self.mg) * @as(isize, p);
		const eg = @as(isize, self.eg) * @as(isize, score.pawn - p);
		return @intCast(@divTrunc(mg + eg, score.pawn));
	}

	pub fn avg(self: Pair) Int {
		return self.taper(score.pawn / 2);
	}
};

pub const PawnFeatures = struct {
	passers:	std.EnumArray(misc.types.Color, misc.types.BitBoard),

	blocked:	std.EnumArray(misc.types.Color, misc.types.BitBoard),
	isolated:	std.EnumArray(misc.types.Color, misc.types.BitBoard),

	doubled:	std.EnumArray(misc.types.Color, misc.types.BitBoard),
	tripled:	std.EnumArray(misc.types.Color, misc.types.BitBoard),

	pub fn fromPosition(pos: Position) PawnFeatures {
		const fetch = transposition.pawn_table.fetch(pos.ss.top().pawn_key);
		const tte = fetch[0];
		const hit = fetch[1];
		if (hit) {
			return tte.*;
		}

		const pawns = std.EnumArray(misc.types.Color, misc.types.BitBoard).init(.{
			.white = pos.pieceOcc(.w_pawn),
			.black = pos.pieceOcc(.b_pawn),
		});
		var pft = std.mem.zeroInit(PawnFeatures, .{});

		for (misc.types.Color.values) |c| {
			const p = pawns.get(c);

			for (misc.types.File.values) |f| {
				const file_pawns = p.bitAnd(f.bb());
				switch (file_pawns.popCount()) {
					0 => continue,
					else => |cnt| {
						if (cnt >= 2) {
							pft.doubled.set(c, pft.doubled.get(c).bitOr(file_pawns));
						}
						if (cnt >= 3) {
							pft.tripled.set(c, pft.tripled.get(c).bitOr(file_pawns));
						}
					},
				}

				var isolated = false;
				if (f.shift(.west)) |wf| {
					isolated = p.bitAnd(wf.bb()) == .nil;
				}
				if (f.shift(.east)) |ef| {
					isolated = p.bitAnd(ef.bb()) == .nil;
				}
				if (isolated) {
					pft.isolated.set(c, pft.isolated.get(c).bitOr(file_pawns));
				}
			}
		}

		tte.* = .{
			.pft = pft,
			.key = pos.ss.top().pawn_key,
		};
		return pft;
	}
};

pub const Features = struct {
	pawn_ft:	PawnFeatures,

	piece_atk:	std.EnumArray(misc.types.Piece, misc.types.BitBoard),
	mobility_area:	std.EnumArray(misc.types.Color, misc.types.BitBoard),

	king_area:	std.EnumArray(misc.types.Color, misc.types.BitBoard),
	king_atker_cnt:	std.EnumArray(misc.types.Color, score.Int),
	king_atker_mat:	std.EnumArray(misc.types.Color, score.Int),
};

pub const score = struct {
	pub const win  = 0 + max;
	pub const draw = 0;
	pub const lose = 0 - max;

	pub const nil  = min;
	pub const pawn = 256;

	pub const Int = i16;

	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);

	pub fn centipawns(s: Int) Int {
		const i: isize = s;
		const d = @divTrunc(i * 100, pawn);
		return @intCast(d);
	}

	pub fn fromCentipawns(cp: Int) Int {
		const i: isize = cp;
		const d = @divTrunc(i * pawn, 100);
		return @intCast(d);
	}

	pub fn fromPosition(pos: Position) Int {
		var pair = Pair {
			.mg = pos.ss.top().pts.mg + pos.ss.top().psqt.mg,
			.eg = pos.ss.top().pts.eg + pos.ss.top().psqt.eg,
		};

		var ev: isize = pair.avg();
		ev *= 100 - pos.ss.top().rule50;
		ev  = @divTrunc(ev, 100);
		return @intCast(ev);
	}
};

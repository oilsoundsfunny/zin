const misc = @import("misc");
const std = @import("std");

const Position = @import("Position.zig");
const transposition = @import("transposition.zig");

pub const Score = enum(i16) {
	win  = 0 + 32767,
	draw = 0,
	lose = 0 - 32767,

	nil  = -32768,
	pawn = 256,

	_,

	pub const Int = std.meta.Tag(Score);

	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);

	pub fn centipawns(self: Score) Int {
		const s: isize = self.int();
		const d = @divTrunc(s * 100, Score.pawn.int());
		return @intCast(d);
	}

	pub fn int(self: Score) Int {
		return @intFromEnum(self);
	}

	pub fn fromCentipawns(cp: Int) Score {
		const c: isize = cp;
		const d = @divTrunc(c * Score.pawn.int(), 100);
		return fromInt(@intCast(d));
	}

	pub fn fromInt(i: Int) Score {
		return @enumFromInt(i);
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
	king_atker_cnt:	std.EnumArray(misc.types.Color, Score.Int),
	king_atker_mat:	std.EnumArray(misc.types.Color, Score.Int),
};

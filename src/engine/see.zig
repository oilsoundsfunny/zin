// This program is free software: you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
// even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.

// You should have received a copy of the GNU General Public License along with this program. If
// not, see <https://www.gnu.org/licenses/>.

const bitboard = @import("bitboard");
const std = @import("std");
const types = @import("types");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const Position = @import("Position.zig");

pub fn func(pos: *const Position, move: movegen.Move, min: evaluation.score.Int) bool {
	if (move.flag != .none) {
		return true;
	}

	const s = move.src;
	const d = move.dst;

	const sp = pos.getSquare(s);
	const dp = pos.getSquare(d);

	var v = dp.score() - min;
	if (v < 0) {
		return false;
	}

	v = sp.score() - v;
	if (v <= 0) {
		return true;
	}

	const diag = pos.ptypeOcc(.queen).bwo(pos.ptypeOcc(.bishop));
	const line = pos.ptypeOcc(.queen).bwo(pos.ptypeOcc(.rook));

	var ret = true;
	var stm = pos.stm;
	var occ = pos.bothOcc()
	  .bwx(s.toSet())
	  .bwx(d.toSet());
	var atkers = types.Square.Set.none
	  .bwo(bitboard.pAtk(d.toSet(), .white).bwa(pos.pieceOcc(.b_pawn)))
	  .bwo(bitboard.pAtk(d.toSet(), .black).bwa(pos.pieceOcc(.w_pawn)))
	  .bwo(bitboard.nAtk(d).bwa(pos.ptypeOcc(.knight)))
	  .bwo(bitboard.kAtk(d).bwa(pos.ptypeOcc(.king)))
	  .bwo(bitboard.bAtk(d, occ).bwa(diag))
	  .bwo(bitboard.rAtk(d, occ).bwa(line));

	while (true) {
		atkers.popOther(occ.flip());
		stm = stm.flip();

		const ours = atkers.bwa(pos.colorOcc(stm));
		ret = if (ours == .none) break else !ret;

		var least = ours.bwa(pos.ptypeOcc(.pawn));
		if (least != .none) {
			v = types.Ptype.pawn.score() - v;
			if (v < @intFromBool(ret)) {
				break;
			}

			occ.popOther(least.getLow());
			atkers.setOther(bitboard.bAtk(d, occ).bwa(diag));
			continue;
		}

		least = ours.bwa(pos.ptypeOcc(.knight));
		if (least != .none) {
			v = types.Ptype.knight.score() - v;
			if (v < @intFromBool(ret)) {
				break;
			}

			occ.popOther(least.getLow());
			continue;
		}

		least = ours.bwa(pos.ptypeOcc(.bishop));
		if (least != .none) {
			v = types.Ptype.bishop.score() - v;
			if (v < @intFromBool(ret)) {
				break;
			}

			occ.popOther(least.getLow());
			atkers.setOther(bitboard.bAtk(d, occ).bwa(diag));
			continue;
		}

		least = ours.bwa(pos.ptypeOcc(.rook));
		if (least != .none) {
			v = types.Ptype.rook.score() - v;
			if (v < @intFromBool(ret)) {
				break;
			}

			occ.popOther(least.getLow());
			atkers.setOther(bitboard.rAtk(d, occ).bwa(line));
			continue;
		}

		least = ours.bwa(pos.ptypeOcc(.queen));
		if (least != .none) {
			v = types.Ptype.queen.score() - v;
			if (v < @intFromBool(ret)) {
				break;
			}

			occ.popOther(least.getLow());
			atkers.setOther(bitboard.bAtk(d, occ).bwa(diag));
			atkers.setOther(bitboard.rAtk(d, occ).bwa(line));
			continue;
		}

		ret = if (atkers.bwx(ours) == .none) ret else !ret;
		break;
	}

	return ret;
}

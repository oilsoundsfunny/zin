// This program is free software: you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.

// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
// even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.

// You should have received a copy of the GNU General Public License along with this program. If
// not, see <https://www.gnu.org/licenses/>.

const bitboard = @import("bitboard");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");

pub const Mode = enum {
    ordering,
    pruning,
};

fn ptypeValue(comptime mode: Mode, p: types.Ptype) evaluation.score.Int {
    return switch (p) {
        .king => evaluation.score.draw,
        inline else => |e| @field(params.values, "see_" ++ @tagName(mode) ++ "_" ++ @tagName(e)),
    };
}

fn pieceValue(comptime mode: Mode, p: types.Piece) evaluation.score.Int {
    return if (p != .none) ptypeValue(mode, p.ptype()) else evaluation.score.draw;
}

pub fn func(
    comptime mode: Mode,
    pos: *const Board.Position,
    move: movegen.Move,
    min: evaluation.score.Int,
) bool {
    if (move.flag == .none or move.flag == .torped) {
        return min <= evaluation.score.draw;
    } else if (move.flag != .noisy) {
        return true;
    }

    const s = move.src;
    const d = move.dst;

    const sp = pos.getSquare(s);
    const dp = pos.getSquare(d);

    var v = pieceValue(mode, dp) - min;
    if (v < 0) {
        return false;
    }

    v = pieceValue(mode, sp) - v;
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
            v = ptypeValue(mode, .pawn) - v;
            if (v < @intFromBool(ret)) {
                break;
            }

            occ.popOther(least.getLow());
            atkers.setOther(bitboard.bAtk(d, occ).bwa(diag));
            continue;
        }

        least = ours.bwa(pos.ptypeOcc(.knight));
        if (least != .none) {
            v = ptypeValue(mode, .knight) - v;
            if (v < @intFromBool(ret)) {
                break;
            }

            occ.popOther(least.getLow());
            continue;
        }

        least = ours.bwa(pos.ptypeOcc(.bishop));
        if (least != .none) {
            v = ptypeValue(mode, .bishop) - v;
            if (v < @intFromBool(ret)) {
                break;
            }

            occ.popOther(least.getLow());
            atkers.setOther(bitboard.bAtk(d, occ).bwa(diag));
            continue;
        }

        least = ours.bwa(pos.ptypeOcc(.rook));
        if (least != .none) {
            v = ptypeValue(mode, .rook) - v;
            if (v < @intFromBool(ret)) {
                break;
            }

            occ.popOther(least.getLow());
            atkers.setOther(bitboard.rAtk(d, occ).bwa(line));
            continue;
        }

        least = ours.bwa(pos.ptypeOcc(.queen));
        if (least != .none) {
            v = ptypeValue(mode, .queen) - v;
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

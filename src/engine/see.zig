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

fn ptypeValue(p: types.Ptype) evaluation.score.Int {
    return switch (p) {
        .pawn => params.values.see_pawn_value,
        .knight => params.values.see_knight_value,
        .bishop => params.values.see_bishop_value,
        .rook => params.values.see_rook_value,
        .queen => params.values.see_queen_value,
        else => evaluation.score.draw,
    };
}

fn pieceValue(p: types.Piece) evaluation.score.Int {
    return ptypeValue(p.ptype());
}

pub fn func(pos: *const Board.Position, move: movegen.Move, min: evaluation.score.Int) bool {
    if (move.flag != .none) {
        return true;
    }

    const s = move.src;
    const d = move.dst;

    const sp = pos.getSquare(s);
    const dp = pos.getSquare(d);

    var v = pieceValue(dp) - min;
    if (v < 0) {
        return false;
    }

    v = pieceValue(sp) - v;
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
            v = ptypeValue(.pawn) - v;
            if (v < @intFromBool(ret)) {
                break;
            }

            occ.popOther(least.getLow());
            atkers.setOther(bitboard.bAtk(d, occ).bwa(diag));
            continue;
        }

        least = ours.bwa(pos.ptypeOcc(.knight));
        if (least != .none) {
            v = ptypeValue(.knight) - v;
            if (v < @intFromBool(ret)) {
                break;
            }

            occ.popOther(least.getLow());
            continue;
        }

        least = ours.bwa(pos.ptypeOcc(.bishop));
        if (least != .none) {
            v = ptypeValue(.bishop) - v;
            if (v < @intFromBool(ret)) {
                break;
            }

            occ.popOther(least.getLow());
            atkers.setOther(bitboard.bAtk(d, occ).bwa(diag));
            continue;
        }

        least = ours.bwa(pos.ptypeOcc(.rook));
        if (least != .none) {
            v = ptypeValue(.rook) - v;
            if (v < @intFromBool(ret)) {
                break;
            }

            occ.popOther(least.getLow());
            atkers.setOther(bitboard.rAtk(d, occ).bwa(line));
            continue;
        }

        least = ours.bwa(pos.ptypeOcc(.queen));
        if (least != .none) {
            v = ptypeValue(.queen) - v;
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

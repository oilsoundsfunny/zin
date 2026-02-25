const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Accumulator = @import("Accumulator.zig");
const network = @import("network.zig");

const FinnyTable = @This();

accs: std.EnumArray(types.Color, [network.Default.ibn]Accumulator) = .initFill(@splat(.{})),
occs: std.EnumArray(types.Color, [network.Default.ibn]Occupancy) = .initFill(@splat(.{})),

const Occupancy = struct {
    by_ptype: std.EnumArray(types.Ptype, types.Square.Set) = .initFill(.none),
    by_color: std.EnumArray(types.Color, types.Square.Set) = .initFill(.none),

    fn init(pos: *const engine.Board.Position, c: types.Color) Occupancy {
        var occ: Occupancy = .{ .by_ptype = pos.by_ptype, .by_color = pos.by_color };
        if (c == .black) {
            std.mem.swap(
                types.Square.Set,
                occ.by_color.getPtr(.white),
                occ.by_color.getPtr(.black),
            );
        }

        const king: Accumulator.Feature = .init(.init(.king, c), pos.kingSquare(c));
        for (types.Ptype.values) |pt| {
            const p = occ.by_ptype.getPtr(pt);
            p.* = king.transform(p.*);
        }
        for (types.Color.values) |pc| {
            const p = occ.by_color.getPtr(pc);
            p.* = king.transform(p.*);
        }

        return occ;
    }

    fn pieceOcc(self: *const Occupancy, p: types.Piece) types.Square.Set {
        const t = self.by_ptype.getPtrConst(p.ptype()).*;
        const c = self.by_color.getPtrConst(p.color()).*;
        return .bwa(t, c);
    }
};

pub fn init(pos: *const engine.Board.Position) FinnyTable {
    const kings: std.EnumArray(types.Color, Accumulator.Feature) = .init(.{
        .white = .init(.w_king, pos.kingSquare(.white)),
        .black = .init(.b_king, pos.kingSquare(.black)),
    });
    const buckets: std.EnumArray(types.Color, usize) = .init(.{
        .white = kings.get(.white).bucket(),
        .black = kings.get(.black).bucket(),
    });

    var arrays: std.EnumArray(types.Color, types.BoundedArray(usize, null, 32)) = .initFill(.{});
    var finny_table: FinnyTable = .{};

    for (types.Color.values) |c| {
        const bucket = buckets.get(c);
        const acc = &finny_table.accs.getPtr(c)[bucket];
        const occ = &finny_table.occs.getPtr(c)[bucket];

        occ.* = .init(pos, c);
        for (types.Piece.values) |p| {
            var b = occ.pieceOcc(p);
            while (b.lowSquare()) |s| : (b.popLow()) {
                const ft: Accumulator.Feature = .{ .piece = p, .square = s };
                arrays.getPtr(c).pushUnchecked(ft.index());
            }
        }
        acc.update(&network.verbatim.l0w[bucket], arrays.getPtrConst(c), null);
    }

    return finny_table;
}

pub fn load(
    self: *FinnyTable,
    c: types.Color,
    perspective: *Accumulator.Perspective,
    position: *const engine.Board.Position,
) void {
    const onboard_king: Accumulator.Feature = .{
        .piece = .init(.king, c),
        .square = position.kingSquare(c),
    };
    const bucket = onboard_king.bucket();

    const wgts = &network.verbatim.l0w[bucket];
    const occs = &self.occs.getPtr(c)[bucket];
    const onboard_occs: Occupancy = .init(position, c);

    var add_array: types.BoundedArray(usize, null, 32) = .{};
    var sub_array: types.BoundedArray(usize, null, 32) = .{};

    for (types.Piece.values) |p| {
        const cached = occs.pieceOcc(p);
        const onboard = onboard_occs.pieceOcc(p);
        const unique: types.Square.Set = .bwx(cached, onboard);

        var add_b = unique.bwa(onboard);
        while (add_b.lowSquare()) |s| : (add_b.popLow()) {
            const ft: Accumulator.Feature = .init(p, s);
            add_array.pushUnchecked(ft.index());
        }

        var sub_b = unique.bwa(cached);
        while (sub_b.lowSquare()) |s| : (sub_b.popLow()) {
            const ft: Accumulator.Feature = .init(p, s);
            sub_array.pushUnchecked(ft.index());
        }
    }

    self.occs.getPtr(c)[bucket] = onboard_occs;
    self.accs.getPtr(c)[bucket].update(wgts, &add_array, &sub_array);

    perspective.accs.set(c, self.accs.getPtrConst(c)[bucket]);
    perspective.dirty.set(c, false);
}

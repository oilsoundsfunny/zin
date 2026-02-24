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

    fn init(pos: *const engine.Board.Position) Occupancy {
        return .{ .by_ptype = pos.by_ptype, .by_color = pos.by_color };
    }

    fn pieceOcc(self: *const Occupancy, p: types.Piece) types.Square.Set {
        const t = self.by_ptype.getPtrConst(p.ptype()).*;
        const c = self.by_color.getPtrConst(p.color()).*;
        return .bwa(t, c);
    }
};

pub fn init(pos: *const engine.Board.Position) FinnyTable {
    const kings: std.EnumArray(types.Color, types.Square) = .init(.{
        .white = pos.kingSquare(.white),
        .black = pos.kingSquare(.black),
    });
    const buckets = network.Default.buckets(kings);

    var w_arr: types.BoundedArray(usize, null, 32) = .{};
    var b_arr: types.BoundedArray(usize, null, 32) = .{};
    var finny_table: FinnyTable = .{};

    for (types.Piece.values) |p| {
        var b = pos.pieceOcc(p);
        while (b.lowSquare()) |s| : (b.popLow()) {
            const indices = network.Default.indices(kings, .{ .piece = p, .square = s });
            w_arr.pushUnchecked(indices.get(.white));
            b_arr.pushUnchecked(indices.get(.black));
        }
    }

    finny_table.accs.getPtr(.white)[buckets.get(.white)]
        .update(&network.verbatim.l0w[buckets.get(.white)], &w_arr, null);
    finny_table.accs.getPtr(.black)[buckets.get(.black)]
        .update(&network.verbatim.l0w[buckets.get(.black)], &b_arr, null);
    finny_table.occs.getPtr(.white)[buckets.get(.white)] = .init(pos);
    finny_table.occs.getPtr(.black)[buckets.get(.black)] = .init(pos);
    return finny_table;
}

pub fn load(
    self: *FinnyTable,
    c: types.Color,
    perspective: *Accumulator.Perspective,
    position: *const engine.Board.Position,
) void {
    const kings: std.EnumArray(types.Color, types.Square) = .init(.{
        .white = position.kingSquare(.white),
        .black = position.kingSquare(.black),
    });
    const bucket = network.Default.buckets(kings).get(c);

    const wgts = &network.verbatim.l0w[bucket];
    const occs = &self.occs.getPtrConst(c)[bucket];

    const hm = blk: {
        const cached_king = occs.pieceOcc(.init(.king, c)).lowSquare() orelse
            std.debug.panic("king not found", .{});
        const cached_hm = switch (cached_king.file()) {
            .file_a, .file_b, .file_c, .file_d => false,
            else => true,
        };
        const onboard_hm = switch (kings.get(c).file()) {
            .file_a, .file_b, .file_c, .file_d => false,
            else => true,
        };
        break :blk cached_hm != onboard_hm;
    };

    var add_array: types.BoundedArray(usize, null, 32) = .{};
    var sub_array: types.BoundedArray(usize, null, 32) = .{};

    for (types.Piece.values) |p| {
        const cached = if (hm) occs.pieceOcc(p).flipFile() else occs.pieceOcc(p);
        const onboard = position.pieceOcc(p);
        const unique: types.Square.Set = .bwx(cached, onboard);

        var add_b = unique.bwa(onboard);
        while (add_b.lowSquare()) |s| : (add_b.popLow()) {
            const i = network.Default.indices(kings, .{ .piece = p, .square = s }).get(c);
            add_array.pushUnchecked(i);
        }

        var sub_b = unique.bwa(cached);
        while (sub_b.lowSquare()) |s| : (sub_b.popLow()) {
            const i = network.Default.indices(kings, .{ .piece = p, .square = s }).get(c);
            sub_array.pushUnchecked(i);
        }
    }

    self.occs.getPtr(c)[bucket] = .init(position);
    self.accs.getPtr(c)[bucket].update(wgts, &add_array, &sub_array);

    perspective.accs.set(c, self.accs.getPtrConst(c)[bucket]);
    perspective.dirty.set(c, false);
}

const bitboard = @import("bitboard");
const std = @import("std");
const types = @import("types");

const kiwi = types.Square.Set.fromSlice(types.Square, &.{
    // zig fmt: off
    .a8,                .e8,           .h8,
    .a7,      .c7, .d7, .e7, .f7, .g7,
    .a6, .b6,           .e6, .f6, .g6,
                   .d5, .e5,
         .b4,           .e4,
              .c3,           .f3,      .h3,
    .a2, .b2, .c2, .d2, .e2, .f2, .g2, .h2,
    .a1,                .e1,           .h1,
    // zig fmt: on
});

test "zin.bitboard.nAtk" {
    try bitboard.init();
    defer bitboard.deinit();

    const c3_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .b5, .a4, .a2, .b1, .d1, .e2, .e4, .d5,
    });
    const f6_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .e8, .d7, .d5, .e4, .g4, .h5, .h7, .g8,
    });

    try std.testing.expectEqual(c3_atk, bitboard.nAtk(.c3));
    try std.testing.expectEqual(f6_atk, bitboard.nAtk(.f6));
}

test "zin.bitboard.bAtk" {
    try bitboard.init();
    defer bitboard.deinit();

    const d2_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .c3, .c1, .e1, .e3, .f4, .g5, .h6,
    });
    const g7_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .f8, .f6, .h6, .h8,
    });

    try std.testing.expectEqual(d2_atk, bitboard.bAtk(.d2, kiwi));
    try std.testing.expectEqual(g7_atk, bitboard.bAtk(.g7, kiwi));
}

test "zin.bitboard.rAtk" {
    try bitboard.init();
    defer bitboard.deinit();

    const a1_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .a2, .b1, .c1, .d1, .e1,
    });
    const h8_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .g8, .f8, .e8, .h7, .h6, .h5, .h4, .h3,
    });

    try std.testing.expectEqual(bitboard.rAtk(.a1, kiwi), a1_atk);
    try std.testing.expectEqual(bitboard.rAtk(.h8, kiwi), h8_atk);
}

test "zin.bitboard.knightsAtk" {
    const c3_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .b5, .a4, .a2, .b1, .d1, .e2, .e4, .d5,
    });
    const e5_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .d7, .c6, .c4, .d3, .f3, .g4, .g6, .f7,
    });
    const b6_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .a8, .a4, .c4, .d5, .d7, .c8,
    });
    const f6_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .e8, .d7, .d5, .e4, .g4, .h5, .h7, .g8,
    });

    try std.testing.expectEqual(c3_atk, bitboard.knightsAtk(.fromSquare(.c3)));
    try std.testing.expectEqual(e5_atk, bitboard.knightsAtk(.fromSquare(.e5)));
    try std.testing.expectEqual(b6_atk, bitboard.knightsAtk(.fromSquare(.b6)));
    try std.testing.expectEqual(f6_atk, bitboard.knightsAtk(.fromSquare(.f6)));
    try std.testing.expectEqual(
        types.Square.Set.fromSlice(types.Square.Set, &.{ c3_atk, e5_atk, b6_atk, f6_atk }),
        bitboard.knightsAtk(.fromSlice(types.Square, &.{ .c3, .e5, .b6, .f6 })),
    );
}

test "zin.bitboard.slidersAtk" {
    const d2_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .c3, .c1, .e1, .e3, .f4, .g5, .h6,
    });
    const e2_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .d3, .c4, .b5, .a6, .d1, .f1, .f3,
    });
    const g7_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .f8, .f6, .h6, .h8,
    });
    const a6_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .b5, .c4, .d3, .e2, .b7, .c8,
    });

    try std.testing.expectEqual(d2_atk, bitboard.slidersAtk(.fromSquare(.d2), .none, kiwi)[0]);
    try std.testing.expectEqual(e2_atk, bitboard.slidersAtk(.fromSquare(.e2), .none, kiwi)[0]);
    try std.testing.expectEqual(a6_atk, bitboard.slidersAtk(.fromSquare(.a6), .none, kiwi)[0]);
    try std.testing.expectEqual(g7_atk, bitboard.slidersAtk(.fromSquare(.g7), .none, kiwi)[0]);

    const a1_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .a2, .b1, .c1, .d1, .e1,
    });
    const h1_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .h2, .g1, .f1, .e1,
    });
    const a8_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .a7, .b8, .c8, .d8, .e8,
    });
    const h8_atk: types.Square.Set = .fromSlice(types.Square, &.{
        .g8, .f8, .e8, .h7, .h6, .h5, .h4, .h3,
    });

    try std.testing.expectEqual(a1_atk, bitboard.slidersAtk(.none, .fromSquare(.a1), kiwi)[1]);
    try std.testing.expectEqual(h8_atk, bitboard.slidersAtk(.none, .fromSquare(.h8), kiwi)[1]);

    const sliders_atk = bitboard.slidersAtk(
        .fromSlice(types.Square, &.{ .d2, .e2, .a6, .g7 }),
        .fromSlice(types.Square, &.{ .a1, .h1, .a8, .h8 }),
        kiwi,
    );
    try std.testing.expectEqual(
        types.Square.Set.fromSlice(types.Square.Set, &.{ d2_atk, e2_atk, a6_atk, g7_atk }),
        sliders_atk[0],
    );
    try std.testing.expectEqual(
        types.Square.Set.fromSlice(types.Square.Set, &.{ a1_atk, h1_atk, a8_atk, h8_atk }),
        sliders_atk[1],
    );
}

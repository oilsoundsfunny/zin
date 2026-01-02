const bitboard = @import("bitboard");
const std = @import("std");
const types = @import("types");

const kiwi = types.Square.Set.fromSlice(types.Square, &.{
    .a8, .e8, .h8,
    .a7, .c7, .d7,
    .e7, .f7, .g7,
    .a6, .b6, .e6,
    .f6, .g6, .d5,
    .e5, .b4, .e4,
    .c3, .f3, .h3,
    .a2, .b2, .c2,
    .d2, .e2, .f2,
    .g2, .h2, .a1,
    .e1, .h1,
});

test {
    try bitboard.init();
    defer bitboard.deinit();

    const c3_atk = types.Square.Set.fromSlice(types.Square, &.{
        .b5, .a4, .a2, .b1, .d1, .e2, .e4, .d5,
    });
    const f6_atk = types.Square.Set.fromSlice(types.Square, &.{
        .e8, .d7, .d5, .e4, .g4, .h5, .h7, .g8,
    });

    try std.testing.expectEqual(c3_atk, bitboard.nAtk(.c3));
    try std.testing.expectEqual(f6_atk, bitboard.nAtk(.f6));
}

test {
    try bitboard.init();
    defer bitboard.deinit();

    const d2_atk = types.Square.Set.fromSlice(types.Square, &.{
        .c3, .c1, .e1, .e3, .f4, .g5, .h6,
    });
    const g7_atk = types.Square.Set.fromSlice(types.Square, &.{
        .f8, .f6, .h6, .h8,
    });

    try std.testing.expectEqual(d2_atk, bitboard.bAtk(.d2, kiwi));
    try std.testing.expectEqual(g7_atk, bitboard.bAtk(.g7, kiwi));
}

test {
    try bitboard.init();
    defer bitboard.deinit();

    const a1_atk = types.Square.Set.fromSlice(types.Square, &.{
        .a2, .b1, .c1, .d1, .e1,
    });
    const h8_atk = types.Square.Set.fromSlice(types.Square, &.{
        .g8, .f8, .e8, .h7, .h6, .h5, .h4, .h3,
    });

    try std.testing.expectEqual(bitboard.rAtk(.a1, kiwi), a1_atk);
    try std.testing.expectEqual(bitboard.rAtk(.h8, kiwi), h8_atk);
}

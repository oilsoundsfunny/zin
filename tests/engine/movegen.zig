const bitboard = @import("bitboard");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

test {
    try std.testing.expectEqual(@sizeOf(u16), @sizeOf(engine.movegen.Move));
    try std.testing.expectEqual(@sizeOf(u16) * 256, @sizeOf(engine.movegen.Move.List));

    try std.testing.expectEqual(@sizeOf(u32), @sizeOf(engine.movegen.Move.Scored));
    try std.testing.expectEqual(@sizeOf(u32) * 256, @sizeOf(engine.movegen.Move.Scored.List));

    try std.testing.expectEqual(@sizeOf(u16) * 256, @sizeOf(engine.movegen.Move.Root));
}

test {
    try bitboard.init();
    defer bitboard.deinit();

    try params.init();
    defer params.deinit();

    try engine.init();
    defer engine.deinit();

    var board: engine.Board = .{};
    try board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    var list: engine.movegen.Move.Scored.List = .{};
    var cnt: usize = 0;

    cnt += list.genNoisy(board.top());
    cnt += list.genQuiet(board.top());
    try std.testing.expectEqual(20, cnt);
}

test {
    try bitboard.init();
    defer bitboard.deinit();

    try params.init();
    defer params.deinit();

    try engine.init();
    defer engine.deinit();

    const thread = try std.testing.allocator.create(engine.Thread);
    defer std.testing.allocator.destroy(thread);

    thread.board = .{};
    try thread.board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    const seq = [_]engine.movegen.Move{
        .{ .flag = .none, .src = .a2, .dst = .a3 },
        .{ .flag = .none, .src = .b2, .dst = .b3 },
        .{ .flag = .none, .src = .c2, .dst = .c3 },
        .{ .flag = .none, .src = .d2, .dst = .d3 },
        .{ .flag = .none, .src = .e2, .dst = .e3 },
        .{ .flag = .none, .src = .f2, .dst = .f3 },
        .{ .flag = .none, .src = .g2, .dst = .g3 },
        .{ .flag = .none, .src = .h2, .dst = .h3 },

        .{ .flag = .torped, .src = .a2, .dst = .a4 },
        .{ .flag = .torped, .src = .b2, .dst = .b4 },
        .{ .flag = .torped, .src = .c2, .dst = .c4 },
        .{ .flag = .torped, .src = .d2, .dst = .d4 },
        .{ .flag = .torped, .src = .e2, .dst = .e4 },
        .{ .flag = .torped, .src = .f2, .dst = .f4 },
        .{ .flag = .torped, .src = .g2, .dst = .g4 },
        .{ .flag = .torped, .src = .h2, .dst = .h4 },

        .{ .flag = .none, .src = .b1, .dst = .a3 },
        .{ .flag = .none, .src = .b1, .dst = .c3 },
        .{ .flag = .none, .src = .g1, .dst = .f3 },
        .{ .flag = .none, .src = .g1, .dst = .h3 },
    };
    var nmp = engine.movegen.Picker.init(thread, .{});
    var qmp = engine.movegen.Picker.init(thread, .{});

    nmp.skipQuiets();
    if (nmp.next()) |_| {
        return error.TestExpectedEqual;
    }

    for (seq) |m| {
        const sm = qmp.next() orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(m.flag, sm.move.flag);
        try std.testing.expectEqual(m.src, sm.move.src);
        try std.testing.expectEqual(m.dst, sm.move.dst);
    }
}

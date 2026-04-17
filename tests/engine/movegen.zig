const bitboard = @import("bitboard");
const engine = @import("engine");
const params = @import("params");
const std = @import("std");
const types = @import("types");

test {
    try std.testing.expectEqual(@sizeOf(u16), @sizeOf(engine.movegen.Move));
    try std.testing.expectEqual(@sizeOf(u16) * 256, @sizeOf(engine.movegen.Move.List));

    try std.testing.expectEqual(@sizeOf(u32), @sizeOf(engine.movegen.Move.Scored));
    try std.testing.expectEqual(@sizeOf(u16) * 256, @sizeOf(engine.movegen.Move.Root));
}

test {
    try bitboard.init();
    defer bitboard.deinit();

    try params.init();
    defer params.deinit();

    try engine.init();
    defer engine.deinit();

    const allocator = std.testing.allocator;
    const thread = try allocator.create(engine.Thread);
    defer allocator.destroy(thread);

    thread.board = .{};
    try thread.board.parseFen(engine.Board.Position.startpos);

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

    var map: std.AutoHashMap(engine.movegen.Move, bool) = .init(allocator);
    defer map.deinit();
    for (seq) |m| {
        try map.put(m, true);
    }

    var nmp = engine.movegen.Picker.init(thread, .{});
    var qmp = engine.movegen.Picker.init(thread, .{});

    nmp.skipQuiets();
    if (nmp.next()) |_| {
        return error.TestExpectedEqual;
    }

    for (seq) |_| {
        const sm = qmp.next() orelse return error.TestExpectedEqual;
        try std.testing.expectEqual(map.get(sm.move), true);
    } else if (qmp.next()) |_| {
        return error.TestExpectedEqual;
    }
}

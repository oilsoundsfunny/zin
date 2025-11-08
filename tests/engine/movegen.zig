const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

test {
	try std.testing.expectEqual(@sizeOf(u16), @sizeOf(engine.movegen.Move));
	try std.testing.expectEqual(@sizeOf(u16) * 256, @sizeOf(engine.movegen.Move.List));

	try std.testing.expectEqual(@sizeOf(u32), @sizeOf(engine.movegen.Move.Scored));
	try std.testing.expectEqual(@sizeOf(u32) * 256, @sizeOf(engine.movegen.Move.Scored.List));
}

test {
	try bitboard.init();
	defer bitboard.deinit();

	var pos = std.mem.zeroInit(engine.Position, .{});
	try pos.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

	var list: engine.movegen.Move.Scored.List = .{};
	var cnt: usize = 0;

	cnt += list.genNoisy(&pos);
	cnt += list.genQuiet(&pos);
	try std.testing.expectEqual(20, cnt);
}

test {
	try bitboard.init();
	defer bitboard.deinit();

	const thread = try std.testing.allocator.create(engine.search.Thread);
	defer std.testing.allocator.destroy(thread);

	const pos = &thread.pos;
	try pos.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

	const seq = [_]engine.movegen.Move {
		.{.flag = .none, .info = .{.none = 0}, .src = .a2, .dst = .a3},
		.{.flag = .none, .info = .{.none = 0}, .src = .b2, .dst = .b3},
		.{.flag = .none, .info = .{.none = 0}, .src = .c2, .dst = .c3},
		.{.flag = .none, .info = .{.none = 0}, .src = .d2, .dst = .d3},
		.{.flag = .none, .info = .{.none = 0}, .src = .e2, .dst = .e3},
		.{.flag = .none, .info = .{.none = 0}, .src = .f2, .dst = .f3},
		.{.flag = .none, .info = .{.none = 0}, .src = .g2, .dst = .g3},
		.{.flag = .none, .info = .{.none = 0}, .src = .h2, .dst = .h3},

		.{.flag = .none, .info = .{.none = 0}, .src = .a2, .dst = .a4},
		.{.flag = .none, .info = .{.none = 0}, .src = .b2, .dst = .b4},
		.{.flag = .none, .info = .{.none = 0}, .src = .c2, .dst = .c4},
		.{.flag = .none, .info = .{.none = 0}, .src = .d2, .dst = .d4},
		.{.flag = .none, .info = .{.none = 0}, .src = .e2, .dst = .e4},
		.{.flag = .none, .info = .{.none = 0}, .src = .f2, .dst = .f4},
		.{.flag = .none, .info = .{.none = 0}, .src = .g2, .dst = .g4},
		.{.flag = .none, .info = .{.none = 0}, .src = .h2, .dst = .h4},

		.{.flag = .none, .info = .{.none = 0}, .src = .b1, .dst = .a3},
		.{.flag = .none, .info = .{.none = 0}, .src = .b1, .dst = .c3},
		.{.flag = .none, .info = .{.none = 0}, .src = .g1, .dst = .f3},
		.{.flag = .none, .info = .{.none = 0}, .src = .g1, .dst = .h3},
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

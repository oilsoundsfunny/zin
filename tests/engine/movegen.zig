const base = @import("base");
const bitboard = @import("bitboard");
const engine = @import("engine");
const std = @import("std");

test {
	try std.testing.expectEqual(@sizeOf(engine.movegen.Move), @sizeOf(u16));
	try std.testing.expectEqual(@sizeOf(engine.movegen.Move.List), @sizeOf(u16) * 256);

	try std.testing.expectEqual(@sizeOf(engine.movegen.Move.Scored), @sizeOf(u32));
	try std.testing.expectEqual(@sizeOf(engine.movegen.Move.Scored.List), @sizeOf(u32) * 256);
}

test {
	try base.init();
	defer base.deinit();

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
	try base.init();
	defer base.deinit();

	try bitboard.init();
	defer bitboard.deinit();

	const info = try base.heap.allocator.create(engine.search.Info);
	defer base.heap.allocator.destroy(info);

	try info.pos.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

	const seq = [_]engine.movegen.Move {
		.{.flag = .none, .info = .{.none = {}}, .src = .a2, .dst = .a3},
		.{.flag = .none, .info = .{.none = {}}, .src = .b2, .dst = .b3},
		.{.flag = .none, .info = .{.none = {}}, .src = .c2, .dst = .c3},
		.{.flag = .none, .info = .{.none = {}}, .src = .d2, .dst = .d3},
		.{.flag = .none, .info = .{.none = {}}, .src = .e2, .dst = .e3},
		.{.flag = .none, .info = .{.none = {}}, .src = .f2, .dst = .f3},
		.{.flag = .none, .info = .{.none = {}}, .src = .g2, .dst = .g3},
		.{.flag = .none, .info = .{.none = {}}, .src = .h2, .dst = .h3},

		.{.flag = .none, .info = .{.none = {}}, .src = .a2, .dst = .a4},
		.{.flag = .none, .info = .{.none = {}}, .src = .b2, .dst = .b4},
		.{.flag = .none, .info = .{.none = {}}, .src = .c2, .dst = .c4},
		.{.flag = .none, .info = .{.none = {}}, .src = .d2, .dst = .d4},
		.{.flag = .none, .info = .{.none = {}}, .src = .e2, .dst = .e4},
		.{.flag = .none, .info = .{.none = {}}, .src = .f2, .dst = .f4},
		.{.flag = .none, .info = .{.none = {}}, .src = .g2, .dst = .g4},
		.{.flag = .none, .info = .{.none = {}}, .src = .h2, .dst = .h4},

		.{.flag = .none, .info = .{.none = {}}, .src = .b1, .dst = .a3},
		.{.flag = .none, .info = .{.none = {}}, .src = .b1, .dst = .c3},
		.{.flag = .none, .info = .{.none = {}}, .src = .g1, .dst = .f3},
		.{.flag = .none, .info = .{.none = {}}, .src = .g1, .dst = .h3},
	};
	var nmp = engine.movegen.Picker.init(info, true,  .{}, .{}, .{});
	var qmp = engine.movegen.Picker.init(info, false, .{}, .{}, .{});

	for (seq) |m| {
		const sm = qmp.next() orelse return error.TestExpectedEqual;
		try std.testing.expectEqual(m.flag, sm.move.flag);
		try std.testing.expectEqual(m.src, sm.move.src);
		try std.testing.expectEqual(m.dst, sm.move.dst);

		if (nmp.next()) |_| {
			return error.TestExpectedEqual;
		}
	}
}

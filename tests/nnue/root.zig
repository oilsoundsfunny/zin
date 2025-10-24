const base = @import("base");
const engine = @import("engine");
const nnue = @import("nnue");
const std = @import("std");

test {
	var pos = std.mem.zeroInit(engine.Position, .{});
	try pos.parseFen(engine.Position.startpos);

	const indices = std.EnumArray(base.types.Color, []const usize).init(.{
		.white = &.{
			192,  65, 130, 259, 324, 133,  70, 199,   8,   9,  10,  11,  12,  13,  14,  15,
			432, 433, 434, 435, 436, 437, 438, 439, 632, 505, 570, 699, 764, 573, 510, 639,
		},
		.black = &.{
			192,  65, 130, 259, 324, 133,  70, 199,   8,   9,  10,  11,  12,  13,  14,  15,
			432, 433, 434, 435, 436, 437, 438, 439, 632, 505, 570, 699, 764, 573, 510, 639,
		},
	});

	const biases = [16]nnue.arch.Int {
		176, 33, 18,  47,  9, 64, 104, -24,
		161, 85, 58, 180, 23, 57,   6,  36,
	};
	var accumulator: nnue.Accumulator = .{};
	for (base.types.Color.values) |c| {
		inline for (0 .. 16) |i| {
			const a = accumulator.perspectives.get(c)[i];
			const v = biases[i];
			try std.testing.expectEqual(v, a);
		}
	}

	const values = std.EnumArray(base.types.Color, [16]nnue.arch.Int).init(.{
		.white = .{
			-1233, 106, 168, -515, 401, 268, 5, 134, 565, 564, -26, 233, -346, 253, 131, 237,
		},
		.black = .{
			-1233, 106, 168, -515, 401, 268, 5, 134, 565, 564, -26, 233, -346, 253, 131, 237,
		},
	});

	for (base.types.Color.values) |c| {
		for (indices.get(c)) |i| {
			accumulator.perspectives.getPtr(c).* +%= nnue.net.default.hl0_w[i];
		}
		pos.ss.top().accumulator.mirror(c, &pos.pieces_occ);
	}
	try std.testing.expectEqual(accumulator, pos.ss.top().accumulator);

	var ev: engine.evaluation.score.Int = engine.evaluation.score.draw;
	for (base.types.Color.values) |c| {
		inline for (0 .. 16) |i| {
			const v = values.get(c)[i];
			const a = accumulator.perspectives.get(c)[i];
			try std.testing.expectEqual(v, a);
		}

		inline for (0 .. nnue.arch.hl0_len) |i| {
			const a: engine.evaluation.score.Int = accumulator.perspectives.get(c)[i];
			const w: engine.evaluation.score.Int = nnue.net.default.out_w[c.tag()][i];
			ev += std.math.clamp(a, 0, nnue.arch.qa) * std.math.clamp(a, 0, nnue.arch.qa) * w;
		}
	}
	try std.testing.expectEqual(608404, ev);

	ev = @divTrunc(ev, nnue.arch.qa) + nnue.net.default.out_b;
	ev = @divTrunc(ev * nnue.arch.scale, nnue.arch.qa * nnue.arch.qb);
	try std.testing.expectEqual(78, ev);
	try std.testing.expectEqual(78, engine.evaluation.score.fromPosition(&pos));
}

test {
	var pos = std.mem.zeroInit(engine.Position, .{});
	try pos.parseFen(engine.Position.kiwipete);

	const biases = [16]nnue.arch.Int {
		176, 33, 18,  47,  9, 64, 104, -24,
		161, 85, 58, 180, 23, 57,   6,  36,
	};
	var accumulator: nnue.Accumulator = .{};
	for (base.types.Color.values) |c| {
		inline for (0 .. 16) |i| {
			const v = accumulator.perspectives.get(c)[i];
			const b = biases[i];
			try std.testing.expectEqual(b, v);
		}
	}

	const indices = std.EnumArray(base.types.Color, []const usize).init(.{
		.white = &.{
			192, 324, 199,   8,   9,  10, 139, 140,  13,  14,  15,  82, 277, 407, 409,  28,
			 35, 100, 552, 489, 428, 493, 430, 432, 434, 435, 692, 437, 566, 632, 764, 639,
		},
		.black = &.{
			632, 764, 639, 432, 433, 434, 563, 564, 437, 438, 439, 490, 685,  47,  33, 420,
			411, 476, 144,  81,  20,  85,  22,   8,  10,  11, 268,  13, 142, 192, 324, 199,
		},
	});

	const values = std.EnumArray(base.types.Color, [16]nnue.arch.Int).init(.{
		.white = .{
			-1326, 140, 57, -500, 539, 265, -180, 81, 574, 576, 42,  271, -260, 286, -52, 287,
		},
		.black = .{
			-1296, 138, 83, -485, 511, 229,    7, 97, 575, 565,  2, -174, -279, 285, 153, 303,
		},
	});

	for (base.types.Color.values) |c| {
		for (indices.get(c)) |i| {
			accumulator.perspectives.getPtr(c).* +%= nnue.net.default.hl0_w[i];
		}
		// pos.ss.top().accumulator.mirror(c, &pos.pieces_occ);
	}
	try std.testing.expectEqual(accumulator, pos.ss.top().accumulator);

	var ev: engine.evaluation.score.Int = engine.evaluation.score.draw;
	for (base.types.Color.values) |c| {
		inline for (0 .. 16) |i| {
			const v = values.get(c)[i];
			const a = accumulator.perspectives.get(c)[i];
			try std.testing.expectEqual(v, a);
		}

		inline for (0 .. nnue.arch.hl0_len) |i| {
			const a: engine.evaluation.score.Int = accumulator.perspectives.get(c)[i];
			const w: engine.evaluation.score.Int = nnue.net.default.out_w[c.tag()][i];
			ev += std.math.clamp(a, 0, nnue.arch.qa) * std.math.clamp(a, 0, nnue.arch.qa) * w;
		}
	}
	try std.testing.expectEqual(-1423747, ev);

	ev = @divTrunc(ev, nnue.arch.qa) + nnue.net.default.out_b;
	ev = @divTrunc(ev * nnue.arch.scale, nnue.arch.qa * nnue.arch.qb);
	try std.testing.expectEqual(-116, ev);
	try std.testing.expectEqual(-116, engine.evaluation.score.fromPosition(&pos));
}

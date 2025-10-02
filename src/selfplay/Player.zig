const base = @import("base");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");

const viri = @import("viri.zig");

const Self = @This();

instance:	engine.search.Instance,
data:	viri.Self,

pub fn init() !Self {
	var self = std.mem.zeroInit(Self, .{});
	try self.instance.alloc(1);
	return self;
}

pub fn match(self: *Self, fen: []const u8) !void {
	const infos = self.instance.infos;
	const pos = &infos[0].pos;
	std.debug.assert(infos.len == 1);

	try pos.parseFen(fen);
	self.data = viri.Self.fromPosition(pos);

	while (true) {
		self.instance.think();

		const pv = &self.instance.root_moves.slice()[0];
		const stm = pos.stm;

		const m = pv.line.slice()[0];
		const s = switch (stm) {
			.white => pv.score,
			.black => -pv.score,
		};
		self.data.line.append(.{ .move = m, .score = @intCast(s) })
		  catch std.debug.panic("stack overflow", .{});

		if (m == viri.Move.zero) {
			self.data.result = switch (s) {
				engine.evaluation.score.win  => .white,
				engine.evaluation.score.draw => .draw,
				engine.evaluation.score.lose => .black,
				else => std.debug.panic("invalid bestscore", .{}),
			};
			break;
		}
		try pos.doMove(m);
	}
}

const base = @import("base");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const root = @import("root");
const std = @import("std");

const viri = @import("viri.zig");

const Self = @This();

instance:	engine.search.Instance,
opening:	[]const u8 = &.{},

err:	?anyerror,
handle:	?std.Thread,

data:	viri.Self,
line:	bounded_array.BoundedArray(viri.Move.Scored, engine.Position.State.Stack.capacity),

pub const Tourney = struct {
	players:	[]Self = &.{},

	started:	u64,
	played:		u64,
	max:	?u64,

	pub fn alloc(n: usize, games: ?u64, nodes: u64) !Tourney {
		var self = std.mem.zeroInit(Tourney, .{
			.players = try base.heap.allocator.alloc(Self, n),
			.max = games,
		});

		for (self.players) |*player| {
			player.* = std.mem.zeroInit(Self, .{});

			try player.instance.alloc(1);
			player.instance.options.infinite = false;
			player.instance.options.nodes = nodes;
		}

		return self;
	}

	pub fn round(self: *Tourney) !void {
		var openings = bounded_array.BoundedArray([]const u8, 256).init(0) catch unreachable;

		while (root.io.reader.takeDelimiterExclusive('\n')) |line| {
			const copy = try base.heap.allocator.dupe(u8, line);
			try openings.append(copy);

			if (openings.constSlice().len >= self.players.len) {
				break;
			}
		} else |err| if (openings.constSlice().len == 0) {
			return err;
		}

		defer while (openings.pop()) |opening| {
			base.heap.allocator.free(opening);
		};

		for (openings.constSlice(), self.players) |opening, *player| {
			player.opening = opening;
			player.handle = try std.Thread.spawn(.{ .allocator = base.heap.allocator },
			  wrapper, .{player});
			defer self.started += 1;
		}

		for (openings.constSlice(), self.players) |_, *player| {
			std.Thread.join(player.handle orelse unreachable);
			if (player.err) |err| {
				return err;
			}

			defer self.played += 1;
			try player.dump();
		}
	}
};

fn dump(self: *Self) !void {
		try root.io.writer.writeAll(std.mem.asBytes(&self.data));
		for (self.line.constSlice()) |sm| {
			try root.io.writer.writeAll(std.mem.asBytes(&sm));
		}
		try root.io.writer.flush();
}

fn match(self: *Self) !void {
	std.debug.assert(self.instance.infos.len == 1);
	const infos = self.instance.infos;
	const info = &infos[0];

	const fen = self.opening;
	const pos = &info.pos;
	try pos.parseFen(fen);

	self.data = viri.Self.fromPosition(pos);
	self.line = std.mem.zeroInit(@TypeOf(self.line), .{});


	while (true) {
		self.instance.root_moves = std.mem.zeroInit(@TypeOf(self.instance.root_moves), .{});
		try self.instance.think();

		const pv = &self.instance.root_moves.slice()[0];
		const pvm = pv.line.slice()[0];
		const stm = pos.stm;

		const m = viri.Move.fromMove(pvm);
		const s = @as(i32, @intCast(switch (stm) {
			.white => pv.score,
			.black => -pv.score,
		}));

		const centipawns = engine.evaluation.score.toCentipawns(s);
		const has_move = pvm != engine.movegen.Move.zero;
		try self.line.append(.{
			.move = m,
			.score = @intCast(centipawns),
		});

		if (!has_move) {
			self.data.result = switch (s) {
				engine.evaluation.score.win  => .white,
				engine.evaluation.score.draw => .draw,
				engine.evaluation.score.lose => .black,
				else => std.debug.panic("invalid bestscore", .{}),
			};

			_ = self.line.pop();
			self.line.append(.{}) catch unreachable;

			break;
		}

		try pos.doMove(pvm);
	}
}

fn wrapper(self: *Self) !void {
	self.err = null;
	return self.match() catch |err| blk: {
		self.err = err;
		break :blk err;
	};
}

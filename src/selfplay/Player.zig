const base = @import("base");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const root = @import("root");
const std = @import("std");

const viri = @import("viri.zig");

const Self = @This();

instance:	engine.search.Instance,
opening:	[]const u8 = &.{},

games:	?usize,
played:	 usize,
index:	 usize,

data:	viri.Self,
line:	bounded_array.BoundedArray(viri.Move.Scored, engine.Position.State.Stack.capacity),

pub const Tourney = struct {
	players:	[]Self = &.{},

	pub fn alloc(n: usize, games: ?u64, nodes: u64) !Tourney {
		var self: Tourney = .{
			.players = try base.heap.allocator.alignedAlloc(Self, .@"64", n),
		};

		for (self.players, 0 ..,) |*player, i| {
			player.* = std.mem.zeroInit(Self, .{
				.games = games,
				.index = i,
			});

			try player.instance.alloc(1);
			player.instance.options.infinite = false;
			player.instance.options.nodes = nodes;
		}

		return self;
	}

	pub fn start(self: *Tourney) !void {
		var threads = try bounded_array.BoundedArray(std.Thread, 256).init(0);
		for (self.players) |*player| {
			const id = try std.Thread.spawn(.{ .allocator = base.heap.allocator },
			  match, .{player});
			try threads.append(id);
		}

		for (threads.constSlice()) |thread| {
			std.Thread.join(thread);
		}
	}
};

fn readOpening(self: *Self) !void {
	root.io.reader_mtx.lock();
	defer root.io.reader_mtx.unlock();

	const reader = &root.io.book_reader.interface;
	const line = try reader.takeDelimiterExclusive('\n');
	const copy = try base.heap.allocator.dupe(u8, line);
	self.opening = copy;
}

fn writeData(self: *Self) !void {
	root.io.writer_mtx.lock();
	defer root.io.writer_mtx.unlock();

	const writer = &root.io.data_writer.interface;
	try writer.writeAll(std.mem.asBytes(&self.data));
	for (self.line.constSlice()) |sm| {
		try writer.writeAll(std.mem.asBytes(&sm));
	}
	try writer.flush();
}

fn playout(self: *Self) !void {
	std.debug.assert(self.instance.infos.len == 1);
	const infos = self.instance.infos;
	const info = &infos[0];

	const fen = self.opening;
	const pos = &info.pos;
	try pos.parseFen(fen);
	defer base.heap.allocator.free(fen);

	self.data = viri.Self.fromPosition(pos);
	try self.line.resize(0);

	while (true) {
		try self.instance.root_moves.array.resize(0);
		try self.instance.think();

		const pv = &self.instance.root_moves.slice()[0];
		const stm = pos.stm;
		const pvm = pv.line.slice()[0];
		const pvs = switch (stm) {
			.white => 0 + pv.score,
			.black => 0 - pv.score,
		};

		const m = viri.Move.fromMove(pvm);
		const s = @as(i32, @intCast(pvs));

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
			try self.line.append(.{});

			break;
		}

		try pos.doMove(pvm);
	}
}

fn match(self: *Self) !void {
	while (self.readOpening()) : (self.played += 1) {
		if (self.games) |games| {
			if (self.played >= games) {
				break;
			}
		}

		self.playout() catch |err| {
			std.debug.print("error: {s} @ player {d}, game {d}",
			  .{@errorName(err), self.index, self.played});
		};
		try self.writeData();
	} else |err| switch (err) {
		error.EndOfStream => {},
		else => return err,
	}
}

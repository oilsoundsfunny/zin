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

book:	std.fs.File,
file:	std.fs.File,

book_buf:	[4096]u8,
file_buf:	[4096]u8,

book_reader:	std.fs.File.Reader,
file_writer:	std.fs.File.Writer,

pub const Tourney = struct {
	players:	[]Self = &.{},

	pub fn alloc(n: usize,
	  book_paths: bounded_array.BoundedArray([]const u8, 256),
	  data_paths: bounded_array.BoundedArray([]const u8, 256),
	  games: ?u64, nodes: u64) !Tourney {
		var self: Tourney = .{
			.players = try base.heap.allocator.alignedAlloc(Self, .@"64", n),
		};

		std.debug.assert(book_paths.len == n);
		std.debug.assert(data_paths.len == n);
		for (self.players, 0 .., book_paths.constSlice(), data_paths.constSlice())
		  |*player, i, book_path, file_path| {
			const book = try std.fs.cwd().openFile(book_path, .{});
			const file = try std.fs.cwd().createFile(file_path, .{});

			player.* = std.mem.zeroInit(Self, .{
				.games = games,
				.index = i,

				.book = book,
				.file = file,

				.book_reader = book.reader(&player.book_buf),
				.file_writer = file.writer(&player.file_buf),
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

fn dump(self: *Self) !void {
	const writer = &self.file_writer.interface;
	try writer.writeAll(std.mem.asBytes(&self.data));
	for (self.line.constSlice()) |sm| {
		try writer.writeAll(std.mem.asBytes(&sm));
	}
	try writer.flush();
}

fn playout(self: *Self, fen: []const u8) !void {
	std.debug.assert(self.instance.infos.len == 1);
	const infos = self.instance.infos;
	const info = &infos[0];

	const pos = &info.pos;
	try pos.parseFen(fen);

	self.instance.root_moves = std.mem.zeroInit(@TypeOf(self.instance.root_moves), .{});
	self.data = viri.Self.fromPosition(pos);
	try self.line.resize(0);

	while (true) {
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
			try self.line.append(.{});

			break;
		}

		try pos.doMove(pvm);
	}
}

fn match(self: *Self) !void {
	while (self.book_reader.interface.takeDelimiterExclusive('\n')) |opening| : (self.played += 1) {
		if (self.games) |games| {
			if (self.played >= games) {
				break;
			}
		}

		self.playout(opening) catch |err| {
			std.debug.print("error: {s} @ player {d}, game {d}",
			  .{@errorName(err), self.index, self.played});
		};
		try self.dump();
	} else |err| switch (err) {
		error.EndOfStream => {},
		else => return err,
	}
}

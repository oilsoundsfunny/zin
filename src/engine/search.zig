const base = @import("base");
const bounded_array = @import("bounded_array");
const params = @import("params");
const std = @import("std");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const Position = @import("Position.zig");
const transposition = @import("transposition.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

pub const Depth = isize;
pub const Node = transposition.Entry.Flag;

pub const Info = struct {
	pos:	Position,
	depth:	Depth,

	instance:	*const Instance,
	options:	*const Options,

	ti:	usize,
	tn:	usize,

	rms:	bounded_array.BoundedArray(*movegen.Move.Root, 256)
	  = bounded_array.BoundedArray(*movegen.Move.Root, 256).init(0) catch unreachable,
	rmi:	usize,

	fn hardStop(self: *const Info) bool {
		const instance = self.instance;
		const options = self.options;

		const searching = @constCast(&options.is_searching);
		var stop = !searching.load(.acquire);
		if (self.ti != 0 or stop) {
			return stop;
		}

		const checked_p = @constCast(&instance.last_checked);
		const nodes_p = @constCast(&instance.nodes);

		const last_checked = checked_p.load(.acquire);
		const nodes = nodes_p.load(.acquire);

		return if (nodes -| last_checked < 1024) unchecked: {
			@branchHint(.likely);
			break :unchecked false;
		} else checked: {
			defer checked_p.store(nodes, .release);
			defer searching.store(!stop, .release);

			const inf = options.infinite;
			const exceed_nodes = if (options.nodes) |lim| nodes >= lim else false;
			const exceed_time = if (options.stop) |lim| base.time.read(.ms) >= lim else false;
			stop = !inf and (exceed_nodes or exceed_time);
			break :checked stop;
		};
	}

	fn aspiration(self: *Info,
	  rm: *movegen.Move.Root,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int) evaluation.score.Int {
		const pos = &self.pos;
		const nodes = @constCast(&self.instance.nodes);

		pos.doMove(rm.line.slice()[0]) catch std.debug.panic("invalid root move", .{});
		_ = nodes.fetchAdd(1, .acq_rel);
		defer pos.undoMove();

		const a = alpha;
		const b = beta;
		const d = self.depth;
		const is_pv = self.ti == 0 and rm == self.rms.slice()[0];

		var s: @TypeOf(a) = @intCast(rm.score);
		defer rm.score = s;

		var i: usize = 0;
		var lo = std.math.clamp(s - evaluation.score.unit / 4, a, b);
		var hi = std.math.clamp(s + evaluation.score.unit / 4, a, b);

		while (!self.hardStop() and s > a and s < b) : (i += 1) {
			s = if (is_pv or i != 0) -self.ab(.exact, 1, -hi, -lo, d - 1)
			  else -self.ab(.lowerbound, 1, -a - 1, -a, d - 1);

			if (s <= lo) {
				lo = std.math.clamp(lo * 2 - s, a, b);
			} else if (s >= hi) {
				hi = std.math.clamp(hi * 2 - s, a, b);
			} else break;
		}

		return s;
	}

	fn think(self: *Info) void {
		const b = evaluation.score.win;
		var a: evaluation.score.Int = evaluation.score.lose;

		for (self.rms.slice()) |rm| {
			const s = self.aspiration(rm, a, b);

			if (s > a) {
				a = s;
			}
			if (s >= b) {
				break;
			}
		}
	}

	pub fn ab(self: *Info,
	  node: Node,
	  ply: usize,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int,
	  depth: Depth) evaluation.score.Int {
		const d = depth;
		const b = beta;
		var a = alpha;

		if (d <= 0) {
			return self.qs(node, ply, a, b);
		}

		const pos = &self.pos;
		const key = pos.ss.top().key;
		const is_checked = pos.isChecked();

		const nodes = @constCast(&self.instance.nodes);
		const trunc_nodes: u4 = @truncate(nodes.load(.acquire));
		const draw
		  = @as(evaluation.score.Int, evaluation.score.draw)
		  + @as(evaluation.score.Int, trunc_nodes) - 8;

		const lose
		  = @as(evaluation.score.Int, evaluation.score.lose)
		  + @as(evaluation.score.Int, @intCast(ply));

		if (pos.isDrawn()) {
			@branchHint(.unlikely);
			return draw;
		}

		const ttf = transposition.table.fetch(key);
		const tte = ttf[0].*;
		const tth = ttf[1]
		  and tte.key == @as(@TypeOf(tte.key), @truncate(key))
		  and tte.flag != .none
		  and (tte.move == movegen.Move.zero or pos.isMovePseudoLegal(tte.move));
		const ttm = if (tth) tte.move else movegen.Move.zero;

		const has_tteval = tth
		  and tte.eval >= evaluation.score.tblose
		  and tte.eval <= evaluation.score.tbwin;
		const has_ttm = ttm != movegen.Move.zero;
		// const is_pv = node == .exact;
		const is_ttm_check = has_ttm and verify: {
			pos.doMove(ttm) catch break :verify false;
			defer pos.undoMove();

			const is = pos.isChecked();
			break :verify is;
		};
		const is_ttm_noisy = has_ttm and pos.isMoveNoisy(ttm);
		// const is_ttm_quiet = has_ttm and pos.isMoveQuiet(ttm);
		const was_pv = tth and tte.was_pv;

		if (tth and tte.shouldTrust(a, b, d)) {
			return tte.score;
		}

		if (is_checked or is_ttm_check or is_ttm_noisy) {
			pos.ss.top().stat_eval = evaluation.score.none;
			pos.ss.top().corr_eval = evaluation.score.none;
		} else {
			// TODO: correct eval
			pos.ss.top().stat_eval = if (has_tteval) tte.eval
			  else evaluation.score.fromPosition(pos);
			pos.ss.top().corr_eval = pos.ss.top().stat_eval;
		}

		const corr_eval = pos.ss.top().corr_eval;
		const stat_eval = pos.ss.top().stat_eval;

		// const has_corr = corr_eval != evaluation.score.none;
		// const has_stat = stat_eval != evaluation.score.none;

		if (self.hardStop()) {
			return if (tth) tte.score
			  else if (corr_eval != evaluation.score.none) draw + corr_eval
			  else evaluate: {
				const stat = evaluation.score.fromPosition(pos);
				const corr = stat;
				break :evaluate draw + corr;
			};
		}

		var best: movegen.Move.Scored = .{
			.move = .{},
			.score = evaluation.score.none,
		};
		var flag = Node.upperbound;

		var mi: usize = 0;
		var mp = movegen.Picker.init(self, false, ttm);

		move_loop: while (mp.next()) |sm| {
			if (self.hardStop()) {
				break :move_loop;
			}

			const m = sm.move;
			const s = recur: {
				pos.doMove(m) catch continue :move_loop;
				_ = nodes.fetchAdd(1, .acq_rel);

				defer pos.undoMove();
				defer mi += 1;

				const child: @TypeOf(node) = switch (node) {
					.upperbound => .lowerbound,
					.exact => if (mi == 0) .exact else .lowerbound,
					.lowerbound => if (mi == 0) .upperbound else .lowerbound,
					else => std.debug.panic("invalid node", .{}),
				};

				var score = -self.ab(child, ply + 1,
				  if (child == .exact) -b else -a - 1, -a, d - 1);
				if (score > a and score < b) {
					score = -self.ab(.exact, ply + 1, -b, -a, d - 1);
				}

				break :recur score;
			};

			if (s > best.score) {
				best.score = @intCast(s);
			}

			if (s > a) {
				a = s;
				best.move = m;
				flag = .exact;
			}

			if (s >= b) {
				flag = .lowerbound;
				break;
			}
		}

		if (best.score == evaluation.score.none) {
			return if (is_checked) lose else draw;
		}

		ttf[0].* = .{
			.was_pv = was_pv or flag == .exact,
			.flag = flag,
			.age = @truncate(transposition.table.age.load(.acquire)),
			.depth = @intCast(depth),
			.key = @truncate(key),
			.eval = @intCast(stat_eval),
			.score = best.score,
			.move = best.move,
		};

		return best.score;
	}

	pub fn qs(self: *Info,
	  node: Node,
	  ply: usize,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int) evaluation.score.Int {
		const b = beta;
		var a = alpha;

		const pos = &self.pos;
		const key = pos.ss.top().key;
		const is_checked = pos.isChecked();

		const nodes = @constCast(&self.instance.nodes);
		const trunc_nodes: u4 = @truncate(nodes.load(.acquire));
		const draw
		  = @as(evaluation.score.Int, evaluation.score.draw)
		  + @as(evaluation.score.Int, trunc_nodes) - 8;

		const lose
		  = @as(evaluation.score.Int, evaluation.score.lose)
		  + @as(evaluation.score.Int, @intCast(ply));

		if (pos.isDrawn()) {
			@branchHint(.unlikely);
			return draw;
		}

		const ttf = transposition.table.fetch(key);
		const tte = ttf[0].*;
		const tth = ttf[1]
		  and tte.key == @as(@TypeOf(tte.key), @truncate(key))
		  and tte.flag != .none
		  and (tte.move == movegen.Move.zero or pos.isMovePseudoLegal(tte.move));
		const ttm = if (tth) tte.move else movegen.Move.zero;

		const has_tteval = tth
		  and tte.eval >= evaluation.score.tblose
		  and tte.eval <= evaluation.score.tbwin;
		const has_ttm = ttm != movegen.Move.zero;
		// const is_pv = node == .exact;
		const is_ttm_check = has_ttm and verify: {
			pos.doMove(ttm) catch break :verify false;
			defer pos.undoMove();

			const is = pos.isChecked();
			break :verify is;
		};
		const is_ttm_noisy = has_ttm and pos.isMoveNoisy(ttm);
		// const is_ttm_quiet = has_ttm and pos.isMoveQuiet(ttm);
		const was_pv = tth and tte.was_pv;

		if (tth and tte.shouldTrust(a, b, 0)) {
			return tte.score;
		}

		if (is_checked or is_ttm_check or is_ttm_noisy) {
			pos.ss.top().stat_eval = evaluation.score.none;
			pos.ss.top().corr_eval = evaluation.score.none;
		} else {
			// TODO: correct eval
			pos.ss.top().stat_eval = if (has_tteval) tte.eval
			  else evaluation.score.fromPosition(pos);
			pos.ss.top().corr_eval = pos.ss.top().stat_eval;
		}

		const corr_eval = pos.ss.top().corr_eval;
		const stat_eval = pos.ss.top().stat_eval;

		const soft_ply: usize = 4;
		const hard_ply: usize = if (is_checked) 8 else 4;
		const qs_ply: usize = if (pos.ss.top().down(1).qs_ply) |qsp| qsp + 1 else 0;
		pos.ss.top().qs_ply = @truncate(qs_ply);

		if (qs_ply >= hard_ply or self.hardStop()) {
			return if (tth) tte.score
			  else if (corr_eval != evaluation.score.none) draw + corr_eval
			  else evaluate: {
				// TODO: correct eval
				const stat = evaluation.score.fromPosition(pos);
				const corr = stat;
				break :evaluate draw + corr;
			};
		}

		var best: movegen.Move.Scored = .{
			.move = .{},
			.score = evaluation.score.none,
		};
		var flag = Node.upperbound;

		var mi: usize = 0;
		var mp = movegen.Picker.init(self, qs_ply >= soft_ply or !is_checked, ttm);

		move_loop: while (mp.next()) |sm| {
			if (self.hardStop()) {
				break;
			}

			const m = sm.move;
			const s = recur: {
				pos.doMove(m) catch continue :move_loop;
				_ = nodes.fetchAdd(1, .acq_rel);

				defer pos.undoMove();
				defer mi += 1;

				const child: @TypeOf(node) = switch (node) {
					.upperbound => .lowerbound,
					.exact => if (mi == 0) .exact else .lowerbound,
					.lowerbound => if (mi == 0) .upperbound else .lowerbound,
					else => std.debug.panic("invalid node", .{}),
				};

				var score = -self.qs(child, ply + 1, if (child == .exact) -b else -a - 1, -a);
				if (score > a and score < b) {
					score = -self.qs(.exact, ply + 1, -b, -a);
				}

				break :recur score;
			};

			if (s > best.score) {
				best.score = @intCast(s);
			}

			if (s > a) {
				a = s;
				best.move = m;
				flag = if (!mp.noisy) .exact else flag;
			}

			if (s >= b) {
				flag = .lowerbound;
				break;
			}
		}

		if (best.score == evaluation.score.none) {
			return if (!mp.noisy) full: {
				break :full if (is_checked) lose else draw;
			} else lazy: {
				break :lazy if (corr_eval != evaluation.score.none) draw + corr_eval
				  else evaluate: {
					// TODO: correct eval
					const stat = evaluation.score.fromPosition(pos);
					const corr = stat;
					break :evaluate draw + corr;
				};
			};
		}

		ttf[0].* = .{
			.was_pv = was_pv or flag == .exact,
			.flag = flag,
			.age = @truncate(transposition.table.age.load(.acquire)),
			.depth = 0,
			.key = @truncate(key),
			.eval = @intCast(stat_eval),
			.score = best.score,
			.move = best.move,
		};

		return best.score;
	}
};

pub const Instance = struct {
	infos:	[]Info = &.{},
	options:	Options = std.mem.zeroInit(Options, .{}),
	root_moves:	movegen.Move.Root.List,

	last_checked:	std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
	nodes:	std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
	tbhits:	std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
	tthits:	std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

	fn printBest(self: *const Instance) !void {
		if (self != &uci.instance) {
			return;
		}
		try io.writer.print("bestmove", .{});

		const pv = self.infos[0].rms.slice()[0].line.constSlice();
		for (pv) |m| {
			const s = m.toString();
			const l = m.toStringLen();
			try io.writer.print(" ", .{});
			try io.writer.print("{s}", .{s[0 .. l]});
		}

		try io.writer.print("\n", .{});
		try io.writer.flush();
	}

	fn printInfo(self: *const Instance) !void {
		if (self != &uci.instance) {
			return;
		}

		const info = &self.infos[0];
		const depth = if (info.depth == 1) info.depth else info.depth - 1;
		const nodes = self.nodes.load(.acquire);
		const pv = info.rms.slice()[0];
		const time = base.time.read(.ns) - self.options.start * std.time.ns_per_ms;

		try io.writer.print("info", .{});
		try io.writer.print(" depth {d}", .{depth});
		try io.writer.print(" time {d}", .{time / std.time.ns_per_ms});
		try io.writer.print(" nodes {d}", .{nodes});
		try io.writer.print(" pv", .{});
		for (pv.slice()) |m| {
			const s = m.toString();
			const l = m.toStringLen();
			try io.writer.print(" {s}", .{s[0 .. l]});
		}
		switch (pv.score) {
			evaluation.score.lose ... evaluation.score.tblose => {
				const s = pv.score - evaluation.score.tblose;
				try io.writer.print(" score mate {d}", .{s});
			},

			evaluation.score.tbwin ... evaluation.score.win => {
				const s = pv.score - evaluation.score.tbwin;
				try io.writer.print(" score mate {d}", .{s});
			},

			else => {
				const s: i32 = @intCast(pv.score);
				try io.writer.print(" score cp {d}", .{evaluation.score.toCentipawns(s)});
			},
		}
		try io.writer.print(" nps {d}", .{nodes * std.time.ns_per_s / time});
		try io.writer.print("\n", .{});
		try io.writer.flush();
	}

	pub fn alloc(self: *Instance, num: usize) !void {
		var pos = std.mem.zeroInit(Position, .{});
		if (self.infos.len == 0) {
			try pos.parseFen(Position.startpos);
			self.infos = try base.heap.allocator.alignedAlloc(Info, .@"64", num);
		} else {
			@memcpy((&pos)[0 .. 1], (&self.infos[0].pos)[0 .. 1]);
			self.infos = try base.heap.allocator.realloc(self.infos, num);
		}

		for (self.infos) |*info| {
			info.instance = self;
			info.options = &self.options;

			@memcpy((&info.pos)[0 .. 1], (&pos)[0 .. 1]);
		}
	}

	pub fn reset(self: *Instance) void {
		var pos = std.mem.zeroInit(Position, .{});
		pos.parseFen(Position.startpos) catch std.debug.panic("invalid position", .{});

		for (self.infos) |*info| {
			info.* = std.mem.zeroInit(Info, .{
				.instance = self,
				.options = &self.options,
			});

			@memcpy((&info.pos)[0 .. 1], (&pos)[0 .. 1]);
		}
	}

	pub fn think(self: *Instance) !void {
		self.nodes = @TypeOf(self.nodes).init(0);
		self.tbhits = @TypeOf(self.tbhits).init(0);
		self.tthits = @TypeOf(self.tthits).init(0);

		const options = &self.options;
		const searching = &options.is_searching;
		searching.store(true, .release);
		defer searching.store(false, .release);

		const is_threaded = switch (self.infos.len) {
			0 => return,
			1 => false,
			else => true,
		};
		for (self.infos, 0 ..) |*info, i| {
			info.depth = 1;

			info.rms.clear();
			info.rmi = 0;

			info.ti = i;
			info.tn = self.infos.len;
		}

		const pos = &self.infos[0].pos;
		self.root_moves = movegen.Move.Root.List.init(pos);
		if (self.root_moves.constSlice().len == 0) {
			if (self == &uci.instance) {
				try io.writer.print("bestmove 0000\n", .{});
				try io.writer.flush();
			}
			return;
		}
		for (self.root_moves.slice(), 0 ..) |*rm, i| {
			const tn = self.infos.len;
			const ti = i % tn;
			const info = &self.infos[ti];

			try info.rms.append(rm);
			info.rmi = 0;
		}

		var pool: std.Thread.Pool = undefined;
		var wg: std.Thread.WaitGroup = .{};

		if (is_threaded) {
			try pool.init(.{
				.allocator = base.heap.allocator,
				.n_jobs = self.infos[0].tn,
			});
		}
		defer if (is_threaded) {
			pool.deinit();
		};

		const max_depth = options.depth orelse 240;
		const min_depth = 1;
		var depth: u8 = min_depth;

		while (depth <= max_depth and searching.load(.acquire)) : (depth += 1) {
			for (self.infos) |*info| {
				info.depth = 0;
				info.depth += @intCast(depth);
				info.depth += @intFromBool(depth > 1 and info.ti % 2 == 0);

				if (is_threaded) {
					pool.spawnWg(&wg, Info.think, .{info});
				} else {
					info.think();
				}
			}
			if (is_threaded) {
				pool.waitAndWork(&wg);
				wg.reset();
			}

			_ = transposition.table.age.fetchAdd(1, .acq_rel);
			movegen.Move.Root.sortSlice(self.root_moves.slice());
			try self.printInfo();
		}
		try self.printBest();
	}

	pub fn spawn(self: *Instance) !void {
		const id = try std.Thread.spawn(.{.allocator = base.heap.allocator}, think, .{self});
		std.Thread.detach(id);
	}
};

pub const Options = struct {
	infinite:		bool = true,
	depth:	?Depth,
	nodes:	?u64,
	movetime:	?u64,

	incr:	std.EnumArray(base.types.Color, ?u64),
	time:	std.EnumArray(base.types.Color, ?u64),

	start:	u64,
	stop:	?u64,

	is_searching:	std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

	pub fn reset(self: *Options) void {
		self.* = std.mem.zeroInit(Options, .{
			.start = base.time.read(.ms),
		});
	}
};

pub const hist = struct {
	pub const Int = i16;

	pub const Correction = enum {
		pawn,
		minor,
		major,

		pub const values = std.enums.values(Correction);
	};

	pub const min = std.math.minInt(Int) / 2;
	pub const max = -min;

	pub fn bonus(p: *Int, b: evaluation.score.Int) void {
		const clamped = std.math.clamp(b, min, max);
		const abs = switch (clamped) {
			min ... -1 => -clamped,
			0 ... max => clamped,
			else => std.debug.panic("integer overflow: {d}", .{clamped}),
		};

		const curr: evaluation.score.Int = p.*;
		const next = curr + clamped - @divTrunc(curr * abs, max);
		p.* = @intCast(next);
	}

	pub fn malus(p: *Int, m: evaluation.score.Int) void {
		bonus(p, -m);
	}
};

pub const io = struct {
	const stdin = std.fs.File.stdin();
	const stdout = std.fs.File.stdout();

	const reader = &std_reader.interface;
	const writer = &std_writer.interface;

	var reader_buf align(32) = std.mem.zeroes([65536]u8);
	var writer_buf align(32) = std.mem.zeroes([65536]u8);

	var std_reader = stdin.readerStreaming(&reader_buf);
	var std_writer = stdout.writerStreaming(&writer_buf);
};

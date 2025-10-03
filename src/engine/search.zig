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
	nodes:	u64,

	instance:	*const Instance,
	options:	*const Options,

	ti:	usize,
	tn:	usize,

	rms:	bounded_array.BoundedArray(*movegen.Move.Root, 256)
	  = bounded_array.BoundedArray(*movegen.Move.Root, 256).init(0) catch unreachable,
	rmi:	usize,

	fn aspiration(self: *Info,
	  rm: *movegen.Move.Root,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int) evaluation.score.Int {
		self.pos.doMove(rm.line.slice()[0]) catch std.debug.panic("invalid root move", .{});
		defer self.pos.undoMove();

		const a = alpha;
		const b = beta;
		const d = self.depth;

		var s: @TypeOf(a) = @intCast(rm.score);
		defer rm.score = s;

		if (self.instance.hardStop()) {
			return s;
		}

		if (self.ti != 0 or rm != self.rms.slice()[0]) {
			s = -self.ab(.lowerbound, 1, -a - 1, -a, d - 1);
		}

		var lo = std.math.clamp(s - evaluation.score.unit / 4, a, b);
		var hi = std.math.clamp(s + evaluation.score.unit / 4, a, b);

		while (!self.instance.hardStop() and s > a and s < b) {
			s = -self.ab(.exact, 1, -hi, -lo, d - 1);

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
		const b = beta;
		var a = alpha;

		var d = depth;
		if (d <= 0) {
			return self.qs(node, ply, a, b);
		}

		const pos = &self.pos;
		const key = pos.ss.top().key;
		const is_checked = pos.isChecked();

		const nodes = @constCast(self.instance).nodes.rmw(.Add, 1, .monotonic);
		const draw
		  = @as(evaluation.score.Int, evaluation.score.draw)
		  + @as(evaluation.score.Int, @as(u4, @truncate(nodes))) - 8;

		const lose
		  = @as(evaluation.score.Int, evaluation.score.lose)
		  + @as(evaluation.score.Int, @intCast(ply));

		if (pos.isDrawn()) {
			@branchHint(.unlikely);
			return draw;
		}

		const ttf = transposition.table.fetch(key);
		const tte = ttf[0];
		const tth = ttf[1];

		if (tth and tte.shouldTrust(a, b, d)) {
			return tte.score;
		}

		// internal iterative reduction (iir)
		// stc: ~2.8 +- good enough
		const has_ttm = tth and tte.move != movegen.Move.zero;
		if (!has_ttm and d > 3) {
			d -= 2;
		}

		if (is_checked) {
			pos.ss.top().stat_eval = evaluation.score.none;
			pos.ss.top().corr_eval = evaluation.score.none;
		} else {
			pos.ss.top().stat_eval = if (tth) tte.eval else evaluation.score.fromPosition(pos);
			pos.ss.top().corr_eval = pos.ss.top().stat_eval;
		}

		const corr_eval = pos.ss.top().corr_eval;
		const stat_eval = pos.ss.top().stat_eval;

		if (self.instance.hardStop()) {
			return if (corr_eval != evaluation.score.none) corr_eval
			  else draw + evaluation.score.fromPosition(pos);
		}

		// reverse futility pruning (rfp)
		// stc: ~4.5 +- 4.3
		if (!is_checked
		  and node == .lowerbound
		  and !(tth and tte.was_pv)
		  and !(tth and tte.move == movegen.Move.zero)
		  and !(tth and pos.isMoveNoisy(tte.move))
		  and corr_eval >= b
		  and stat_eval >= b + d * 384) {
			return @divTrunc(stat_eval + b, 2);
		}

		// null move pruning (nmr)
		// stc: ~9.8 +- i forgot
		if (!is_checked
		  and node == .lowerbound
		  and corr_eval >= b
		  and stat_eval >= b) {
			pos.doNull() catch std.debug.panic("invalid null move", .{});
			defer pos.undoNull();

			const nd = d - 4;
			const ns = -self.ab(.lowerbound, ply + 1, -b, 1 - b, nd - 1);

			if (ns >= b) {
				return ns;
			}
		}

		var best: movegen.Move.Scored = .{
			.move = .{},
			.score = evaluation.score.none,
		};
		var flag = Node.upperbound;

		var mi: usize = 0;
		var mp = movegen.Picker.init(self, false, tte.move);

		while (mp.next()) |sm| {
			if (self.instance.hardStop()) {
				break;
			}

			var r: Depth = 0;

			const m = sm.move;
			const is_noisy = pos.isMoveNoisy(m);
			const is_quiet = !is_noisy;
			const is_ttm = m == tte.move;

			if (is_ttm and !pos.isMovePseudoLegal(m)) {
				// @branchHint(.unlikely);
				continue;
			}

			pos.doMove(m) catch continue;
			defer pos.undoMove();
			defer mi += 1;

			const child: @TypeOf(node) = switch (node) {
				.upperbound => .lowerbound,
				.exact => if (mi == 0) .exact else .lowerbound,
				.lowerbound => if (mi == 0) .upperbound else .lowerbound,
				else => std.debug.panic("invalid node", .{}),
			};

			if (d >= 3 and mi >= 3
			  and !is_checked
			  and !pos.isChecked()
			  and node != .exact
			  and child != .exact) {
				const clamped_d: usize = @intCast(@min(d, 31));
				const clamped_i: usize = @min(mi, 31);

				r += (&params.search.lmr)[clamped_d][clamped_i][@intFromBool(is_quiet)];
			}

			r = @max(r, 0);
			const s = -self.ab(child, ply + 1, if (child == .exact) -b else -a - 1, -a, d - r - 1);

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

		tte.* = .{
			.was_pv = flag == .exact or (tth and tte.was_pv),
			.flag = flag,
			.age = @truncate(transposition.table.age),
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

		const nodes = @constCast(self.instance).nodes.rmw(.Add, 1, .monotonic);
		const draw
		  = @as(evaluation.score.Int, evaluation.score.draw)
		  + @as(evaluation.score.Int, @as(u4, @truncate(nodes))) - 8;

		const lose
		  = @as(evaluation.score.Int, evaluation.score.lose)
		  + @as(evaluation.score.Int, @intCast(ply));

		if (pos.isDrawn()) {
			@branchHint(.unlikely);
			return draw;
		}

		const ttf = transposition.table.fetch(key);
		const tte = ttf[0];
		const tth = ttf[1];

		if (tth and tte.shouldTrust(a, b, 0)) {
			return tte.score;
		}

		if (is_checked) {
			pos.ss.top().stat_eval = evaluation.score.none;
			pos.ss.top().corr_eval = evaluation.score.none;
		} else {
			pos.ss.top().stat_eval = if (tth) tte.eval else evaluation.score.fromPosition(pos);
			pos.ss.top().corr_eval = pos.ss.top().stat_eval;
		}

		const corr_eval = pos.ss.top().corr_eval;
		const stat_eval = pos.ss.top().stat_eval;

		if (self.instance.hardStop()) {
			return if (corr_eval != evaluation.score.none) corr_eval
			  else draw + evaluation.score.fromPosition(pos);
		}

		var best: movegen.Move.Scored = .{
			.move = .{},
			.score = evaluation.score.none,
		};
		var flag = Node.upperbound;

		var mi: usize = 0;
		var mp = movegen.Picker.init(self, !is_checked, tte.move);

		while (mp.next()) |sm| {
			if (self.instance.hardStop()) {
				break;
			}

			const m = sm.move;
			const is_ttm = m == tte.move;

			if (is_ttm and !pos.isMovePseudoLegal(m)) {
				// @branchHint(.unlikely);
				continue;
			}

			pos.doMove(m) catch continue;
			defer pos.undoMove();
			defer mi += 1;

			const child: @TypeOf(node) = switch (node) {
				.upperbound => .lowerbound,
				.exact => if (mi == 0) .exact else .lowerbound,
				.lowerbound => if (mi == 0) .upperbound else .lowerbound,
				else => std.debug.panic("invalid node", .{}),
			};
			const s = -self.qs(child, ply + 1, if (child == .exact) -b else -a - 1, -a);

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
			return if (is_checked) lose else draw + corr_eval;
		}

		tte.* = .{
			.was_pv = flag == .exact or (tth and tte.was_pv),
			.flag = flag,
			.age = @truncate(transposition.table.age),
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

	nodes:	std.atomic.Value(u64) = .{ .raw = 0 },
	tbhits:	std.atomic.Value(u64) = .{ .raw = 0 },
	tthits:	std.atomic.Value(u64) = .{ .raw = 0 },

	fn hardStop(self: *const Instance) bool {
		const options = &self.options;

		if (!options.is_searching.load(.monotonic)) {
			return true;
		}

		if (options.infinite) {
			return false;
		}

		if (options.nodes) |lim| {
			const nodes = self.nodes.load(.monotonic);
			if (nodes >= lim) {
				@constCast(options).is_searching.store(false, .monotonic);
				return true;
			}
		}

		if (options.stop) |lim| {
			const time = base.time.read(.ms);
			if (time >= lim) {
				@constCast(options).is_searching.store(false, .monotonic);
				return true;
			}
		}

		return false;
	}

	fn printBest(self: *const Instance) !void {
		if (self != &uci.instance) {
			return;
		}

		const pv = self.infos[0].rms.slice()[0];
		const m = pv.slice()[0];
		const s = m.toString();
		const l = m.toStringLen();

		if (m == movegen.Move.zero) {
			try io.writer.print("bestmove 0000\n", .{});
			try io.writer.flush();
			return;
		}

		try io.writer.print("bestmove {s}", .{s[0 .. l]});
		try io.writer.print("\n", .{});
		try io.writer.flush();
	}

	fn printInfo(self: *const Instance) !void {
		if (self != &uci.instance) {
			return;
		}

		const info = &self.infos[0];
		const depth = if (info.depth == 1) info.depth else info.depth - 1;
		const nodes = self.nodes.load(.monotonic);
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

			evaluation.score.tblose + 1 ... evaluation.score.tbwin - 1 => {
				const s: i32 = @intCast(pv.score);
				try io.writer.print(" score cp {d}", .{evaluation.score.toCentipawns(s)});
			},

			else => std.debug.panic("out of bounds", .{}),
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
		self.nodes = .{ .raw = 0 };
		self.tbhits = .{ .raw = 0 };
		self.tthits = .{ .raw = 0 };
		self.options.is_searching.store(true, .monotonic);
		defer self.options.is_searching.store(false, .monotonic);

		if (self.infos.len == 0) {
			return;
		}
		for (self.infos, 0 ..) |*info, i| {
			info.depth = 1;

			info.rms.clear();
			info.rmi = 0;

			info.ti = i;
			info.tn = self.infos.len;
		}

		self.root_moves = movegen.Move.Root.List.init(self);
		if (self.root_moves.slice().len == 0) {
			const is_checked = self.infos[0].pos.isChecked();

			try self.root_moves.array.resize(0);
			try self.root_moves.array.append(.{
				.line = .{
					.buffer = .{movegen.Move.zero} ** movegen.Move.Root.capacity,
					.len = 1,
				},
				.score = if (is_checked) evaluation.score.lose else evaluation.score.draw,
			});

			try self.printInfo();
			try self.printBest();

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

		try pool.init(.{
			.allocator = base.heap.allocator,
			.n_jobs = self.infos[0].tn,
		});
		defer pool.deinit();

		const max_d: u8 = @intCast(self.options.depth orelse 240);
		for (1 .. max_d + 1) |d| {
			wg.reset();
			for (self.infos) |*info| {
				info.depth = 0;
				info.depth += @intCast(d);
				info.depth += @intFromBool(d > 1 and info.ti % 2 == 0);

				pool.spawnWg(&wg, Info.think, .{info});
			}
			pool.waitAndWork(&wg);

			movegen.Move.Root.sortSlice(self.root_moves.slice());
			try self.printInfo();

			if (self.hardStop()) {
				break;
			}
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

	is_searching:	std.atomic.Value(bool) = .{ .raw = false },

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
		const abs: @TypeOf(clamped) = @intCast(clamped);

		const curr = @as(i32, p.*);
		const next
		  = curr
		  + clamped
		  - @divTrunc(curr * abs, max);
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

	var reader_buf align(std.heap.page_size_max) = std.mem.zeroes([4096]u8);
	var writer_buf align(std.heap.page_size_max) = std.mem.zeroes([4096]u8);

	var std_reader = stdin.reader(&reader_buf);
	var std_writer = stdout.writer(&writer_buf);
};

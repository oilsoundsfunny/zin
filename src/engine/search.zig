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
	instance:	*const Instance,
	options:	*const Options,

	ti:	usize,
	tn:	usize,

	nodes:	usize,
	tbhits:	usize,
	tthits:	usize,

	depth:		Depth,
	seldepth:	Depth,
	root_moves:	movegen.Move.Root.List,

	allhist:	[base.types.Ptype.cnt][base.types.Square.cnt]hist.Int,
	cuthist:	[base.types.Ptype.cnt][base.types.Square.cnt]hist.Int,

	fn bestMove(self: *const Info) movegen.Move {
		const pv = &self.root_moves.constSlice()[0];
		return if (pv.line.len == 0) movegen.Move.zero else pv.constSlice()[0];
	}

	fn printInfo(self: *const Info) !void {
		if (self.instance != &uci.instance) {
			return;
		}

		const best = self.bestMove();
		const nodes = self.nodes;
		const ntime = base.time.read(.ns) - self.options.start * std.time.ns_per_ms;
		const mtime = ntime / std.time.ns_per_ms;

		const depth = self.depth;
		const seldepth = self.seldepth;
		const pv = &self.root_moves.constSlice()[0];

		if (best == movegen.Move.zero) {
			return;
		}

		try io.writer().print("info", .{});
		try io.writer().print(" depth {d}", .{depth});
		try io.writer().print(" seldepth {d}", .{seldepth});

		try io.writer().print(" nodes {d}", .{nodes});
		try io.writer().print(" time {d}", .{mtime});
		try io.writer().print(" nps {d}", .{nodes * std.time.ns_per_s / ntime});

		try io.writer().print(" score", .{});
		switch (pv.score) {
			evaluation.score.lose ... evaluation.score.tblose => |pvs| {
				const s = @divTrunc(pvs - evaluation.score.lose + 1, 2);
				try io.writer().print(" mate {d}", .{-s});
			},
			evaluation.score.tbwin ... evaluation.score.win => |pvs| {
				const s = @divTrunc(evaluation.score.win - pvs + 1, 2);
				try io.writer().print(" mate {d}", .{s});
			},
			else => |pvs| {
				const s = evaluation.score.toCentipawns(@intCast(pvs));
				try io.writer().print(" cp {d}", .{s});
			},
		}

		try io.writer().print(" pv", .{});
		for (pv.constSlice()) |m| {
			const s = m.toString();
			const l = m.toStringLen();
			try io.writer().print(" {s}", .{s[0 .. l]});
		}

		try io.writer().print("\n", .{});
		try io.writer().flush();
	}

	fn printBest(self: *const Info) !void {
		if (self.instance != &uci.instance) {
			return;
		}

		const m = self.bestMove();
		if (m == movegen.Move.zero) {
			try io.writer().print("bestmove 0000\n", .{});
			try io.writer().flush();
			return;
		}

		const s = m.toString();
		const l = m.toStringLen();
		try io.writer().print("bestmove {s}\n", .{s[0 .. l]});
		try io.writer().flush();
	}

	fn iid(self: *Info) !void {
		const has_moves = self.root_moves.constSlice().len > 0;
		const is_main = self.ti == 0;
		const is_threaded = self.tn > 1;

		const options = self.options;
		const cond = &options.is_searching;

		const max_depth = options.depth orelse movegen.Move.Root.capacity;
		const min_depth = 1;
		var depth: Depth = min_depth;

		while (has_moves and depth <= max_depth) : (depth += 1) {
			self.depth = depth + @intFromBool(is_threaded
			  and self.ti % 2 == 1
			  and depth > min_depth
			  and depth < max_depth);
			self.seldepth = 0;
			self.asp();

			movegen.Move.Root.sortSlice(self.root_moves.slice());
			if (!cond.load(.acquire)) {
				break;
			}

			if (is_main) {
				std.mem.doNotOptimizeAway(transposition.table.age.fetchAdd(1, .acq_rel));
				try self.printInfo();
			}
		}

		if (is_main) {
			try self.printInfo();
			try self.printBest();
		}
	}

	fn asp(self: *Info) void {
		const options = self.options;
		const cond = &options.is_searching;

		const pv = &self.root_moves.constSlice()[0];
		const pvs: evaluation.score.Int = @intCast(pv.score);

		var s: @TypeOf(pvs) = evaluation.score.none;
		var w: @TypeOf(pvs) = evaluation.score.unit;

		const d = self.depth;
		var a: @TypeOf(pvs) = evaluation.score.lose;
		var b: @TypeOf(pvs) = evaluation.score.win;
		if (d >= 3) {
			a = std.math.clamp(pvs - w, evaluation.score.lose, evaluation.score.win);
			b = std.math.clamp(pvs + w, evaluation.score.lose, evaluation.score.win);
		}

		while (true) : (w *= 2) {
			s = self.ab(.exact, 0, a, b, d);
			if (!cond.load(.acquire)) {
				return;
			}

			if (s <= a) {
				b = @divTrunc(a + b, 2);
				a = std.math.clamp(a - w, evaluation.score.lose, evaluation.score.win);
			} else if (s >= b) {
				a = @divTrunc(a + b, 2);
				b = std.math.clamp(b + w, evaluation.score.lose, evaluation.score.win);
			} else break;
		}

		if (!cond.load(.acquire)) {
			return;
		}
	}

	fn ab(self: *Info,
	  node: Node,
	  ply: usize,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int,
	  depth: Depth) evaluation.score.Int {
		const mate: evaluation.score.Int = @intCast(evaluation.score.win - ply);
		const mated = -mate;

		const draw: evaluation.score.Int = evaluation.score.draw;
		const lose: evaluation.score.Int = mated;

		const cond = @constCast(&self.options.is_searching);
		if (!cond.load(.acquire)) {
			return draw;
		}

		const d = depth;
		var b = beta;
		var a = alpha;

		// mate dist pruning
		a = @max(a, mated);
		b = @min(b, mate + 1);
		if (a >= b) {
			return a;
		}

		if (d <= 0) {
			return self.qs(ply, a, b);
		}

		const is_pv = node == .exact;
		const is_root = ply == 0;

		if (is_pv) {
			self.seldepth = @max(self.seldepth, @as(Depth, @intCast(ply + 1)));
			self.pos.ss.top().pv.line.resize(0) catch unreachable;
		}

		self.nodes += 1;
		const nodes = self.nodes;

		if (self.ti == 0) {
			const options = self.options;

			const inf = options.infinite;
			const exceed_time = options.stop != null
			  and nodes % 2048 == 0
			  and base.time.read(.ms) >= options.stop.?;
			const exceed_nodes = options.nodes != null and nodes >= options.nodes.?;

			if (!inf and (exceed_time or exceed_nodes)) {
				cond.store(false, .release);
				return draw;
			}
		}

		const pos = &self.pos;
		const key = pos.ss.top().key;
		const is_checked = pos.isChecked();
		if (pos.isDrawn()) {
			return draw;
		} else if (pos.ss.isFull()) {
			return pos.evaluate();
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
		const use_ttscore = tth
		  and tte.score < evaluation.score.tbwin
		  and tte.score > evaluation.score.tblose
		  and !(tte.flag == .upperbound and tte.score >  pos.ss.top().stat_eval)
		  and !(tte.flag == .lowerbound and tte.score <= pos.ss.top().stat_eval);
		const was_pv = tth and tte.was_pv;

		if (tth and tte.shouldTrust(a, b, d)) {
			return tte.score;
		}

		pos.ss.top().stat_eval = if (is_checked) evaluation.score.none
		  else if (has_tteval) tte.eval
		  else pos.evaluate();
		pos.ss.top().corr_eval = if (use_ttscore) tte.score else pos.ss.top().stat_eval;

		const stat_eval = pos.ss.top().stat_eval;
		const corr_eval = pos.ss.top().corr_eval;
		_ = &stat_eval;
		_ = &corr_eval;

		// reverse futility pruning (rfp)
		if (!is_pv
		  and !is_checked
		  and d < 8
		  and corr_eval >= b + d * 96) {
			return @divTrunc(corr_eval + b, 2);
		}

		var best: movegen.Move.Scored = .{
			.move = .{},
			.score = evaluation.score.none,
		};
		var flag = transposition.Entry.Flag.upperbound;

		var mi: usize = 0;
		var mp = movegen.Picker.init(self, ttm);

		move_loop: while (mp.next()) |sm| {
			const m = sm.move;
			const s = recur: {
				pos.doMove(m) catch continue :move_loop;
				defer pos.undoMove();
				defer mi += 1;

				const child: Node = switch (node) {
					.upperbound => .lowerbound,
					.lowerbound => if (mi == 0) .upperbound else .lowerbound,
					.exact => if (mi == 0) .exact else .lowerbound,
					else => std.debug.panic("invalid node", .{}),
				};

				var score = -self.ab(child, ply + 1,
				  if (child == .exact) -b else -a - 1, -a, d - 1);
				if (child != .exact and score > a and score < b) {
					score = -self.ab(.exact, ply + 1, -b, -a, d - 1);
				}
				break :recur score;
			};

			if (!cond.load(.acquire)) {
				return draw;
			}

			std.debug.assert(best.score <= a);
			std.debug.assert(a < b);

			const first_rm = is_root and mi == 1;
			const pv_found = is_pv and s > a;

			if (is_root) {
				const rms = self.root_moves.slice();
				var rmi: usize = 0;
				while (rms[rmi].line.constSlice()[0] != m) : (rmi += 1) {
				}

				const next_pv = &pos.ss.top().up(1).pv;
				const rm = &rms[rmi];
				if (pv_found or first_rm) {
					rm.update(s, m, next_pv.constSlice());
				} else {
					rm.score = evaluation.score.lose;
				}
			}

			if (s > best.score) {
				best.score = @intCast(s);

				if (pv_found or first_rm) {
					const next_pv = &pos.ss.top().up(1).pv;
					const this_pv = &pos.ss.top().pv;

					this_pv.update(s, m, next_pv.constSlice());
				}

				if (s > a) {
					a = s;
					best.move = m;
					flag = .exact;
				}

				if (s >= b) {
					flag = .lowerbound;
					break :move_loop;
				}
			}
		}

		if (mi == 0) {
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
			.move = if (best.move != movegen.Move.zero) best.move else ttm,
		};

		return best.score;
	}

	fn qs(self: *Info,
	  ply: usize,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int) evaluation.score.Int {
		const draw = evaluation.score.draw;
		const lose = evaluation.score.lose + 1;

		const cond = @constCast(&self.options.is_searching);
		if (!cond.load(.acquire)) {
			return evaluation.score.draw;
		}

		self.nodes += 1;
		self.pos.ss.top().pv.line.resize(0) catch unreachable;

		const nodes = self.nodes;
		if (self.ti == 0) {
			const options = self.options;

			const inf = options.infinite;
			const exceed_time = options.stop != null
			  and nodes % 2048 == 0
			  and base.time.read(.ms) >= options.stop.?;
			const exceed_nodes = options.nodes != null and nodes >= options.nodes.?;

			if (!inf and (exceed_time or exceed_nodes)) {
				cond.store(false, .release);
				return draw;
			}
		}

		const b = beta;
		var a = alpha;

		const pos = &self.pos;
		const key = pos.ss.top().key;
		const is_checked = pos.isChecked();
		if (pos.isDrawn()) {
			return draw;
		} else if (pos.ss.isFull()) {
			return pos.evaluate();
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
		// const is_pv = node == .exact;
		const use_ttscore = tth
		  and tte.score < evaluation.score.tbwin
		  and tte.score > evaluation.score.tblose
		  and !(tte.flag == .upperbound and tte.score >  pos.ss.top().stat_eval)
		  and !(tte.flag == .lowerbound and tte.score <= pos.ss.top().stat_eval);

		if (tth and tte.shouldTrust(a, b, 0)) {
			return tte.score;
		}

		pos.ss.top().stat_eval = if (is_checked) evaluation.score.none
		  else if (has_tteval) tte.eval
		  else pos.evaluate();
		pos.ss.top().corr_eval = if (use_ttscore) tte.score else pos.ss.top().stat_eval;

		const stat_eval = pos.ss.top().stat_eval;
		const corr_eval = pos.ss.top().corr_eval;
		_ = &stat_eval;
		_ = &corr_eval;

		if (stat_eval >= b) {
			return stat_eval;
		}
		a = @max(a, stat_eval);

		var best: movegen.Move.Scored = .{
			.move = .{},
			.score = @intCast(stat_eval),
		};
		var flag = transposition.Entry.Flag.upperbound;

		var mi: usize = 0;
		var mp = movegen.Picker.init(self, ttm);
		if (!is_checked) {
			mp.skipQuiets();
		}

		move_loop: while (mp.next()) |sm| {
			if (best.score > evaluation.score.tblose and mp.stage.isBad()) {
				break;
			}

			const m = sm.move;
			const s = recur: {
				pos.doMove(m) catch continue :move_loop;
				defer pos.undoMove();
				defer mp.skipQuiets();
				defer mi += 1;

				break :recur -self.qs(ply + 1, -b, -a);
			};

			if (!cond.load(.acquire)) {
				return draw;
			}

			if (s > best.score) {
				best.score = @intCast(s);

				if (s > a) {
					a = s;
					best.move = m;

					if (a >= b) {
						flag = .lowerbound;
						break :move_loop;
					}
				}
			}
		}

		if (mi == 0 and is_checked) {
			return lose;
		}

		ttf[0].* = .{
			.was_pv = false,
			.flag = flag,
			.age = @truncate(transposition.table.age.load(.acquire)),
			.depth = 0,
			.key = @truncate(key),
			.eval = @intCast(stat_eval),
			.score = best.score,
			.move = if (best.move != movegen.Move.zero) best.move else ttm,
		};

		return best.score;
	}
};

pub const Instance = struct {
	infos:	[]Info = &.{},
	options:	Options = std.mem.zeroInit(Options, .{}),

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

	pub fn waitStop(self: *const Instance) void {
		const cond = &self.options.is_searching;
		while (cond.load(.acquire)) {
		}
	}

	pub fn stop(self: *Instance) void {
		self.options.is_searching.store(false, .release);
		std.Thread.sleep(uci.options.overhead * std.time.ns_per_ms);
	}

	pub fn start(self: *Instance) !void {
		self.options.is_searching.store(true, .release);

		const pos = &self.infos[0].pos;
		const rml = movegen.Move.Root.List.init(pos);

		for (self.infos, 0 ..) |*info, i| {
			info.* = std.mem.zeroInit(Info, .{
				.pos = info.pos,
				.instance = self,
				.options = &self.options,

				.ti = i,
				.tn = self.infos.len,

				.root_moves = rml,
			});

			const config: std.Thread.SpawnConfig = .{
				.stack_size = 16 * 1024 * 1024,
				.allocator = base.heap.allocator,
			};
			const thread = try std.Thread.spawn(config, Info.iid, .{info});
			std.Thread.detach(thread);
		}
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

	pub const Corr = enum {
		pawn,
		minor,
		major,

		pub const values = std.enums.values(Corr);
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

pub var io: base.Io = undefined;

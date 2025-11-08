const bounded_array = @import("bounded_array");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const Position = @import("Position.zig");
const transposition = @import("transposition.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

pub const Depth = isize;
pub const Node = transposition.Entry.Flag;

pub const Thread = struct {
	pos:	Position,
	pool:	*Pool,

	nodes:	usize,
	tbhits:	usize,
	tthits:	usize,

	depth:		Depth,
	seldepth:	Depth,
	root_moves:	movegen.Move.Root.List,

	nmp_verif:	bool,
	bfhist:	[types.Ptype.cnt][types.Square.cnt]hist.Int,

	const zero: Thread = .{
		.pos = Position.zero,
		.pool = undefined,

		.nodes = 0,
		.tbhits = 0,
		.tthits = 0,

		.depth = 0,
		.seldepth = 0,
		.root_moves = .{},

		.nmp_verif = false,
		.bfhist = @splat(@splat(evaluation.score.draw)),
	};

	fn reset(self: *Thread, pool: *Pool) void {
		self.* = zero;
		self.pool = pool;
	}

	fn idx(self: *const Thread) usize {
		return self - &self.pool.threads[0];
	}

	fn cnt(self: *const Thread) usize {
		return self.pool.threads.len;
	}

	fn bestMove(self: *const Thread) movegen.Move {
		const pv = &self.root_moves.constSlice()[0];
		return if (pv.line.len > 0) pv.constSlice()[0] else movegen.Move.zero;
	}

	fn printInfo(self: *const Thread) !void {
		if (self.pool.quiet) {
			return;
		}

		const writer = self.pool.io.writer();
		const timer = &self.pool.timer;

		const best = self.bestMove();
		const nodes = self.pool.nodes();
		const ntime = timer.read();
		const mtime = ntime / std.time.ns_per_ms;

		const depth = self.depth;
		const seldepth = self.seldepth;
		const pv = &self.root_moves.constSlice()[0];

		if (best.isZero()) {
			return;
		}

		self.pool.io.lockWriter();
		defer self.pool.io.unlockWriter();

		try writer.print("info", .{});
		try writer.print(" depth {d}", .{depth});
		try writer.print(" seldepth {d}", .{seldepth});

		try writer.print(" nodes {d}", .{nodes});
		try writer.print(" time {d}", .{mtime});
		try writer.print(" nps {d}", .{nodes * std.time.ns_per_s / ntime});

		try writer.print(" score", .{});
		switch (pv.score) {
			evaluation.score.lose ... evaluation.score.tblose => |pvs| {
				const s = @divTrunc(pvs - evaluation.score.lose + 1, 2);
				try writer.print(" mate {d}", .{-s});
			},
			evaluation.score.tbwin ... evaluation.score.win => |pvs| {
				const s = @divTrunc(evaluation.score.win - pvs + 1, 2);
				try writer.print(" mate {d}", .{s});
			},
			else => |pvs| {
				const s = evaluation.score.centipawns(@intCast(pvs));
				try writer.print(" cp {d}", .{s});
			},
		}

		try writer.print(" pv", .{});
		for (pv.constSlice()) |m| {
			const s = m.toString(&self.pos);
			const l = m.toStringLen();
			try writer.print(" {s}", .{s[0 .. l]});
		}

		try writer.print("\n", .{});
		try writer.flush();
	}

	fn printBest(self: *const Thread) !void {
		if (self.pool.quiet) {
			return;
		}

		self.pool.io.lockWriter();
		defer self.pool.io.unlockWriter();

		const m = self.bestMove();
		if (m.isZero()) {
			try self.pool.io.writer().print("bestmove 0000\n", .{});
			try self.pool.io.writer().flush();
			return;
		}

		const s = m.toString(&self.pos);
		const l = m.toStringLen();
		try self.pool.io.writer().print("bestmove {s}\n", .{s[0 .. l]});
		try self.pool.io.writer().flush();
	}

	fn iid(self: *Thread) !void {
		const is_main = self.idx() == 0;
		const is_threaded = self.cnt() > 1;

		if (is_main) {
			defer self.pool.is_searching = true;
			self.pool.prep();
			self.pool.timer.reset();
		} else self.pool.waitStart();

		const has_moves = self.root_moves.constSlice().len > 0;
		const max_depth = self.pool.options.depth orelse movegen.Move.Root.capacity;
		const min_depth = 1;
		var depth: Depth = min_depth;

		while (has_moves and depth <= max_depth) : (depth += 1) {
			self.depth = depth + @intFromBool(is_threaded
			  and self.idx() % 2 == 1
			  and depth > min_depth
			  and depth < max_depth);
			self.seldepth = 0;
			self.asp();

			movegen.Move.Root.sortSlice(self.root_moves.slice());
			if (!self.pool.is_searching) {
				break;
			}

			if (is_main) {
				self.pool.tt.doAge();
				try self.printInfo();
			}
		}

		if (is_main) {
			defer self.pool.stop();
			try self.printInfo();
			try self.printBest();
		} else self.pool.waitStop();
	}

	fn asp(self: *Thread) void {
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
			if (!self.pool.is_searching) {
				break;
			}

			if (s <= a) {
				b = @divTrunc(a + b, 2);
				a = std.math.clamp(a - w, evaluation.score.lose, evaluation.score.win);
			} else if (s >= b) {
				a = @divTrunc(a + b, 2);
				b = std.math.clamp(b + w, evaluation.score.lose, evaluation.score.win);
			} else break;
		}
	}

	fn ab(self: *Thread,
	  node: Node,
	  ply: usize,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int,
	  depth: Depth) evaluation.score.Int {
		self.nodes += 1;
		self.pos.ss.top().pv.line.resize(0) catch unreachable;

		const d = depth;
		var b = beta;
		var a = alpha;

		const mate: @TypeOf(a, b) = @intCast(evaluation.score.win - ply);
		const mated = -mate;

		const draw: @TypeOf(a, b) = evaluation.score.draw;
		const lose: @TypeOf(a, b) = mated;

		if (!self.pool.is_searching) {
			return draw;
		}

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
		const is_main = self.idx() == 0;
		const is_root = ply == 0;

		if (is_pv) {
			self.seldepth = @max(self.seldepth, @as(Depth, @intCast(ply + 1)));
		}

		if (is_main and !self.pool.options.infinite) {
			const options = &self.pool.options;
			const nodes = self.nodes;
			const timer = &self.pool.timer;

			const exceed_time = options.stop != null
			  and nodes % 2048 == 0
			  and timer.read() / std.time.ns_per_ms >= options.stop.?;
			const exceed_nodes = options.nodes != null and nodes >= options.nodes.?;

			if (exceed_time or exceed_nodes) {
				self.pool.stop();
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

		const tt = self.pool.tt;
		const ttf = tt.fetch(key);
		const tte = ttf[0].*;
		const tth = ttf[1]
		  and tte.key == @as(@TypeOf(tte.key), @truncate(key))
		  and tte.flag != .none
		  and (tte.move.isZero() or pos.isMovePseudoLegal(tte.move));
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

		// null move pruning
		if (!is_pv
		  and !is_checked
		  and d >= 3
		  and b > evaluation.score.tblose
		  and corr_eval >= b
		  and !self.nmp_verif) nmp: {
			const occ = pos.bothOcc();
			const kings = pos.ptypeOcc(.king);
			const pawns = pos.ptypeOcc(.pawn);
			if (occ.bwx(kings).bwx(pawns) == .none) {
				break :nmp;
			}

			const r = @divTrunc(d, 4) + 3;
			var s = null_search: {
				pos.doNull() catch std.debug.panic("invalid null move", .{});
				defer pos.undoNull();

				const child: Node = switch (node) {
					.upperbound => .lowerbound,
					.lowerbound => .upperbound,
					else => std.debug.panic("invalid node", .{}),
				};
				break :null_search -self.ab(child, ply + 1, -b, 1 - b, d - r);
			};

			if (s >= b) {
				if (s >= evaluation.score.tbwin) {
					s = b;
				}

				const verified = d <= 14 or verif_search: {
					self.nmp_verif = true;
					defer self.nmp_verif = false;

					const vs = self.ab(.upperbound, ply + 1, b - 1, b, d - r);
					break :verif_search vs >= b;
				};
				if (verified) {
					return s;
				}
			}
		}

		var best: movegen.Move.Scored = .{
			.move = .{},
			.score = evaluation.score.none,
		};
		var flag = transposition.Entry.Flag.upperbound;

		var searched: usize = 0;
		var mp = movegen.Picker.init(self, ttm);

		move_loop: while (mp.next()) |sm| {
			const m = sm.move;
			const s = recur: {
				pos.doMove(m) catch continue :move_loop;
				tt.prefetch(pos.ss.top().key);

				defer pos.undoMove();
				defer searched += 1;

				const child: Node = switch (node) {
					.upperbound => .lowerbound,
					.lowerbound => if (searched == 0) .upperbound else .lowerbound,
					.exact => if (searched == 0) .exact else .lowerbound,
					else => std.debug.panic("invalid node", .{}),
				};

				var score = -self.ab(child, ply + 1,
				  if (child == .exact) -b else -a - 1, -a, d - 1);
				if (child != .exact and score > a and score < b) {
					score = -self.ab(.exact, ply + 1, -b, -a, d - 1);
				}
				break :recur score;
			};

			if (!self.pool.is_searching) {
				return draw;
			}

			std.debug.assert(best.score <= a);
			std.debug.assert(a < b);

			const first_rm = is_root and searched == 1;
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

		if (searched == 0) {
			return if (is_checked) lose else draw;
		}

		ttf[0].* = .{
			.was_pv = was_pv or flag == .exact,
			.flag = flag,
			.age = @truncate(tt.age),
			.depth = @intCast(depth),
			.key = @truncate(key),
			.eval = @intCast(stat_eval),
			.score = best.score,
			.move = if (!best.move.isZero()) best.move else mp.ttm,
		};

		return best.score;
	}

	fn qs(self: *Thread,
	  ply: usize,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int) evaluation.score.Int {
		self.nodes += 1;
		self.pos.ss.top().pv.line.resize(0) catch unreachable;

		const draw = evaluation.score.draw;
		const lose = evaluation.score.lose + 1;

		if (!self.pool.is_searching) {
			return draw;
		}

		if (self.idx() == 0 and !self.pool.options.infinite) {
			const options = &self.pool.options;
			const nodes = self.nodes;
			const timer = &self.pool.timer;

			const exceed_nodes = if (options.nodes) |lim| nodes >= lim else false;
			const exceed_time = options.stop != null
			  and nodes % 2048 == 0
			  and timer.read() / std.time.ns_per_ms >= options.stop.?;

			if (exceed_time or exceed_nodes) {
				self.pool.stop();
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

		const tt = self.pool.tt;
		const ttf = tt.fetch(key);
		const tte = ttf[0].*;
		const tth = ttf[1]
		  and tte.key == @as(@TypeOf(tte.key), @truncate(key))
		  and tte.flag != .none
		  and (tte.move.isZero() or pos.isMovePseudoLegal(tte.move));
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

		var searched: usize = 0;
		var mp = movegen.Picker.init(self, ttm);
		if (!is_checked) {
			mp.skipQuiets();
		}

		move_loop: while (mp.next()) |sm| {
			const is_mated = best.score <= evaluation.score.tblose;
			if (!is_mated and mp.stage.isBad()) {
				break;
			}

			const m = sm.move;
			// if (!is_mated and !pos.see(m, evaluation.score.draw)) {
				// continue;
			// }

			const s = recur: {
				pos.doMove(m) catch continue :move_loop;
				tt.prefetch(pos.ss.top().key);

				defer pos.undoMove();
				defer mp.skipQuiets();
				defer searched += 1;

				break :recur -self.qs(ply + 1, -b, -a);
			};

			if (!self.pool.is_searching) {
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

		if (searched == 0 and is_checked) {
			return lose;
		}

		ttf[0].* = .{
			.was_pv = false,
			.flag = flag,
			.age = @truncate(tt.age),
			.depth = 0,
			.key = @truncate(key),
			.eval = @intCast(stat_eval),
			.score = best.score,
			.move = if (!best.move.isZero()) best.move else mp.ttm,
		};

		return best.score;
	}
};

pub const Pool = struct {
	allocator:	std.mem.Allocator,
	threads:	[]Thread,
	options:	Options,

	timer:	std.time.Timer,
	is_searching:	bool,

	quiet:	bool,
	io:	*types.Io,
	tt:	*transposition.Table,

	fn nodes(self: *const Pool) usize {
		var n: usize = 0;
		for (self.threads) |*thread| {
			n += thread.nodes;
		}
		return n;
	}

	fn prep(self: *Pool) void {
		const pos = &self.threads[0].pos;
		const root_moves = &self.threads[0].root_moves;

		root_moves.* = movegen.Move.Root.List.init(pos);
		for (self.threads) |*thread| {
			thread.pos = pos.*;
			thread.root_moves = root_moves.*;

			thread.nodes = 0;
			thread.tbhits = 0;
			thread.tthits = 0;
		}
	}

	pub fn deinit(self: *Pool) void {
		self.allocator.free(self.threads);
		self.threads = undefined;
	}

	pub fn init(allocator: std.mem.Allocator,
	  threads: ?usize,
	  quiet: bool,
	  io: *types.Io,
	  tt: *transposition.Table) !Pool {
		return .{
			.allocator = allocator,
			.threads = try allocator.alloc(Thread, threads orelse 1),
			.options = Options.zero,

			.timer = try std.time.Timer.start(),
			.is_searching = false,

			.quiet = quiet,
			.io = io,
			.tt = tt,
		};
	}

	pub fn realloc(self: *Pool, num: usize) !void {
		if (num == 0) {
			return;
		}

		const copy = self.threads[0];
		self.threads = try self.allocator.realloc(self.threads, num);
		for (self.threads) |*thread| {
			thread.* = copy;
		}
	}

	pub fn reset(self: *Pool) !void {
		const frc = self.options.frc;
		var pos = Position.zero;

		for (self.threads) |*thread| {
			thread.reset(self);
		}

		try pos.parseFen(Position.startpos);
		pos.frc = frc;
		self.setPosition(&pos);
	}

	pub fn setFRC(self: *Pool, frc: bool) void {
		self.options.frc = frc;
		for (self.threads) |*thread| {
			thread.pos.frc = frc;
		}
	}

	pub fn setPosition(self: *Pool, src: *const Position) void {
		for (self.threads) |*thread| {
			const dst = &thread.pos;
			@memcpy(dst[0 .. 1], src[0 .. 1]);
		}
	}

	pub fn waitStart(self: *const Pool) void {
		while (!self.is_searching) {
		}
	}

	pub fn waitStop(self: *const Pool) void {
		while (self.is_searching) {
		}
	}

	pub fn start(self: *Pool) !void {
		const config: std.Thread.SpawnConfig = .{
			.stack_size = 16 * 1024 * 1024,
			.allocator = self.allocator,
		};
		for (self.threads) |*thread| {
			const handle = try std.Thread.spawn(config, Thread.iid, .{thread});
			std.Thread.detach(handle);
		}
	}

	pub fn stop(self: *Pool) void {
		self.is_searching = false;
	}
};

pub const Options = struct {
	frc:	bool,
	hash:	usize,
	threads:	usize,
	overhead:	u64,

	infinite:		bool,
	depth:	?Depth,
	nodes:	?u64,

	incr: std.EnumMap(types.Color, u64),
	time: std.EnumMap(types.Color, u64),

	movetime:	?u64,
	stop:	?u64,

	pub const zero: Options = .{
		.frc = false,
		.hash = 64,
		.threads = 1,
		.overhead = 10,

		.infinite = true,
		.depth = null,
		.nodes = null,
		.incr = std.EnumMap(types.Color, u64).init(.{}),
		.time = std.EnumMap(types.Color, u64).init(.{}),
		.movetime = null,
		.stop = null,
	};

	pub fn reset(self: *Options) void {
		self.* = zero;
	}

	pub fn calcStop(self: *Options, stm: types.Color) void {
		const has_clock = self.incr.get(stm) != null and self.time.get(stm) != null;
		const inf = self.infinite;
		const overhead = self.overhead;

		const incr = self.incr.get(stm) orelse undefined;
		const time = self.time.get(stm) orelse undefined;

		self.stop = if (inf) null
		  else if (self.movetime) |mt| mt -| overhead
		  else if (has_clock) time / 20 + incr / 2 -| overhead
		  else null;
	}
};

pub const hist = struct {
	pub const Int = i16;

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

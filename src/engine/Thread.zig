const bounded_array = @import("bounded_array");
const params = @import("params");
const selfplay = @import("selfplay");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const transposition = @import("transposition.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

const Thread = @This();

const Node = transposition.Entry.Flag;

const Request = union(Tag) {
	bench:		void,
	clear_hash:	void,
	datagen:	selfplay.Request,
	quit:	void,
	search:	void,
	sleep:	void,

	const Tag = enum {
		bench,
		clear_hash,
		datagen,
		quit,
		search,
		sleep,
	};
};

pub const Depth = evaluation.score.Int;

pub const Pool = struct {
	allocator:	std.mem.Allocator,
	threads:	std.ArrayList(Thread),

	searching:	bool,
	sleeping:	bool,
	stop:	bool align(64),

	cond:	std.Thread.Condition,
	mtx:	std.Thread.Mutex,

	options:	Options,
	timer:	std.time.Timer,

	io:	types.IO,
	tt:	transposition.Table,

	fn spawn(self: *Pool) !void {
		const config: std.Thread.SpawnConfig = .{.allocator = self.allocator};
		for (self.threads.items) |*thread| {
			thread.handle = try std.Thread.spawn(config, Thread.loop, .{thread});
		}
	}

	fn waitHelpers(self: *Pool) void {
		if (self.threads.items.len > 1) {
			for (self.threads.items[1 ..]) |*thread| {
				thread.waitSleep();
			}
		}
	}

	fn waitMain(self: *Pool) void {
		self.threads.items[0].waitSleep();
	}

	fn wakeHelpers(self: *Pool, rq: Request) void {
		if (self.threads.items.len > 1) {
			for (self.threads.items[1 ..]) |*thread| {
				thread.wake(rq);
			}
		}
	}

	fn wakeMain(self: *Pool, rq: Request) void {
		self.threads.items[0].wake(rq);
	}

	pub fn destroy(self: *Pool) void {
		self.join();
		self.threads.deinit(self.allocator);

		self.io.deinit(self.allocator);
		self.tt.deinit(self.allocator);

		self.allocator.destroy(self);
	}

	pub fn create(allocator: std.mem.Allocator, opt_threads: ?usize,
	  io: types.IO, tt: transposition.Table) !*Pool {
		const options: Options = .{};
		const threads = opt_threads orelse options.threads;

		const pool = try allocator.create(Pool);
		pool.* = .{
			.allocator = allocator,
			.threads = try .initCapacity(allocator, threads),

			.cond = .{},
			.mtx = .{},

			.options = options,
			.timer = try std.time.Timer.start(),

			.searching = false,
			.sleeping = false,
			.stop = true,

			.io = io,
			.tt = tt,
		};

		_ = try pool.threads.addManyAsSliceBounded(threads);
		try pool.reset();
		try pool.spawn();
		pool.clearHash();

		return pool;
	}

	pub fn join(self: *Pool) void {
		self.stopSearch();
		for (self.threads.items) |*thread| {
			thread.wake(.quit);
			thread.handle.join();
		}
	}

	pub fn realloc(self: *Pool, num: usize) !void {
		const board = self.threads.items[0].board;
		const prev_len = self.threads.items.len;
		if (prev_len == num) {
			return;
		}

		self.stopSearch();
		self.join();

		if (prev_len < num) {
			const add_n = num - prev_len;
			_ = try self.threads.addManyAsSlice(self.allocator, add_n);
		} else {
			self.threads.items.len -= prev_len - num;
		}

		for (self.threads.items, 0 ..) |*thread, i| {
			thread.* = .{
				.board = board,
				.pool = self,
				.idx = i,
				.cnt = num,
			};
		}
		try self.spawn();
	}

	pub fn reset(self: *Pool) !void {
		self.stopSearch();
		self.sleeping = false;

		self.options.reset();
		self.timer.reset();

		for (self.threads.items, 0 ..) |*thread, i| {
			thread.* = .{
				.pool = self,
				.idx = i,
				.cnt = self.threads.items.len,
			};
		}

		var board: Board = .{};
		try board.parseFen(Board.Position.startpos);
		self.setBoard(&board, false);
	}

	pub fn nodes(self: *const Pool) u64 {
		var n: u64 = 0;
		for (self.threads.items) |*thread| {
			n += thread.nodes;
		}
		return n;
	}

	pub fn setFRC(self: *Pool, frc: bool) void {
		self.options.frc = frc;
		for (self.threads.items) |*thread| {
			thread.board.frc = frc;
		}
	}

	pub fn setBoard(self: *Pool, board: *const Board, frc: bool) void {
		self.options.frc = frc;
		for (self.threads.items) |*thread| {
			thread.board = board.*;
			thread.board.frc = frc;
		}
	}

	pub fn bench(self: *Pool) void {
		self.stopSearch();
		self.tt.doAge();

		self.stop = false;
		self.searching = true;
		self.wakeMain(.bench);
		self.waitMain();
	}

	pub fn clearHash(self: *Pool) void {
		self.stopSearch();
		self.wakeMain(.clear_hash);
		self.wakeHelpers(.clear_hash);
		self.waitSleep();
	}

	pub fn datagen(self: *Pool, rq: selfplay.Request) void {
		self.stopSearch();
		self.tt.doAge();

		self.stop = false;
		self.searching = true;

		self.wakeMain(.{.datagen = rq});
		self.wakeHelpers(.{.datagen = rq});
	}

	pub fn search(self: *Pool) void {
		self.stopSearch();
		self.tt.doAge();

		self.stop = false;
		self.searching = true;
		self.wakeMain(.search);
	}

	pub fn stopSearch(self: *Pool) void {
		if (self.searching) {
			self.stop = true;
			self.waitMain();
		}
	}

	pub fn waitSleep(self: *Pool) void {
		self.waitMain();
		self.waitHelpers();
	}
};

pub const Options = struct {
	frc:	bool = false,
	hash:	usize = 64,
	threads:	usize = 1,
	overhead:	u64 = 10,

	infinite:	bool = true,
	depth:		?Depth = null,
	movetime:	?u64 = null,

	hard_nodes:	?u64 = null,
	soft_nodes:	?u64 = null,

	incr: std.EnumMap(types.Color, u64) = std.EnumMap(types.Color, u64).init(.{}),
	time: std.EnumMap(types.Color, u64) = std.EnumMap(types.Color, u64).init(.{}),

	hard_stop:	?u64 = null,
	soft_stop:	?u64 = null,

	pub fn reset(self: *Options) void {
		self.* = .{
			.frc = self.frc,
			.hash = self.hash,
			.threads = self.threads,
			.overhead = self.overhead,
		};
	}

	pub fn setLimits(self: *Options, stm: types.Color) void {
		const has_clock = self.incr.get(stm) != null and self.time.get(stm) != null;
		const overhead = self.overhead;

		const from_movetime = if (self.movetime) |mt| mt -| overhead else std.math.maxInt(u64);
		const from_clock = if (!has_clock) std.math.maxInt(u64) else blk: {
			const incr: f32 = @floatFromInt(self.incr.get(stm).?);
			const time: f32 = @floatFromInt(self.time.get(stm).?);

			const im: f32 = @floatFromInt(params.values.base_incr_mul);
			const tm: f32 = @floatFromInt(params.values.base_time_mul);

			const mt: u64 = @intFromFloat(time * tm * 0.01 + incr * im * 0.01);
			break :blk mt -| overhead;
		};
		const min_time = @min(from_movetime, from_clock);

		self.hard_stop = if (min_time < std.math.maxInt(u64)) min_time else null;
		self.infinite = self.depth == null
		  and self.soft_nodes == null and self.soft_stop == null
		  and self.hard_nodes == null and self.hard_stop == null;
	}
};

pub const hist = struct {
	pub const Int = i16;

	pub const min = std.math.minInt(Int) / 2;
	pub const max = -min;

	fn bonus(d: Depth) evaluation.score.Int {
		const x: evaluation.score.Int
		  = params.values.hist_bonus2 * d * d
		  + params.values.hist_bonus1 * d
		  + params.values.hist_bonus0;
		return @min(x, params.values.max_hist_bonus);
	}

	fn malus(d: Depth) evaluation.score.Int {
		const x: evaluation.score.Int
		  = params.values.hist_malus2 * d * d
		  + params.values.hist_malus1 * d
		  + params.values.hist_malus0;
		return -@min(x, params.values.max_hist_malus);
	}

	fn gravity(p: *Int, dx: evaluation.score.Int) void {
		const clamped = std.math.clamp(dx, min, max);
		const abs = if (clamped < 0) -clamped else clamped;

		const curr: evaluation.score.Int = p.*;
		const next = curr + clamped - @divTrunc(curr * abs, max);
		p.* = @intCast(next);
	}
};

board:	 Board = .{},

pool:	*Pool = undefined,
idx:	 usize = 0,
cnt:	 usize = 0,

handle:	std.Thread = undefined,
request:	Request align(64) = .sleep,

nodes:	u64 = 0,
tbhits:	u64 = 0,
tthits:	u64 = 0,

depth:		Depth = 0,
seldepth:	Depth = 0,
root_moves:	movegen.Move.Root.List = .{},

nmp_verif:	bool = false,
quiethist:	[types.Color.cnt][types.Ptype.cnt][types.Square.cnt]hist.Int
  = @splat(@splat(@splat(0))),
noisyhist:	[types.Color.cnt][types.Ptype.cnt][types.Square.cnt]
  [1 << types.Ptype.tag_info.bits]hist.Int
  = @splat(@splat(@splat(@splat(0)))),
conthist:	[types.Color.cnt][4]
  [1 << types.Ptype.tag_info.bits][types.Square.cnt]
  [1 << types.Ptype.tag_info.bits][types.Square.cnt]hist.Int
  = @splat(@splat(@splat(@splat(@splat(@splat(0)))))),

fn quietHistPtr(self: anytype,
  move: movegen.Move) types.SameMutPtr(@TypeOf(self), Thread, hist.Int) {
	const sp = self.board.top().getSquare(move.src);
	return &self.quiethist[sp.color().tag()][sp.ptype().tag()][move.dst.tag()];
}

fn noisyHistPtr(self: anytype,
  move: movegen.Move) types.SameMutPtr(@TypeOf(self), Thread, hist.Int) {
	const sp = self.board.top().getSquare(move.src);
	const dp = self.board.top().getSquare(move.dst);

	return &self.noisyhist
	  [sp.color().tag()]
	  [sp.ptype().tag()]
	  [move.dst.tag()]
	  [dp.ptype().tag()];
}

fn contHistPtr(self: anytype, move: movegen.Move,
  ply: usize) types.SameMutPtr(@TypeOf(self), Thread, hist.Int) {
	const last_spt = self.board.top().down(ply).src_piece.ptype();
	const last_dst = self.board.top().down(ply).move.dst;

	const this_spt = self.board.top().getSquare(move.src).ptype();
	const this_dst = move.dst;

	return &self.conthist
	  [self.board.top().stm.tag()][ply / 2]
	  [last_spt.tag()][last_dst.tag()]
	  [this_spt.tag()][this_dst.tag()];
}

fn updateHist(self: *Thread, depth: Depth, move: movegen.Move,
  bad_noisy_moves: []const movegen.Move,
  bad_quiet_moves: []const movegen.Move) void {
	const bonus = hist.bonus(depth);
	const malus = hist.malus(depth);

	const pos = self.board.top();
	const is_quiet = pos.isMoveQuiet(move);
	if (is_quiet) {
		hist.gravity(self.quietHistPtr(move), bonus);
		for (bad_quiet_moves) |qm| {
			hist.gravity(self.quietHistPtr(qm), malus);
		}

		const cont_plies = [_]usize {1, 2, 4, 6};
		for (cont_plies) |ply| {
			hist.gravity(self.contHistPtr(move, ply), bonus);
			for (bad_quiet_moves) |qm| {
				hist.gravity(self.contHistPtr(qm, ply), malus);
			}
		}
	} else {
		hist.gravity(self.noisyHistPtr(move), bonus);
	}

	for (bad_noisy_moves) |nm| {
		hist.gravity(self.noisyHistPtr(nm), malus);
	}
}

fn printInfo(self: *const Thread,
  pv: *const movegen.Move.Root,
  depth: Depth, seldepth: Depth) !void {
	const io = &self.pool.io;
	const tt = &self.pool.tt;

	self.pool.mtx.lock();
	defer self.pool.mtx.unlock();

	const writer = io.writer();
	const timer = &self.pool.timer;

	const nodes = self.pool.nodes();
	const ntime = timer.read();
	const mtime = ntime / std.time.ns_per_ms;

	try writer.print("info", .{});
	try writer.print(" depth {d}", .{depth});
	try writer.print(" seldepth {d}", .{seldepth});

	try writer.print(" hashfull {d}", .{tt.hashfull()});
	try writer.print(" nodes {d}", .{nodes});
	try writer.print(" time {d}", .{mtime});
	try writer.print(" nps {d}", .{nodes * std.time.ns_per_s / ntime});

	const pvs: evaluation.score.Int = @intCast(pv.score);
	try writer.print(" score", .{});
	if (evaluation.score.isMated(pvs)) {
		const ply = pvs - evaluation.score.mated;
		const moves = @divTrunc(ply + 1, 2);
		try writer.print(" mate {d} wdl 0 0 1000", .{-moves});
	} else if (evaluation.score.isMate(pvs)) {
		const ply = evaluation.score.mate - pvs;
		const moves = @divTrunc(ply + 1, 2);
		try writer.print(" mate {d} wdl 1000 0 0", .{moves});
	} else {
		const material = self.board.top().material();
		try writer.print(" cp {d}", .{evaluation.score.normalize(pvs, material)});
		try writer.print(" wdl {d} {d} {d}", evaluation.score.wdl(pvs, material));
	}

	try writer.print(" pv", .{});
	for (pv.constSlice()) |m| {
		const s = m.toString(&self.board);
		const l = m.toStringLen();
		try writer.print(" {s}", .{s[0 .. l]});
	}

	try writer.print("\n", .{});
	try writer.flush();
}

fn printBest(self: *const Thread, pv: *const movegen.Move.Root) !void {
	self.pool.mtx.lock();
	defer self.pool.mtx.unlock();

	if (pv.constSlice().len == 0) {
		try self.pool.io.writer().print("bestmove 0000\n", .{});
		try self.pool.io.writer().flush();
		return;
	}

	const m = pv.constSlice()[0];
	const s = m.toString(&self.board);
	const l = m.toStringLen();
	try self.pool.io.writer().print("bestmove {s}\n", .{s[0 .. l]});
	try self.pool.io.writer().flush();
}

fn datagenStop(self: *Thread, comptime which: enum {hard, soft}) bool {
	const options = &self.pool.options;
	const nodes_lim = if (which == .hard) options.hard_nodes else options.soft_nodes;
	return if (nodes_lim) |lim| self.nodes >= lim else false;
}

fn searchStop(self: *Thread, comptime which: enum {hard, soft}) bool {
	const options = &self.pool.options;
	if (options.infinite) {
		return false;
	}

	const nodes = self.nodes;
	const nodes_lim = if (which == .hard) options.hard_nodes else options.soft_nodes;
	if (nodes_lim != null and nodes >= nodes_lim.?) {
		return true;
	}

	const timer = &self.pool.timer;
	const time_lim = if (which == .hard) options.hard_stop else options.soft_stop;
	return nodes % 2048 == 0
	  and time_lim != null
	  and time_lim.? * std.time.ns_per_ms <= timer.read();
}

fn asp(self: *Thread) void {
	const pv = &self.root_moves.constSlice()[0];
	const pvs: evaluation.score.Int = @intCast(pv.score);

	var s: @TypeOf(pvs) = evaluation.score.none;
	var w: @TypeOf(pvs) = params.values.asp_window;

	const d = self.depth;
	var a: @TypeOf(pvs) = evaluation.score.mated;
	var b: @TypeOf(pvs) = evaluation.score.mate;
	if (d >= params.values.asp_min_depth) {
		a = std.math.clamp(pvs - w, evaluation.score.mated, evaluation.score.mate);
		b = std.math.clamp(pvs + w, evaluation.score.mated, evaluation.score.mate);
	}

	while (true) : ({
		w = w + @divTrunc(w * params.values.asp_window_mul, 256);
		w = std.math.clamp(w, evaluation.score.mated, evaluation.score.mate);
	}) {
		s = self.ab(.exact, 0, a, b, d);

		const datagen_stop = self.request == .datagen and self.datagenStop(.hard);
		if (datagen_stop or self.pool.stop) {
			break;
		}

		if (s <= a) {
			b = @divTrunc(a + b, 2);
			a = std.math.clamp(a - w, evaluation.score.mated, evaluation.score.mate);
		} else if (s >= b) {
			a = @divTrunc(a + b, 2);
			b = std.math.clamp(b + w, evaluation.score.mated, evaluation.score.mate);
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
	self.board.top().pv.line.resize(0) catch unreachable;

	if (self.pool.stop) {
		return alpha;
	}

	const is_datagen = self.request == .datagen;
	if (is_datagen and self.datagenStop(.hard)) {
		return alpha;
	}

	const is_main = self.idx == 0;
	if (!is_datagen and is_main and self.searchStop(.hard)) {
		self.pool.stop = true;
		return alpha;
	}

	var a = alpha;
	var b = beta;
	var d = depth;

	const mate = evaluation.score.mateIn(ply);
	const mated = evaluation.score.matedIn(ply);

	const draw = mated + mate;
	const lose = mated;

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
		const len: Depth = @intCast(ply + 1);
		self.seldepth = @max(self.seldepth, len);
	}

	const board = &self.board;
	const is_drawn = self.board.isDrawn();
	const is_terminal = self.board.isTerminal();
	if (is_drawn or is_terminal) {
		@branchHint(.unlikely);
		return if (is_drawn) draw else board.evaluate();
	}

	const pos = board.top();
	const key = pos.key;
	const is_checked = pos.isChecked();

	var tte: transposition.Entry = .{};
	const tt = self.pool.tt;
	const tth = tt.read(key, &tte);

	const was_pv = tth and tte.was_pv;
	const ttscore = evaluation.score.fromTT(tte.score, ply);

	if (!is_pv and tth and tte.shouldTrust(a, b, d)) {
		return ttscore;
	}

	const has_tteval = tth
	  and tte.eval > evaluation.score.lose
	  and tte.eval < evaluation.score.win;
	const stat_eval = if (is_checked) evaluation.score.none
	  else if (has_tteval) tte.eval
	  else board.evaluate();

	const use_ttscore = tth
	  and ttscore > evaluation.score.lose
	  and ttscore < evaluation.score.win
	  and !(tte.flag == .upperbound and ttscore >  stat_eval)
	  and !(tte.flag == .lowerbound and ttscore <= stat_eval);
	// TODO: correct eval in case tt score is unusable
	const corr_eval = if (use_ttscore) ttscore
	  else if (is_checked) evaluation.score.none
	  else stat_eval;

	pos.stat_eval = stat_eval;
	pos.corr_eval = corr_eval;

	// improving heuristic(s)
	// 10.0+0.1: 21.29 +- 9.45
	const improving = !is_checked and blk: {
		const fu2ev = pos.down(2).corr_eval;
		if (fu2ev != evaluation.score.none) {
			break :blk fu2ev < corr_eval;
		}

		const fu4ev = pos.down(4).corr_eval;
		if (fu4ev != evaluation.score.none) {
			break :blk fu4ev < corr_eval;
		}

		break :blk true;
	};
	const ntm_worsening = !is_checked and !is_root
	  and pos.down(1).corr_eval != evaluation.score.none
	  and pos.down(1).corr_eval > 1 - corr_eval;

	// internal iterative reduction (iir)
	// 10.0+0.1: 84.25 +- 20.51
	const has_ttm = tth and pos.isMovePseudoLegal(tte.move);
	if (node.hasLower() and depth >= params.values.iir_min_depth and !has_ttm) {
		d -= 1;
	}

	// reverse futility pruning (rfp)
	var rfp_margin = d;
	rfp_margin *= params.values.rfp_depth_mul;
	rfp_margin -= params.values.rfp_ntm_worsening
	  * @as(@TypeOf(b), @intFromBool(ntm_worsening));
	rfp_margin = @max(rfp_margin, 20);
	if (!is_pv
	  and !is_checked
	  and d <= params.values.rfp_max_depth
	  and corr_eval >= b + rfp_margin) {
		return corr_eval;
	}

	// null move pruning
	if (!is_pv
	  and !is_checked
	  and d >= params.values.nmp_min_depth
	  and b > evaluation.score.lose
	  and corr_eval >= b + params.values.nmp_eval_margin
	  and !self.nmp_verif) nmp: {
		const occ = pos.bothOcc();
		const kings = pos.ptypeOcc(.king);
		const pawns = pos.ptypeOcc(.pawn);
		if (occ.bwx(kings).bwx(pawns) == .none) {
			break :nmp;
		}

		const base_r = params.values.nmp_base_reduction;
		const depth_r = params.values.nmp_depth_mul * d;

		const eval_diff = corr_eval - b;
		const diff_scaled = @divTrunc(eval_diff, params.values.nmp_eval_diff_divisor);

		const r: @TypeOf(d)
		  = @divTrunc(base_r + depth_r, 256)
		  + @min(diff_scaled, params.values.nmp_max_eval_reduction)
		  + @intFromBool(improving);

		var s = null_search: {
			board.doNull();
			defer board.undoNull();

			break :null_search -self.ab(node.flip(), ply + 1, -b, 1 - b, d - r);
		};

		if (s >= b) {
			if (evaluation.score.isMate(s)) {
				s = b;
			}

			const verified = d < 15 or verif_search: {
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

	// razoring
	if (!is_pv and !is_checked
	  and d <= params.values.razoring_max_depth
	  and corr_eval + params.values.razoring_depth_mul * d <= a) {
		const rs = self.qs(ply + 1, a, b);
		if (rs <= a) {
			return rs;
		}
	}

	var best: movegen.Move.Scored = .{
		.move = .{},
		.score = evaluation.score.none,
	};
	var flag = transposition.Entry.Flag.upperbound;

	var searched: usize = 0;
	var bad_noisy_moves: movegen.Move.List = .{};
	var bad_quiet_moves: movegen.Move.List = .{};
	var mp = movegen.Picker.init(self, tte.move);

	const is_ttm_noisy = !mp.ttm.isNone() and pos.isMoveNoisy(mp.ttm);
	const is_ttm_quiet = !mp.ttm.isNone() and !is_ttm_noisy;

	move_loop: while (mp.next()) |sm| {
		const m = sm.move;
		if (!pos.isMoveLegal(m)) {
			continue :move_loop;
		}

		const is_ttm = m == mp.ttm;
		const is_noisy = (is_ttm and is_ttm_noisy) or mp.stage.isNoisy();
		const is_quiet = (is_ttm and is_ttm_quiet) or mp.stage.isQuiet();

		const base_lmr = @as(@TypeOf(d), params.lmr.get(d, searched, is_quiet)) * 1024;

		if (!is_root and best.score > evaluation.score.lose) {
			// futility pruning
			// 10.0+0.1: 34.28 +- 12.73
			const lmr_d = @max(d - @divTrunc(base_lmr, 1024), 0);
			const fp_margin
			  = params.values.fp_margin0
			  + params.values.fp_margin1 * lmr_d
			  + @divTrunc(sm.score, params.values.fp_hist_divisor);
			if (lmr_d <= params.values.fp_max_depth
			  and is_quiet
			  and !is_checked
			  and a < evaluation.score.win
			  and stat_eval + fp_margin <= a) {
				continue :move_loop;
			}

			// late move pruning (lmp)
			// 10.0+0.1: 21.30 +- 9.80
			var very_late: usize = @intCast(d * d);
			very_late += 4;
			very_late /= if (improving) 1 else 2;
			if (searched > very_late) {
				break :move_loop;
			}
		}

		var recur_d = d - 1;
		var r: Depth = 0;

		const s = recur: {
			board.doMove(m);
			tt.prefetch(board.top().key);

			defer board.undoMove();
			defer searched += 1;

			var score: @TypeOf(a, b) = evaluation.score.none;
			if (is_pv and searched == 0) {
				score = -self.ab(.exact, ply + 1, -b, -a, recur_d);
				break :recur score;
			}

			const is_late = searched > 1 and searched
			  > @as(usize, @intFromBool(is_pv))
			  + @as(usize, @intFromBool(is_root))
			  + @as(usize, @intFromBool(is_noisy))
			  + @as(usize, @intFromBool(mp.ttm.isNone()));

			score = if (d >= params.values.lmr_min_depth and is_late) reduced: {
				// late move reduction (lmr)
				// 10.0+0.1: 48.29 +- 15.89
				r += base_lmr;

				r += @as(@TypeOf(d), @intFromBool(!improving))
				  * params.values.lmr_non_improving;
				r += @as(@TypeOf(d), @intFromBool(node == .lowerbound))
				  * params.values.lmr_cutnode;
				r += @as(@TypeOf(d), @intFromBool(is_ttm_noisy))
				  * params.values.lmr_noisy_ttm;

				r -= @as(@TypeOf(d), @intFromBool(board.top().isChecked()))
				  * params.values.lmr_gave_check;
				r -= @as(@TypeOf(d), @intFromBool(is_checked))
				  * params.values.lmr_is_checked;
				r -= @as(@TypeOf(d), @intFromBool(is_pv))
				  * params.values.lmr_is_pv;

				r -= @as(@TypeOf(d), @intFromBool(was_pv))
				  * params.values.lmr_was_pv;
				r -= @as(@TypeOf(d), @intFromBool(was_pv and ttscore > a))
				  * params.values.lmr_was_pv_non_fail_low;

				r = @divTrunc(r, 1024);
				const rd = std.math.clamp(recur_d - r, 1, recur_d);
				var rs = -self.ab(.lowerbound, ply + 1, -a - 1, -a, rd);

				if (rs > a and rd < recur_d) {
					const deeper = rs
					  > best.score
					  + params.values.deeper_margin0
					  + @divTrunc(params.values.deeper_margin1 * recur_d, 256);
					const shallower = rs < best.score + params.values.shallower_margin;

					recur_d += @intFromBool(deeper);
					recur_d -= @intFromBool(shallower);

					rs = -self.ab(node.flip(), ply + 1, -a - 1, -a, recur_d);
				}

				break :reduced rs;
			} else -self.ab(node.flip(), ply + 1, -a - 1, -a, recur_d);

			score = if (is_pv and score > a) -self.ab(.exact, ply + 1, -b, -a, recur_d)
			  else score;

			break :recur score;
		};

		const datagen_stop = is_datagen and self.datagenStop(.hard);
		if (datagen_stop or self.pool.stop) {
			return a;
		}

		std.debug.assert(best.score <= a);
		std.debug.assert(a < b);

		if (is_root) {
			const rms = self.root_moves.slice();
			var rmi: usize = 0;
			while (rms[rmi].line.constSlice()[0] != m) : (rmi += 1) {
			}

			const next_pv = &self.board.top().up(1).pv;
			const rm = &rms[rmi];
			if (searched == 1 or s > a) {
				rm.update(s, m, next_pv.constSlice());
			} else {
				rm.score = evaluation.score.none;
			}
		}

		if (s > best.score) {
			best.score = @intCast(s);

			if (!is_root and is_pv and s > a) {
				const next_pv = &self.board.top().up(1).pv;
				const this_pv = &self.board.top().pv;

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

		if (is_quiet) {
			bad_quiet_moves.push(m);
		} else {
			bad_noisy_moves.push(m);
		}
	}

	if (searched == 0) {
		return if (is_checked) lose else draw;
	}

	if (flag == .lowerbound) {
		self.updateHist(d, best.move,
		  bad_noisy_moves.constSlice(),
		  bad_quiet_moves.constSlice());
	}

	tte = .{
		.was_pv = was_pv or flag == .exact,
		.flag = flag,
		.age = @truncate(tt.age),
		.depth = @intCast(depth),
		.key = @truncate(key),
		.eval = @intCast(stat_eval),
		.score = @intCast(evaluation.score.toTT(best.score, ply)),
		.move = best.move,
	};
	tt.write(key, tte);

	return best.score;
}

fn qs(self: *Thread,
  ply: usize,
  alpha: evaluation.score.Int,
  beta:  evaluation.score.Int) evaluation.score.Int {
	self.nodes += 1;
	self.board.top().pv.line.resize(0) catch unreachable;

	if (self.pool.stop) {
		return alpha;
	}

	const is_datagen = self.request == .datagen;
	if (is_datagen and self.datagenStop(.hard)) {
		return alpha;
	}

	const is_main = self.idx == 0;
	if (!is_datagen and is_main and self.searchStop(.hard)) {
		self.pool.stop = true;
		return alpha;
	}

	const draw = evaluation.score.draw;
	const lose = evaluation.score.lose + 1;

	const b = beta;
	var a = alpha;

	const board = &self.board;
	const is_drawn = self.board.isDrawn();
	const is_terminal = self.board.isTerminal();
	if (is_drawn or is_terminal) {
		@branchHint(.unlikely);
		return if (is_drawn) draw else board.evaluate();
	}

	const pos = board.top();
	const key = pos.key;
	const is_checked = pos.isChecked();

	var tte: transposition.Entry = .{};
	const tt = self.pool.tt;
	const tth = tt.read(key, &tte);
	const ttscore = evaluation.score.fromTT(tte.score, ply);

	if (tth and tte.shouldTrust(a, b, 0)) {
		return ttscore;
	}

	const has_tteval = tth
	  and tte.eval > evaluation.score.lose
	  and tte.eval < evaluation.score.win;
	const stat_eval = if (is_checked) evaluation.score.none
	  else if (has_tteval) tte.eval
	  else board.evaluate();

	const use_ttscore = tth
	  and ttscore > evaluation.score.lose
	  and ttscore < evaluation.score.win
	  and !(tte.flag == .upperbound and ttscore >  stat_eval)
	  and !(tte.flag == .lowerbound and ttscore <= stat_eval);
	// TODO: correct eval in case tt score is unusable
	const corr_eval = if (use_ttscore) ttscore
	  else if (is_checked) evaluation.score.none
	  else stat_eval;

	pos.stat_eval = stat_eval;
	pos.corr_eval = corr_eval;

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
	var mp = movegen.Picker.init(self, tte.move);
	if (!is_checked) {
		mp.skipQuiets();
	}

	move_loop: while (mp.next()) |sm| {
		const m = sm.move;

		if (searched > 0) {
			if (mp.stage.isBad()) {
				break :move_loop;
			}

			// qs see pruning
			// 10.0+0.1: 206.81 +- 35.91
			if (!pos.see(m, draw)) {
				continue :move_loop;
			}
		}

		if (!is_checked) {
			// qs futility pruning
			// 10.0+0.1: 65.37 +- 17.63
			const margin = params.values.qs_fp_margin;
			if (corr_eval + margin <= a and !pos.see(m, draw + 1)) {
				best.score = @intCast(@max(best.score, corr_eval + margin));
				continue :move_loop;
			}
		}

		const s = recur: {
			// TODO: move this to top of the loop
			if (!pos.isMoveLegal(m)) {
				continue :move_loop;
			}
			board.doMove(m);
			tt.prefetch(board.top().key);

			defer board.undoMove();
			defer mp.skipQuiets();
			defer searched += 1;

			break :recur -self.qs(ply + 1, -b, -a);
		};

		const datagen_stop = is_datagen and self.datagenStop(.hard);
		if (datagen_stop or self.pool.stop) {
			return a;
		}

		if (s > best.score) {
			best.score = @intCast(s);

			if (s > a) {
				a = s;
				best.move = m;
			}

			if (s >= b) {
				flag = .lowerbound;
				break :move_loop;
			}
		}
	}

	if (searched == 0 and is_checked) {
		return lose;
	}

	tte = .{
		.was_pv = tte.was_pv,
		.flag = flag,
		.age = @truncate(tt.age),
		.depth = 0,
		.key = @truncate(key),
		.eval = @intCast(stat_eval),
		.score = @intCast(evaluation.score.toTT(best.score, ply)),
		.move = best.move,
	};
	tt.write(key, tte);

	return best.score;
}

fn loop(self: *Thread) !void {
	idle: while (true) {
		self.pool.mtx.lock();
		while (self.request == .sleep) {
			self.pool.cond.signal();
			self.pool.cond.wait(&self.pool.mtx);
		}
		self.pool.mtx.unlock();

		defer self.request = .sleep;
		switch (self.request) {
			.bench, .search => try self.search(),
			.clear_hash => self.clearHash(),
			.datagen => try self.datagen(),
			.quit => break :idle,
			.sleep => continue :idle,
		}
	}
}

fn waitBool(self: *Thread, cond: *bool) void {
	self.pool.mtx.lock();
	defer self.pool.mtx.unlock();

	while (!cond.*) {
		self.pool.cond.wait(&self.pool.mtx);
	}
}

fn waitSleep(self: *Thread) void {
	self.pool.mtx.lock();
	while (self.request != .sleep) {
		self.pool.cond.signal();
		self.pool.cond.wait(&self.pool.mtx);
	}
	self.pool.mtx.unlock();

	if (self.idx == 0) {
		self.pool.searching = false;
	}
}

fn wake(self: *Thread, request: Request) void {
	self.pool.mtx.lock();
	defer self.pool.mtx.unlock();

	self.request = request;
	self.pool.cond.signal();
}

fn clearHash(self: *Thread) void {
	const tt = self.pool.tt.slice;
	if (tt.len == 0) {
		return;
	}

	const i = self.idx;
	const n = self.cnt;
	const d = tt.len / n;
	const m = tt.len % n;
	var p = tt.ptr;

	for (0 .. i) |it| {
		p += if (it < m) d + 1 else d;
	}

	const s = p[0 .. if (i < m) d + 1 else d];
	for (s) |*c| {
		c.* = .{};
	}
}

fn datagen(self: *Thread) !void {
	return selfplay.thread.datagen(self);
}

pub fn search(self: *Thread) !void {
	self.nodes = 0;
	self.tbhits = 0;
	self.tthits = 0;

	const pool = self.pool;
	const rq = self.request;

	const is_main = self.idx == 0;
	const is_threaded = self.cnt > 1;

	const is_bench = rq == .bench;
	const is_datagen = rq == .datagen;
	const is_search = rq == .search;
	const should_report = !is_bench and !is_datagen and is_main;

	if (!is_search or is_main) {
		self.root_moves = movegen.Move.Root.List.init(&self.board);
	}

	if (is_search and is_main and is_threaded) {
		for (pool.threads.items[1 ..]) |*thread| {
			thread.board = self.board;
			thread.root_moves = self.root_moves;
			thread.wake(.search);
		}
	}

	var last_depth: Depth = 0;
	var last_seldepth: Depth = 0;
	var last_pv: movegen.Move.Root = .{};

	const no_moves = self.root_moves.constSlice().len == 0;
	last_pv = if (no_moves) {
		if (!should_report) {
			return;
		}

		try self.printInfo(&last_pv, last_depth, last_seldepth);
		try self.printBest(&last_pv);
		return;
	} else self.root_moves.constSlice()[0];

	const max_depth = pool.options.depth orelse movegen.Move.Root.capacity;
	const min_depth = 1;
	var depth: Depth = min_depth;

	while (depth <= max_depth) : (depth += 1) {
		self.depth = depth;
		self.seldepth = 0;
		self.asp();

		movegen.Move.Root.sortSlice(self.root_moves.slice());
		if (self.pool.stop) {
			break;
		} else if (!should_report) {
			continue;
		}

		last_depth = self.depth;
		last_seldepth = self.seldepth;
		last_pv = self.root_moves.constSlice()[0];
		try self.printInfo(&last_pv, last_depth, last_seldepth);

		if (self.searchStop(.soft)) {
			break;
		}
	}

	if (!should_report) {
		return;
	}

	pool.stop = true;
	if (is_threaded) {
		for (pool.threads.items[1 ..]) |*thread| {
			thread.waitSleep();
		}
	}

	try self.printInfo(&last_pv, last_depth, last_seldepth);
	try self.printBest(&last_pv);
}

pub fn getQuietHist(self: *const Thread, move: movegen.Move) hist.Int {
	return self.quietHistPtr(move).*;
}

pub fn getNoisyHist(self: *const Thread, move: movegen.Move) hist.Int {
	return self.noisyHistPtr(move).*;
}

pub fn getContHist(self: *const Thread, move: movegen.Move, ply: usize) hist.Int {
	return self.contHistPtr(move, ply).*;
}

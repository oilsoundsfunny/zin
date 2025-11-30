const bounded_array = @import("bounded_array");
const params = @import("params");
const std = @import("std");
const types = @import("types");

const Board = @import("Board.zig");
const evaluation = @import("evaluation.zig");
const movegen = @import("movegen.zig");
const transposition = @import("transposition.zig");
const uci = @import("uci.zig");
const zobrist = @import("zobrist.zig");

pub const lmr = struct {
	var table: [32][32][2]u8 = undefined;

	pub fn get(depth: Depth, searched: usize, quiet: bool) u8 {
		const clamped_d: usize = @intCast(std.math.clamp(depth, 0, 31));
		const clamped_i: usize = @min(searched, 31);
		return table[clamped_d][clamped_i][@intFromBool(quiet)];
	}

	pub fn init() !void {
		for (table[0 ..], 0 ..) |*by_depth, depth| {
			for (by_depth[0 ..], 0 ..) |*by_num, num| {
				if (depth == 0 or num == 0) {
					by_num.* = .{0, 0};
					continue;
				}

				const d: f32 = @floatFromInt(depth);
				const n: f32 = @floatFromInt(num);

				// from weiss
				const noisy = 0.20 + @log(d) * @log(n) / 3.35;
				const quiet = 1.35 + @log(d) * @log(n) / 2.75;
				by_num.* = .{@intFromFloat(noisy), @intFromFloat(quiet)};
			}
		}
	}
};

pub const Depth = evaluation.score.Int;
pub const Node = transposition.Entry.Flag;

pub const Thread = struct {
	board:	 Board = .{},
	pool:	*Pool = undefined,
	idx:	 usize = 0,
	cnt:	 usize = 0,

	nodes:	u64 = 0,
	tbhits:	u64 = 0,
	tthits:	u64 = 0,

	depth:		Depth = 0,
	seldepth:	Depth = 0,
	root_moves:	movegen.Move.Root.List = .{},

	nmp_verif:	bool = false,
	quiet_hist:	[types.Square.cnt][types.Square.cnt]hist.Int = @splat(@splat(0)),

	fn reset(self: *Thread, pool: *Pool) void {
		self.* = .{};
		self.pool = pool;
		self.idx = self[0 .. 1].ptr - pool.threads.ptr;
		self.cnt = pool.threads.len;
	}

	fn quietHistPtr(self: anytype, move: movegen.Move) switch (@TypeOf(self)) {
		*Thread => *hist.Int,
		*const Thread => *const hist.Int,
		else => |T| @compileError("unexpected type " ++ @typeName(T)),
	} {
		return &self.quiet_hist[move.src.tag()][move.dst.tag()];
	}

	fn updateHist(self: *Thread, depth: Depth, move: movegen.Move,
	  bad_noisy_moves: []const movegen.Move,
	  bad_quiet_moves: []const movegen.Move) void {
		const clamped = @min(depth, 12);
		const bonus = clamped * 64;
		const malus = bonus;

		const pos = self.board.top();
		const is_quiet = pos.isMoveQuiet(move);
		if (is_quiet) {
			hist.bonus(self.quietHistPtr(move), bonus);
			for (bad_quiet_moves) |qm| {
				hist.malus(self.quietHistPtr(qm), malus);
			}
		} else {
			// TODO: bonus noisy hist
		}

		for (bad_noisy_moves) |_| {
			// TODO: malus noisy hist
		}
	}

	fn printInfo(self: *const Thread) !void {
		if (self.pool.quiet) {
			return;
		}

		const writer = self.pool.io.writer();
		const timer = &self.pool.timer;

		const has_pv = self.root_moves.constSlice().len > 0;
		const pv = if (has_pv) &self.root_moves.constSlice()[0] else return;

		const nodes = self.pool.nodes();
		const ntime = timer.read();
		const mtime = ntime / std.time.ns_per_ms;

		const depth = self.depth;
		const seldepth = self.seldepth;

		self.pool.io.lockWriter();
		defer self.pool.io.unlockWriter();

		try writer.print("info", .{});
		try writer.print(" depth {d}", .{depth});
		try writer.print(" seldepth {d}", .{seldepth});

		try writer.print(" hashfull {d}", .{self.pool.tt.hashfull()});
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
			const pos = self.board.top();
			const mat
			  = pos.ptypeOcc(.pawn).count() * 1
			  + pos.ptypeOcc(.knight).count() * 3
			  + pos.ptypeOcc(.bishop).count() * 3
			  + pos.ptypeOcc(.rook).count() * 5
			  + pos.ptypeOcc(.queen).count() * 9;
			const normalized = evaluation.score.normalize(pvs, mat);
			try writer.print(" cp {d}", .{normalized});
			try writer.print(" wdl {d} {d} {d}", evaluation.score.wdl(pvs, mat));
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

	fn printBest(self: *const Thread) !void {
		if (self.pool.quiet) {
			return;
		}

		self.pool.io.lockWriter();
		defer self.pool.io.unlockWriter();

		const has_pv = self.root_moves.constSlice().len > 0;
		if (!has_pv) {
			try self.pool.io.writer().print("bestmove 0000\n", .{});
			try self.pool.io.writer().flush();
			return;
		}

		const m = self.root_moves.constSlice()[0].constSlice()[0];
		const s = m.toString(&self.board);
		const l = m.toStringLen();
		try self.pool.io.writer().print("bestmove {s}\n", .{s[0 .. l]});
		try self.pool.io.writer().flush();
	}

	fn iid(self: *Thread) !void {
		const is_main = self.idx == 0;
		const is_threaded = self.cnt > 1;

		const max_depth = self.pool.options.depth orelse movegen.Move.Root.capacity;
		const min_depth = 1;
		var depth: Depth = min_depth;

		const no_moves = self.root_moves.constSlice().len == 0;
		while (!no_moves and depth <= max_depth) : (depth += 1) {
			self.depth = depth + @intFromBool(is_threaded
			  and self.idx % 2 == 1
			  and depth > min_depth
			  and depth < max_depth);
			self.seldepth = 0;
			self.asp();

			movegen.Move.Root.sortSlice(self.root_moves.slice());
			if (!self.pool.searching) {
				break;
			}

			if (is_main) {
				self.pool.tt.doAge();
				try self.printInfo();
			}
		}

		if (is_main) {
			self.pool.stop();
			defer self.pool.finish();

			try self.printInfo();
			try self.printBest();
		} else self.pool.waitStop();
	}

	fn hardStop(self: *Thread) bool {
		const pool = self.pool;
		const options = pool.options;

		const nodes = self.nodes;
		if (options.nodes) |lim| {
			if (nodes >= lim) {
				return true;
			}
		}

		return nodes % 2048 == 0
		  and options.stop != null
		  and options.stop.? * std.time.ns_per_ms <= pool.timer.read();
	}

	fn asp(self: *Thread) void {
		const pv = &self.root_moves.constSlice()[0];
		const pvs: evaluation.score.Int = @intCast(pv.score);

		var s: @TypeOf(pvs) = evaluation.score.none;
		var w: @TypeOf(pvs) = 256;

		const d = self.depth;
		var a: @TypeOf(pvs) = evaluation.score.lose;
		var b: @TypeOf(pvs) = evaluation.score.win;
		if (d >= 3) {
			a = std.math.clamp(pvs - w, evaluation.score.lose, evaluation.score.win);
			b = std.math.clamp(pvs + w, evaluation.score.lose, evaluation.score.win);
		}

		while (true) : (w *= 2) {
			s = self.ab(.exact, 0, a, b, d);

			if (!self.pool.searching) {
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
		self.board.top().pv.line.resize(0) catch unreachable;

		const is_main = self.idx == 0;
		if (is_main and self.hardStop()) {
			self.pool.stop();
			return alpha;
		}

		if (!self.pool.searching) {
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
		const pos = board.top();
		const key = pos.key;
		const is_checked = pos.isChecked();
		if (self.board.isDrawn()) {
			return draw;
		} else if (self.board.isTerminal()) {
			return self.board.top().evaluate();
		}

		const tt = self.pool.tt;
		const ttf = tt.fetch(key);
		const tte = ttf[0].*;
		const tth = ttf[1]
		  and tte.key == @as(@TypeOf(tte.key), @truncate(key))
		  and tte.flag != .none;

		const was_pv = tth and tte.was_pv;

		if (!is_pv and tth and tte.shouldTrust(a, b, d)) {
			return tte.score;
		}

		const has_tteval = tth
		  and tte.eval > evaluation.score.lose
		  and tte.eval < evaluation.score.win;
		const stat_eval = if (is_checked) evaluation.score.none
		  else if (has_tteval) tte.eval else pos.evaluate();

		const use_ttscore = tth
		  and tte.score > evaluation.score.lose
		  and tte.score < evaluation.score.win
		  and !(tte.flag == .upperbound and tte.score >  stat_eval)
		  and !(tte.flag == .lowerbound and tte.score <= stat_eval);
		// TODO: correct eval in case tt score is unusable
		const corr_eval = if (use_ttscore) tte.score else stat_eval;

		pos.stat_eval = stat_eval;
		pos.corr_eval = corr_eval;

		// internal iterative reduction (iir)
		const has_ttm = tth and pos.isMovePseudoLegal(tte.move);
		if (node.hasLower() and depth >= 4 and !has_ttm) {
			d -= 1;
		}

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
		  and b > evaluation.score.lose
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
				board.doNull() catch std.debug.panic("invalid null move", .{});
				defer board.undoNull();

				break :null_search -self.ab(node.flip(), ply + 1, -b, 1 - b, d - r);
			};

			if (s >= b) {
				if (evaluation.score.isMate(s)) {
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

		// razoring
		if (!is_pv and !is_checked and d < 8 and corr_eval + 460 * d <= a) {
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

			const is_ttm = m == mp.ttm;
			const is_noisy = (is_ttm and is_ttm_noisy) or mp.stage.isNoisy();
			const is_quiet = (is_ttm and is_ttm_quiet) or mp.stage.isQuiet();

			if (!is_root and best.score > evaluation.score.lose) {
				// late move pruning (lmp)
				const very_late: usize = @intCast(d * d + 4);
				if (searched > very_late) {
					break :move_loop;
				}
			}

			var recur_d = d - 1;
			var r: Depth = 0;

			const s = recur: {
				board.doMove(m) catch continue :move_loop;
				tt.prefetch(board.top().key);

				defer board.undoMove();
				defer searched += 1;

				var score: @TypeOf(a, b) = evaluation.score.none;
				if (is_pv and searched == 0) {
					score = -self.ab(.exact, ply + 1, -b, -a, recur_d);
					break :recur score;
				}

				const is_late = searched
				  > @as(usize, @intFromBool(is_pv))
				  + @as(usize, @intFromBool(is_root))
				  + @as(usize, @intFromBool(is_noisy))
				  + @as(usize, @intFromBool(mp.ttm.isNone()));

				score = if (d >= 3 and searched > 1 and is_late) reduced: {
					r += lmr.get(d, searched, is_quiet);
					r += @intFromBool(node == .lowerbound);
					r += @intFromBool(is_ttm_noisy);
					r -= @intFromBool(is_pv);

					const rd = std.math.clamp(recur_d -| r, 1, recur_d);
					var rs = -self.ab(.lowerbound, ply + 1, -a - 1, -a, rd);

					if (rs > a and rd < recur_d) {
						recur_d += @intFromBool(rs > best.score);
						recur_d -= @intFromBool(rs < best.score);

						rs = -self.ab(node.flip(), ply + 1, -a - 1, -a, recur_d);
					}

					break :reduced rs;
				} else -self.ab(node.flip(), ply + 1, -a - 1, -a, recur_d);

				score = if (is_pv and score > a) -self.ab(.exact, ply + 1, -b, -a, recur_d)
				  else score;

				break :recur score;
			};

			if (!self.pool.searching) {
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

		ttf[0].* = .{
			.was_pv = was_pv or flag == .exact,
			.flag = flag,
			.age = @truncate(tt.age),
			.depth = @intCast(depth),
			.key = @truncate(key),
			.eval = @intCast(stat_eval),
			.score = best.score,
			.move = if (!best.move.isNone()) best.move else mp.ttm,
		};

		return best.score;
	}

	fn qs(self: *Thread,
	  ply: usize,
	  alpha: evaluation.score.Int,
	  beta:  evaluation.score.Int) evaluation.score.Int {
		self.nodes += 1;
		self.board.top().pv.line.resize(0) catch unreachable;

		const is_main = self.idx == 0;
		if (is_main and self.hardStop()) {
			self.pool.stop();
			return alpha;
		}

		if (!self.pool.searching) {
			return alpha;
		}

		const draw = evaluation.score.draw;
		const lose = evaluation.score.lose + 1;

		const b = beta;
		var a = alpha;

		if (!self.pool.searching) {
			return a;
		}

		if (self.idx == 0 and !self.pool.options.infinite) {
			const options = &self.pool.options;
			const nodes = self.nodes;
			const timer = &self.pool.timer;

			const exceed_nodes = if (options.nodes) |lim| nodes >= lim else false;
			const exceed_time = options.stop != null
			  and nodes % 2048 == 0
			  and timer.read() / std.time.ns_per_ms >= options.stop.?;

			if (exceed_time or exceed_nodes) {
				self.pool.stop();
				return a;
			}
		}

		const board = &self.board;
		const pos = board.top();
		const key = pos.key;
		const is_checked = pos.isChecked();
		if (self.board.isDrawn()) {
			return draw;
		} else if (self.board.isTerminal()) {
			return self.board.top().evaluate();
		}

		const tt = self.pool.tt;
		const ttf = tt.fetch(key);

		const tte = ttf[0].*;
		const tth = ttf[1]
		  and tte.flag != .none
		  and tte.key == @as(@TypeOf(tte.key), @truncate(key));

		if (tth and tte.shouldTrust(a, b, 0)) {
			return tte.score;
		}

		const has_tteval = tth
		  and tte.eval > evaluation.score.lose
		  and tte.eval < evaluation.score.win;
		const stat_eval = if (is_checked) evaluation.score.none
		  else if (has_tteval) tte.eval else pos.evaluate();

		const use_ttscore = tth
		  and tte.score > evaluation.score.lose
		  and tte.score < evaluation.score.win
		  and !(tte.flag == .upperbound and tte.score >  stat_eval)
		  and !(tte.flag == .lowerbound and tte.score <= stat_eval);
		// TODO: correct eval in case tt score is unusable
		const corr_eval = if (use_ttscore) tte.score else stat_eval;

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

				if (!pos.see(m, draw)) {
					continue :move_loop;
				}
			}

			if (!is_checked) {
				const margin = corr_eval + 64;
				if (corr_eval + margin <= a and !pos.see(m, draw + 1)) {
					best.score = @intCast(@max(best.score, corr_eval + margin));
					continue :move_loop;
				}
			}

			const s = recur: {
				board.doMove(m) catch continue :move_loop;
				tt.prefetch(board.top().key);

				defer board.undoMove();
				defer mp.skipQuiets();
				defer searched += 1;

				break :recur -self.qs(ply + 1, -b, -a);
			};

			if (!self.pool.searching) {
				return a;
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
			.move = if (!best.move.isNone()) best.move else mp.ttm,
		};

		return best.score;
	}

	pub fn getQuietHist(self: *const Thread, move: movegen.Move) hist.Int {
		return self.quietHistPtr(move).*;
	}
};

pub const Pool = struct {
	allocator:	std.mem.Allocator,
	threads:	[]Thread,
	options:	Options,

	timer:	std.time.Timer,
	searching:	bool,
	finished:	bool,

	quiet:	bool,
	io:	*types.Io,
	tt:	*transposition.Table,

	pub fn deinit(self: *Pool) void {
		self.allocator.free(self.threads);
		self.threads = undefined;
	}

	pub fn init(allocator: std.mem.Allocator,
	  threads: ?usize,
	  quiet: bool,
	  io: *types.Io,
	  tt: *transposition.Table) !Pool {
		const options: Options = .{};
		return .{
			.allocator = allocator,
			.threads = try allocator.alloc(Thread, threads orelse options.threads),
			.options = options,

			.timer = try std.time.Timer.start(),
			.searching = false,
			.finished = false,

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
		self.searching = false;
		self.finished = false;

		self.options.reset();
		self.timer.reset();

		for (self.threads) |*thread| {
			thread.reset(self);
		}

		const frc = self.options.frc;
		var pos: Board.One = .{};

		try pos.parseFen(Board.One.startpos);
		self.setPosition(&pos, frc);
	}

	pub fn nodes(self: *const Pool) u64 {
		var n: u64 = 0;
		for (self.threads) |*thread| {
			n += thread.nodes;
		}
		return n;
	}

	pub fn setFRC(self: *Pool, frc: bool) void {
		self.options.frc = frc;
		for (self.threads) |*thread| {
			thread.board.frc = frc;
		}
	}

	pub fn setPosition(self: *Pool, src: *const Board.One, frc: bool) void {
		for (self.threads) |*thread| {
			thread.board = .{};
			thread.board.top().* = src.*;
			thread.board.frc = frc;
		}
	}

	pub fn waitFinish(self: *const Pool) void {
		while (!self.finished) {
			std.mem.doNotOptimizeAway(self);
		}
	}

	pub fn waitStart(self: *const Pool) void {
		while (!self.searching) {
			std.mem.doNotOptimizeAway(self);
		}
	}

	pub fn waitStop(self: *const Pool) void {
		while (self.searching) {
			std.mem.doNotOptimizeAway(self);
		}
	}

	pub fn finish(self: *Pool) void {
		self.finished = true;
	}

	pub fn start(self: *Pool) !void {
		const is_threaded = self.threads.len > 1;
		const board = &self.threads[0].board;
		const root_moves = &self.threads[0].root_moves;

		root_moves.* = movegen.Move.Root.List.init(board);
		for (self.threads, 0 ..) |*thread, i| {
			if (is_threaded and i != 0) {
				thread.board = board.*;
				thread.root_moves = root_moves.*;
			}

			thread.idx = i;
			thread.cnt = self.threads.len;

			thread.nodes = 0;
			thread.tbhits = 0;
			thread.tthits = 0;
		}

		self.searching = true;
		self.finished = false;
		self.timer.reset();

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
		self.searching = false;
	}
};

pub const Options = struct {
	frc:	bool = false,
	hash:	usize = 64,
	threads:	usize = 1,
	overhead:	u64 = 10,

	infinite:		bool = false,
	depth:	?Depth = null,
	nodes:	?u64 = null,

	incr: std.EnumMap(types.Color, u64) = std.EnumMap(types.Color, u64).init(.{}),
	time: std.EnumMap(types.Color, u64) = std.EnumMap(types.Color, u64).init(.{}),

	movetime:	?u64 = null,
	stop:	?u64 = null,

	pub fn reset(self: *Options) void {
		self.* = .{};
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

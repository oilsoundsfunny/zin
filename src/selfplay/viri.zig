const base = @import("base");
const engine = @import("engine");
const std = @import("std");

pub const Self = extern struct {
	occ:	base.types.Square.Set,
	board:	@Vector(32, u4),
	flag:	u8,
	rule50:	u8,
	length:	u16,
	score:	engine.evaluation.score.Int,
	result:	Result,
	pad:	u8,

	const Result = enum(u8) {
		black,
		draw,
		white,
		_,
	};

	fn fromPiece(p: base.types.Piece) u4 {
		// viriformat requires castle-able rooks
		return switch (p) {
			.w_pawn => 0,
			.w_knight => 1,
			.w_bishop => 2,
			.w_rook => 3,
			.w_queen => 4,
			.w_king => 5,

			.b_pawn => 8,
			.b_knight => 9,
			.b_bishop => 10,
			.b_rook => 11,
			.b_queen => 12,
			.b_king => 13,

			else => std.debug.panic("invalid piece", .{}),
		};
	}

	pub fn fromPosition(pos: *const engine.Position) Self {
		var self = std.mem.zeroInit(Self, .{});

		var occ = pos.ptypeOcc(.all);
		var si: usize = 0;
		self.occ = occ;
		while (occ.lowSquare()) |s| : ({
			si += 1;
			occ.popLow();
		}) {
			const p = pos.getSquare(s);
			self.board[si] = switch (p) {
				.w_rook => blk: {
					var iter = @constCast(pos).castle.iterator();
					break :blk loop: while (iter.next()) |entry| {
						if (entry.value.rs == s) {
							break :loop 6;
						}
					} else fromPiece(p);
				},

				.b_rook => blk: {
					var iter = @constCast(pos).castle.iterator();
					break :blk loop: while (iter.next()) |entry| {
						if (entry.value.rs == s) {
							break :loop 14;
						}
					} else fromPiece(p);
				},

				else => fromPiece(p),
			};
		}

		self.flag = if (pos.ss.top().en_pas) |s| s.tag() orelse base.types.Square.cnt;
		if (pos.stm == .black) {
			self.flag |= 1 << 8;
		}

		self.score = engine.evaluation.score.fromPosition(pos);
		self.result = .draw;

		return self;
	}
};

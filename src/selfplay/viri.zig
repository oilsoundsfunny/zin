const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");
const types = @import("types");

const Piece = enum(u4) {
	w_pawn = 0,
	w_knight = 1,
	w_bishop = 2,
	w_rook = 3,
	w_queen = 4,
	w_king = 5,
	w_castle = 6,

	b_pawn = 8,
	b_knight = 9,
	b_bishop = 10,
	b_rook = 11,
	b_queen = 12,
	b_king = 13,
	b_castle = 14,

	const Tag = std.meta.Tag(Piece);

	const tag_info = @typeInfo(Tag).int;

	fn fromSquare(pos: *const engine.Position, s: types.Square) Piece {
		var iter = @constCast(pos).castles.iterator();

		return switch (pos.getSquare(s)) {
			.w_rook => loop: while (iter.next()) |entry| {
				const k = entry.key;
				const v = entry.value;

				if (pos.ss.top().castle.get(k) and v.rs == s) {
					break :loop Piece.w_castle;
				}
			} else Piece.w_rook,

			.b_rook => loop: while (iter.next()) |entry| {
				const k = entry.key;
				const v = entry.value;

				if (pos.ss.top().castle.get(k) and v.rs == s) {
					break :loop Piece.b_castle;
				}
			} else Piece.b_rook,

			.none => std.debug.panic("invalid piece", .{}),
			inline else => |e| @field(Piece, @tagName(e)),
		};
	}

	fn fromTag(i: Tag) Piece {
		return @enumFromInt(i);
	}

	fn tag(self: Piece) Tag {
		return @intFromEnum(self);
	}
};

pub const Move = packed struct(u16) {
	src:	types.Square = @enumFromInt(0),
	dst:	types.Square = @enumFromInt(0),
	info:	engine.movegen.Move.Info = .{.none = 0},
	flag:	engine.movegen.Move.Flag = .none,

	pub const Scored = extern struct {
		move:	Move = .{},
		score:	i16 = engine.evaluation.score.draw,
	};

	pub const zero: Move = .{};

	pub fn fromMove(move: engine.movegen.Move) Move {
		return .{
			.flag = move.flag,
			.info = if (move.flag == .promote) move.info else .{.none = 0},
			.src = move.src,
			.dst = move.dst,
		};
	}
};

pub const Result = enum(u8) {
	black,
	draw,
	white,
	_,
};

pub const Self = extern struct {
	occ:	types.Square.Set = .none,
	pieces:	u128 align(8) = 0,

	flag:	u8 = 0,

	ply:	u8 = 0,
	length:	u16 = 0,
	score:	i16 = 0,

	result:	Result = .draw,
	pad:	u8 = 0,

	pub fn fromPosition(pos: *const engine.Position) Self {
		var self = std.mem.zeroInit(Self, .{});
		const eval = pos.evaluate();

		self.ply = pos.ss.top().rule50;
		self.length = 0;
		self.score = @intCast(switch (pos.stm) {
			.white => eval,
			.black => -eval,
		});

		var i: usize = 0;
		var occ = pos.bothOcc();
		self.occ = occ;
		while (occ.lowSquare()) |s| : ({
			i += 1;
			occ.popLow();
		}) {
			const t = Piece.fromSquare(pos, s).tag();
			self.pieces |= std.math.shl(u128, t, i * Piece.tag_info.bits);
		}

		self.flag = if (pos.ss.top().en_pas) |s| s.tag() else types.Square.cnt;
		if (pos.stm == .black) {
			self.flag |= 1 << 7;
		}

		return self;
	}
};

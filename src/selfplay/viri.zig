const base = @import("base");
const bounded_array = @import("bounded_array");
const engine = @import("engine");
const std = @import("std");

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

	fn fromSquare(pos: *const engine.Position, s: base.types.Square) Piece {
		var iter = @constCast(pos).castles.iterator();

		return switch (pos.getSquare(s)) {
			.w_pawn => .w_pawn,
			.w_knight => .w_knight,
			.w_bishop => .w_bishop,
			.w_queen => .w_queen,
			.w_king => .w_king,

			.w_rook => loop: while (iter.next()) |entry| {
				const k = entry.key;
				const v = entry.value;

				if (pos.ss.top().castle.get(k) and v.rs == s) {
					break :loop Piece.w_castle;
				}
			} else Piece.w_rook,

			.b_pawn => .b_pawn,
			.b_knight => .b_knight,
			.b_bishop => .b_bishop,
			.b_queen => .b_queen,
			.b_king => .b_king,

			.b_rook => loop: while (iter.next()) |entry| {
				const k = entry.key;
				const v = entry.value;

				if (pos.ss.top().castle.get(k) and v.rs == s) {
					break :loop Piece.b_castle;
				}
			} else Piece.b_rook,

			else => @enumFromInt(0),
		};
	}

	fn fromTag(i: Tag) Piece {
		return @enumFromInt(i);
	}

	fn tag(self: Piece) Tag {
		return @intFromEnum(self);
	}
};

pub const Move = engine.movegen.Move;

pub const Result = enum(u8) {
	black,
	draw,
	white,
	_,
};

pub const Self = extern struct {
	occ:	base.types.Square.Set,
	pieces:	u128,
	flag:	u8,
	ply:	u8,
	length:	u16,
	score:	i16,
	result:	Result,
	pad:	u8,

	pub fn fromPosition(pos: *const engine.Position) Self {
		var self = std.mem.zeroInit(Self, .{});

		var i: usize = 0;
		var occ = pos.ptypeOcc(.all);
		self.occ = occ;
		while (occ.lowSquare()) |s| : ({
			i += 1;
			occ.popLow();
		}) {
			const p = Piece.fromSquare(pos, s);
			self.pieces |= std.math.shl(u128, p.tag(),
			  @as(usize, s.tag()) * @typeInfo(Piece.Tag).int.bits);
		}

		self.flag = if (pos.ss.top().en_pas) |s| s.tag() else base.types.Square.cnt;
		if (pos.stm == .black) {
			self.flag |= 1 << 7;
		}

		return self;
	}
};

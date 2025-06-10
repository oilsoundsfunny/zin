const std = @import("std");

pub const Color = enum(u1) {
	white,
	black,

	const char_map = std.EnumMap(Color, u8).init(.{
		.white = 'w',
		.black = 'b',
	});

	pub const Int = std.meta.Tag(Color);
	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);
	pub const num = max - min + 1;
	pub const values = std.enums.values(Color);

	pub fn char(self: Color) ?u8 {
		return char_map.get(self);
	}
	pub fn int(self: Color) Int {
		return @intFromEnum(self);
	}

	pub fn fromChar(c: u8) ?Color {
		inline for (values) |f| {
			const v = f.char();
			if (v != null and v == c) {
				return f;
			}
		}
		return null;
	}

	pub fn flip(self: Color) Color {
		return switch (self) {
			.white => .black,
			.black => .white,
		};
	}

	pub fn forward(self: Color) Direction {
		return switch (self) {
			.white => .north,
			.black => .south,
		};
	}

	pub fn homeRank(self: Color) Rank {
		return switch (self) {
			.white => .rank_1,
			.black => .rank_8,
		};
	}
	pub fn pawnRank(self: Color) Rank {
		return switch (self) {
			.white => .rank_2,
			.black => .rank_7,
		};
	}
	pub fn promotionRank(self: Color) Rank {
		return self.flip().homeRank();
	}
};

pub const Ptype = enum(u3) {
	nil,
	pawn,
	knight,
	bishop,
	rook,
	queen,
	king,
	all,

	const char_map = std.EnumMap(Ptype, u8).init(.{
		.pawn = 'p',
		.knight = 'n',
		.bishop = 'b',
		.rook = 'r',
		.queen = 'q',
		.king = 'k',
	});

	pub const Int = std.meta.Tag(Ptype);
	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);
	pub const num = max - min + 1;
	pub const values = std.enums.values(Ptype);

	pub fn char(self: Ptype) ?u8 {
		return char_map.get(self);
	}
	pub fn int(self: Ptype) Int {
		return @intFromEnum(self);
	}

	pub fn fromChar(c: u8) ?Ptype {
		inline for (values) |f| {
			const v = f.char();
			if (v != null and v == c) {
				return f;
			}
		}
		return null;
	}
};

pub const Piece
  = enum(std.meta.Int(.unsigned, @typeInfo(Color.Int).int.bits + @typeInfo(Ptype.Int).int.bits)) {
	nil,

	w_pawn = Ptype.num * @as(comptime_int, Color.white.int()) + @as(comptime_int, Ptype.pawn.int()),
	w_knight,
	w_bishop,
	w_rook,
	w_queen,
	w_king,
	w_all,

	b_pawn = Ptype.num * @as(comptime_int, Color.black.int()) + @as(comptime_int, Ptype.pawn.int()),
	b_knight,
	b_bishop,
	b_rook,
	b_queen,
	b_king,
	b_all,

	const char_map = std.EnumMap(Piece, u8).init(.{
		.w_pawn = 'P',
		.w_knight = 'N',
		.w_bishop = 'B',
		.w_rook = 'R',
		.w_queen = 'Q',
		.w_king = 'K',
		.b_pawn = 'p',
		.b_knight = 'n',
		.b_bishop = 'b',
		.b_rook = 'r',
		.b_queen = 'q',
		.b_king = 'k',
	});

	pub const Int = std.meta.Tag(Piece);
	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);
	pub const num = max - min + 1;
	pub const values = std.enums.values(Piece);

	pub const w_pieces = values[1 ..][0 .. 6];
	pub const b_pieces = values[8 ..][0 .. 6];

	pub fn char(self: Piece) ?u8 {
		return char_map.get(self);
	}
	pub fn int(self: Piece) Int {
		return @intFromEnum(self);
	}

	pub fn color(self: Piece) Color {
		return @enumFromInt(self.int() / Ptype.num);
	}
	pub fn ptype(self: Piece) Ptype {
		return @enumFromInt(self.int() % Ptype.num);
	}

	pub fn fromChar(c: u8) ?Piece {
		inline for (values) |f| {
			const v = f.char();
			if (v != null and v == c) {
				return f;
			}
		}
		return null;
	}
	pub fn fromPtype(c: Color, p: Ptype) Piece {
		return @enumFromInt(@as(Int, c.int()) * Ptype.num + @as(Int, p.int()));
	}
};
test {
	try std.testing.expectEqual(Piece.w_pawn, Piece.w_pieces[0]);
	try std.testing.expectEqual(Piece.w_king, Piece.w_pieces[Piece.w_pieces.len - 1]);

	try std.testing.expectEqual(Piece.b_pawn, Piece.b_pieces[0]);
	try std.testing.expectEqual(Piece.b_king, Piece.b_pieces[Piece.b_pieces.len - 1]);
}

pub const Rank = enum(u3) {
	rank_1,
	rank_2,
	rank_3,
	rank_4,
	rank_5,
	rank_6,
	rank_7,
	rank_8,

	const char_map = std.EnumMap(Rank, u8).init(.{
		.rank_1 = '1',
		.rank_2 = '2',
		.rank_3 = '3',
		.rank_4 = '4',
		.rank_5 = '5',
		.rank_6 = '6',
		.rank_7 = '7',
		.rank_8 = '8',
	});

	pub const Int = std.meta.Tag(Rank);
	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);
	pub const num = max - min + 1;
	pub const values = std.enums.values(Rank);

	pub fn char(self: Rank) ?u8 {
		return char_map.get(self);
	}
	pub fn int(self: Rank) Int {
		return @intFromEnum(self);
	}
	pub fn bb(self: Rank) BitBoard {
		return BitBoard.fromRank(self);
	}

	pub fn fromChar(c: u8) ?Rank {
		inline for (values) |f| {
			const v = f.char();
			if (v != null and v == c) {
				return f;
			}
		}
		return null;
	}
};

pub const File = enum(u3) {
	file_a,
	file_b,
	file_c,
	file_d,
	file_e,
	file_f,
	file_g,
	file_h,

	const char_map = std.EnumMap(File, u8).init(.{
		.file_a = 'a',
		.file_b = 'b',
		.file_c = 'c',
		.file_d = 'd',
		.file_e = 'e',
		.file_f = 'f',
		.file_g = 'g',
		.file_h = 'h',
	});

	pub const Int = std.meta.Tag(File);
	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);
	pub const num = max - min + 1;
	pub const values = std.enums.values(File);

	pub fn char(self: File) ?u8 {
		return char_map.get(self);
	}
	pub fn int(self: File) Int {
		return @intFromEnum(self);
	}
	pub fn bb(self: File) BitBoard {
		return BitBoard.fromFile(self);
	}

	pub fn fromChar(c: u8) ?File {
		inline for (values) |f| {
			const v = f.char();
			if (v != null and v == c) {
				return f;
			}
		}
		return null;
	}
};

pub const Square
  = enum(std.meta.Int(.unsigned, @typeInfo(Rank.Int).int.bits + @typeInfo(File.Int).int.bits)) {
	a1, b1, c1, d1, e1, f1, g1, h1,
	a2, b2, c2, d2, e2, f2, g2, h2,
	a3, b3, c3, d3, e3, f3, g3, h3,
	a4, b4, c4, d4, e4, f4, g4, h4,
	a5, b5, c5, d5, e5, f5, g5, h5,
	a6, b6, c6, d6, e6, f6, g6, h6,
	a7, b7, c7, d7, e7, f7, g7, h7,
	a8, b8, c8, d8, e8, f8, g8, h8,

	pub const Int = std.meta.Tag(Square);
	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);
	pub const num = max - min + 1;
	pub const values = std.enums.values(Square);

	pub const book_order = [_]Square {
		.a8, .b8, .c8, .d8, .e8, .f8, .g8, .h8,
		.a7, .b7, .c7, .d7, .e7, .f7, .g7, .h7,
		.a6, .b6, .c6, .d6, .e6, .f6, .g6, .h6,
		.a5, .b5, .c5, .d5, .e5, .f5, .g5, .h5,
		.a4, .b4, .c4, .d4, .e4, .f4, .g4, .h4,
		.a3, .b3, .c3, .d3, .e3, .f3, .g3, .h3,
		.a2, .b2, .c2, .d2, .e2, .f2, .g2, .h2,
		.a1, .b1, .c1, .d1, .e1, .f1, .g1, .h1,
	};

	pub fn int(self: Square) Int {
		return @intFromEnum(self);
	}

	pub fn rank(self: Square) Rank {
		return @enumFromInt(self.int() / File.num);
	}
	pub fn file(self: Square) File {
		return @enumFromInt(self.int() % File.num);
	}
	pub fn bb(self: Square) BitBoard {
		return BitBoard.fromSquare(self);
	}

	pub fn fromCoord(r: Rank, f: File) Square {
		return @enumFromInt(@as(Int, r.int()) * File.num + @as(Int, f.int()));
	}

	pub fn okShift(self: Square, comptime dir: Direction, amt: anytype) bool {
		return switch (dir) {
			Direction.northwest.add(.north) => true
			  and self.okShift(.north, amt * 2)
			  and self.okShift(.west,  amt * 1),
			Direction.northwest.add(.west) => true
			  and self.okShift(.north, amt * 1)
			  and self.okShift(.west,  amt * 2),
			Direction.southwest.add(.west) => true
			  and self.okShift(.south, amt * 1)
			  and self.okShift(.west,  amt * 2),
			Direction.southwest.add(.south) => true
			  and self.okShift(.south, amt * 2)
			  and self.okShift(.west,  amt * 1),
			Direction.southeast.add(.south) => true
			  and self.okShift(.south, amt * 2)
			  and self.okShift(.east,  amt * 1),
			Direction.southeast.add(.east) => true
			  and self.okShift(.south, amt * 1)
			  and self.okShift(.east,  amt * 2),
			Direction.northeast.add(.east) => true
			  and self.okShift(.north, amt * 1)
			  and self.okShift(.east,  amt * 2),
			Direction.northeast.add(.north) => true
			  and self.okShift(.north, amt * 2)
			  and self.okShift(.east,  amt * 1),
			.northwest => self.okShift(.north, amt) and self.okShift(.west, amt),
			.southwest => self.okShift(.south, amt) and self.okShift(.west, amt),
			.southeast => self.okShift(.south, amt) and self.okShift(.east, amt),
			.northeast => self.okShift(.north, amt) and self.okShift(.east, amt),
			.north, .south => vert: {
				const a: isize = @intCast(amt);
				const d: isize = std.math.sign(dir.int());
				const r: isize = self.rank().int();
				break :vert r + a * d <= Rank.max and r + a * d >= Rank.min;
			},
			.west, .east => horz: {
				const a: isize = @intCast(amt);
				const d: isize = std.math.sign(dir.int());
				const f: isize = self.file().int();
				break :horz f + a * d <= File.max and f + a * d >= File.min;
			},
			else => @compileError("unexpected tag " ++ @tagName(dir)),
		};
	}
	pub fn shift(self: Square, dir: Direction, amt: anytype) Square {
		const a: isize = @intCast(amt);
		const d: isize = dir.int();
		const s: isize = self.int();
		const sum = s + d * a;
		return @enumFromInt(sum);
	}
};

pub const Direction = enum(isize) {
	north = 0 - down,
	south = 0 + down,

	west = 0 + left,
	east = 0 - left,

	northwest = 0 - down + left,
	southwest = 0 + down + left,
	southeast = 0 + down - left,
	northeast = 0 - down - left,

	_,

	const down = @as(comptime_int, Square.d4.int()) - @as(comptime_int, Square.d5.int());
	const left = @as(comptime_int, Square.d4.int()) - @as(comptime_int, Square.e4.int());

	pub const Int = std.meta.Tag(Direction);

	pub fn int(self: Direction) Int {
		return @intFromEnum(self);
	}

	pub fn add(self: Direction, other: Direction) Direction {
		return @enumFromInt(self.int() + other.int());
	}
	pub fn mul(self: Direction, amt: anytype) Direction {
		return @enumFromInt(self.int() * amt);
	}
	pub fn flip(self: Direction) Direction {
		return self.mul(-1);
	}
};

pub const BitBoard = enum(std.meta.Int(.unsigned, Square.num)) {
	nil = (1 << (Square.num * 0)) - 1,
	all = (1 << (Square.num * 1)) - 1,
	_,

	const rank_bb: BitBoard = @enumFromInt(0x00000000000000ff);
	const file_bb: BitBoard = @enumFromInt(0x0101010101010101);

	pub const Int = std.meta.Tag(BitBoard);

	pub fn int(self: BitBoard) Int {
		return @intFromEnum(self);
	}

	pub fn flip(self: BitBoard) BitBoard {
		return self.bitXor(.all);
	}
	pub fn flipRank(self: BitBoard) BitBoard {
		return @enumFromInt(@byteSwap(self.int()));
	}
	pub fn flipFile(self: BitBoard) BitBoard {
		var x = self.int();
		x = ((x >> 1) & 0x5555555555555555) + ((x & 0x5555555555555555) << 1);
		x = ((x >> 2) & 0x3333333333333333) + ((x & 0x3333333333333333) << 2);
		x = ((x >> 4) & 0x0f0f0f0f0f0f0f0f) + ((x & 0x0f0f0f0f0f0f0f0f) << 4);
		return @enumFromInt(x);
	}

	pub fn shl(self: BitBoard, amt: anytype) BitBoard {
		return @enumFromInt(std.math.shl(Int, self.int(), amt));
	}
	pub fn shr(self: BitBoard, amt: anytype) BitBoard {
		return @enumFromInt(std.math.shr(Int, self.int(), amt));
	}

	pub fn getSquare(self: BitBoard, s: Square) bool {
		return self.bitAnd(s.bb()) != .nil;
	}
	pub fn popSquare(self: *BitBoard, s: Square) void {
		self.* = self.bitAnd(s.bb().flip());
	}
	pub fn setSquare(self: *BitBoard, s: Square) void {
		self.* = self.bitOr(s.bb());
	}

	pub fn cntSquares(self: BitBoard) u8 {
		return @popCount(self.int());
	}
	pub fn lowSquare(self: BitBoard) Square {
		std.debug.assert(self.cntSquares() > 0);
		return @enumFromInt(@ctz(self.int()));
	}
	pub fn getLow(self: BitBoard) BitBoard {
		std.debug.assert(self.cntSquares() > 0);
		return self.bitAnd(@enumFromInt(0 -% self.int()));
	}
	pub fn popLow(self: *BitBoard) void {
		std.debug.assert(self.cntSquares() > 0);
		self.* = self.bitAnd(@enumFromInt(self.int() - 1));
	}

	pub fn bitAnd(self: BitBoard, other: BitBoard) BitBoard {
		return @enumFromInt(self.int() & other.int());
	}
	pub fn bitOr(self: BitBoard, other: BitBoard) BitBoard {
		return @enumFromInt(self.int() | other.int());
	}
	pub fn bitXor(self: BitBoard, other: BitBoard) BitBoard {
		return @enumFromInt(self.int() ^ other.int());
	}

	pub fn fromRank(r: Rank) BitBoard {
		return rank_bb.shl(@as(Square.Int, r.int()) * File.num);
	}
	pub fn fromFile(f: File) BitBoard {
		return file_bb.shl(@as(Square.Int, f.int()));
	}
	pub fn fromSquare(s: Square) BitBoard {
		return @enumFromInt(std.math.shl(Int, 1, s.int()));
	}
	pub fn fromSlice(comptime T: type, slice: []const T) BitBoard {
		var b = BitBoard.nil;
		for (slice) |item| {
			b = b.bitOr(item.bb());
		}
		return b;
	}

	pub fn permute(self: BitBoard, idx: usize) BitBoard {
		var i = idx;
		var b = self;
		var r = BitBoard.nil;
		while (i != 0) {
			r  = r.bitOr(if (i % 2 != 0) b.getLow() else .nil);
			i /= 2;
			b.popLow();
		}
		return r;
	}
};

pub const Castle = enum(u4) {
	nil = 0b0000,
	all = 0b1111,

	wk = 1 << 0,
	wq = 1 << 1,
	bk = 1 << 2,
	bq = 1 << 3,

	_,

	const char_map = std.EnumMap(Castle, u8).init(.{
		.nil = '-',
		.wk = 'K',
		.wq = 'Q',
		.bk = 'k',
		.bq = 'q',
	});

	pub const Int = std.meta.Tag(Castle);
	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);
	pub const num = max - min + 1;
	pub const values = std.enums.values(Castle);

	pub fn char(self: Castle) ?u8 {
		return char_map.get(self);
	}
	pub fn int(self: Castle) Int {
		return @intFromEnum(self);
	}

	pub fn flip(self: Castle) Castle {
		return self.bitXor(.all);
	}
	pub fn bitAnd(self: Castle, other: Castle) Castle {
		return @enumFromInt(self.int() & other.int());
	}
	pub fn bitOr(self: Castle, other: Castle) Castle {
		return @enumFromInt(self.int() | other.int());
	}
	pub fn bitXor(self: Castle, other: Castle) Castle {
		return @enumFromInt(self.int() ^ other.int());
	}

	pub fn fromChar(c: u8) ?Castle {
		inline for (values) |f| {
			const v = f.char();
			if (v != null and v == c) {
				return f;
			}
		}
		return null;
	}
};

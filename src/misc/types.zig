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
	pub const cnt = max - min + 1;

	pub const values = std.enums.values(Color);

	pub fn char(self: Color) ?u8 {
		return char_map.get(self);
	}

	pub fn int(self: Color) Int {
		return @intFromEnum(self);
	}

	pub fn fromChar(c: u8) ?Color {
		inline for (values) |v| {
			if (v.char()) |from_value| {
				if (c == from_value) {
					return v;
				}
			}
		}
		return null;
	}

	pub fn fromInt(i: Int) Color {
		return @enumFromInt(i);
	}

	pub fn flip(self: Color) Color {
		return switch (self) {
			.white => .black,
			.black => .white,
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

	pub fn castleMask(self: Color) Castle {
		return Castle.fromColor(self);
	}

	pub fn forward(self: Color) Direction {
		return switch (self) {
			.white => .north,
			.black => .south,
		};
	}

	pub fn backward(self: Color) Direction {
		return self.flip().forward();
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
	pub const cnt = max - min + 1;

	pub const values = std.enums.values(Ptype);

	pub fn char(self: Ptype) ?u8 {
		return char_map.get(self);
	}

	pub fn int(self: Ptype) Int {
		return @intFromEnum(self);
	}

	pub fn fromChar(c: u8) ?Ptype {
		inline for (values) |v| {
			if (v.char()) |from_value| {
				if (c == from_value) {
					return v;
				}
			}
		}
		return null;
	}

	pub fn fromInt(i: Int) Ptype {
		return @enumFromInt(i);
	} 
};

pub const Piece
  = enum(std.meta.Int(.unsigned, @typeInfo(Color.Int).int.bits + @typeInfo(Ptype.Int).int.bits)) {
	nil,

	w_pawn = Ptype.cnt
	  * @as(comptime_int, Color.white.int())
	  + @as(comptime_int, Ptype.pawn.int()),
	w_knight,
	w_bishop,
	w_rook,
	w_queen,
	w_king,
	w_all,

	b_pawn = Ptype.cnt
	  * @as(comptime_int, Color.black.int())
	  + @as(comptime_int, Ptype.pawn.int()),
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
	pub const cnt = max - min + 1;

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
		return Color.fromInt(@truncate(self.int() / Ptype.cnt));
	}

	pub fn ptype(self: Piece) Ptype {
		return Ptype.fromInt(@truncate(self.int() % Ptype.cnt));
	}

	pub fn fromChar(c: u8) ?Piece {
		inline for (values) |v| {
			if (v.char()) |from_value| {
				if (c == from_value) {
					return v;
				}
			}
		}
		return null;
	}

	pub fn fromInt(i: Int) Piece {
		return @enumFromInt(i);
	}

	pub fn fromPtype(c: Color, p: Ptype) Piece {
		return fromInt(@as(Int, c.int()) * Ptype.cnt + @as(Int, p.int()));
	}
};

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
	pub const cnt = max - min + 1;

	pub const values = std.enums.values(Rank);

	pub fn char(self: Rank) ?u8 {
		return char_map.get(self);
	}

	pub fn int(self: Rank) Int {
		return @intFromEnum(self);
	}

	pub fn fromChar(c: u8) ?Rank {
		inline for (values) |v| {
			if (v.char()) |from_value| {
				if (c == from_value) {
					return v;
				}
			}
		}
		return null;
	}

	pub fn fromInt(i: Int) Rank {
		return @enumFromInt(i);
	}

	pub fn bb(self: Rank) BitBoard {
		return BitBoard.fromRank(self);
	}

	pub fn shift(self: Rank, comptime dir: Direction) ?Rank {
		return switch (self) {
			switch (dir) {
				.north => .rank_8,
				.south => .rank_1,
				else => @compileError("unexpected tag " ++ @tagName(dir)),
			} => null,
			else => not_edge: {
				const s = Square.fromCoord(self, File.fromInt(File.min));
				const d = s.shift(dir, 1);
				break :not_edge d.rank();
			},
		};
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
	pub const cnt = max - min + 1;

	pub const values = std.enums.values(File);

	pub fn char(self: File) ?u8 {
		return char_map.get(self);
	}

	pub fn int(self: File) Int {
		return @intFromEnum(self);
	}

	pub fn fromChar(c: u8) ?File {
		inline for (values) |v| {
			if (v.char()) |from_value| {
				if (c == from_value) {
					return v;
				}
			}
		}
		return null;
	}

	pub fn fromInt(i: Int) File {
		return @enumFromInt(i);
	}

	pub fn bb(self: File) BitBoard {
		return BitBoard.fromFile(self);
	}

	pub fn shift(self: File, comptime dir: Direction) ?File {
		return switch (self) {
			switch (dir) {
				.west => .file_a,
				.east => .file_h,
				else => @compileError("unexpected tag " ++ @tagName(dir)),
			} => null,
			else => not_edge: {
				const s = Square.fromCoord(Rank.fromInt(Rank.min), self);
				const d = s.shift(dir, 1);
				break :not_edge d.file();
			},
		};
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
	pub const cnt = max - min + 1;

	pub const values = std.enums.values(Square);

	pub fn int(self: Square) Int {
		return @intFromEnum(self);
	}

	pub fn fromCoord(r: Rank, f: File) Square {
		return fromInt(@as(Int, r.int()) * File.cnt + @as(Int, f.int()));
	}

	pub fn fromInt(i: Int) Square {
		return @enumFromInt(i);
	}

	pub fn okShift(self: Square, dir: Direction, amt: anytype) bool {
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
				const a: i8 = @intCast(amt);
				const d: i8 = std.math.sign(dir.int());
				const r: i8 = self.rank().int();
				break :vert r + a * d >= Rank.min and r + a * d <= Rank.max;
			},

			.west, .east => horz: {
				const a: i8 = @intCast(amt);
				const d: i8 = std.math.sign(dir.int());
				const f: i8 = self.file().int();
				break :horz f + a * d >= File.min and f + a * d <= File.max;
			},

			else => std.debug.panic("unexpected enum value", .{}),
		};
	}

	pub fn shift(self: Square, dir: Direction, amt: anytype) Square {
		const s: i8 = self.int();
		const d: i8 = dir.int();
		const a: i8 = @intCast(amt);
		const sum = s + d * a;
		return fromInt(@intCast(sum));
	}

	pub fn rank(self: Square) Rank {
		return Rank.fromInt(@truncate(self.int() / File.cnt));
	}

	pub fn file(self: Square) File {
		return File.fromInt(@truncate(self.int() % File.cnt));
	}

	pub fn bb(self: Square) BitBoard {
		return BitBoard.fromSquare(self);
	}
};

pub const Direction = enum(i8) {
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

	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);

	pub fn int(self: Direction) Int {
		return @intFromEnum(self);
	}

	pub fn fromInt(i: Int) Direction {
		return @enumFromInt(i);
	}

	pub fn add(self: Direction, other: Direction) Direction {
		return fromInt(self.int() + other.int());
	}

	pub fn mul(self: Direction, amt: anytype) Direction {
		return fromInt(self.int() * @as(Int, @intCast(amt)));
	}

	pub fn flip(self: Direction) Direction {
		return self.mul(-1);
	}
};

pub const BitBoard = enum(std.meta.Int(.unsigned, Square.cnt)) {
	nil = (1 << (Square.cnt * 0)) - 1,
	all = (1 << (Square.cnt * 1)) - 1,
	_,

	const ranks_bb = std.EnumArray(Rank, BitBoard).init(.{
		.rank_1 = fromSlice(Square, &.{.a1, .b1, .c1, .d1, .e1, .f1, .g1, .h1}),
		.rank_2 = fromSlice(Square, &.{.a2, .b2, .c2, .d2, .e2, .f2, .g2, .h2}),
		.rank_3 = fromSlice(Square, &.{.a3, .b3, .c3, .d3, .e3, .f3, .g3, .h3}),
		.rank_4 = fromSlice(Square, &.{.a4, .b4, .c4, .d4, .e4, .f4, .g4, .h4}),
		.rank_5 = fromSlice(Square, &.{.a5, .b5, .c5, .d5, .e5, .f5, .g5, .h5}),
		.rank_6 = fromSlice(Square, &.{.a6, .b6, .c6, .d6, .e6, .f6, .g6, .h6}),
		.rank_7 = fromSlice(Square, &.{.a7, .b7, .c7, .d7, .e7, .f7, .g7, .h7}),
		.rank_8 = fromSlice(Square, &.{.a8, .b8, .c8, .d8, .e8, .f8, .g8, .h8}),
	});

	const files_bb = std.EnumArray(File, BitBoard).init(.{
		.file_a = fromSlice(Square, &.{.a1, .a2, .a3, .a4, .a5, .a6, .a7, .a8}),
		.file_b = fromSlice(Square, &.{.b1, .b2, .b3, .b4, .b5, .b6, .b7, .b8}),
		.file_c = fromSlice(Square, &.{.c1, .c2, .c3, .c4, .c5, .c6, .c7, .c8}),
		.file_d = fromSlice(Square, &.{.d1, .d2, .d3, .d4, .d5, .d6, .d7, .d8}),
		.file_e = fromSlice(Square, &.{.e1, .e2, .e3, .e4, .e5, .e6, .e7, .e8}),
		.file_f = fromSlice(Square, &.{.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8}),
		.file_g = fromSlice(Square, &.{.g1, .g2, .g3, .g4, .g5, .g6, .g7, .g8}),
		.file_h = fromSlice(Square, &.{.h1, .h2, .h3, .h4, .h5, .h6, .h7, .h8}),
	});

	pub const Int = std.meta.Tag(BitBoard);

	pub fn int(self: BitBoard) Int {
		return @intFromEnum(self);
	}

	pub fn fromInt(i: Int) BitBoard {
		return @enumFromInt(i);
	}

	pub fn fromRank(r: Rank) BitBoard {
		return ranks_bb.get(r);
	}

	pub fn fromFile(f: File) BitBoard {
		return files_bb.get(f);
	}

	pub fn fromSquare(s: Square) BitBoard {
		return fromInt(std.math.shl(Int, 1, s.int()));
	}

	pub fn fromSlice(comptime T: type, slice: []const T) BitBoard {
		var b = BitBoard.nil;
		return switch (T) {
			Int => int_blk: {
				for (slice) |item| {
					b = b.bitOr(fromInt(item));
				}
				break :int_blk b;
			},
			Rank, File, Square => enum_blk: {
				for (slice) |item| {
					b = b.bitOr(item.bb());
				}
				break :enum_blk b;
			},
			else => @compileError("unexpected type " ++ @typeName(T)),
		};
	}

	pub fn flip(self: BitBoard) BitBoard {
		return self.bitXor(.all);
	}

	pub fn shl(self: BitBoard, amt: anytype) BitBoard {
		return fromInt(std.math.shl(Int, self.int(), amt));
	}

	pub fn shr(self: BitBoard, amt: anytype) BitBoard {
		return fromInt(std.math.shr(Int, self.int(), amt));
	}

	pub fn bitAnd(self: BitBoard, other: BitBoard) BitBoard {
		return fromInt(self.int() & other.int());
	}

	pub fn bitOr(self: BitBoard, other: BitBoard) BitBoard {
		return fromInt(self.int() | other.int());
	}

	pub fn bitXor(self: BitBoard, other: BitBoard) BitBoard {
		return fromInt(self.int() ^ other.int());
	}

	pub fn getSquare(self: BitBoard, s: Square) bool {
		return self.bitAnd(s.bb()) != .nil;
	}

	pub fn lowSquare(self: BitBoard) Square {
		return Square.fromInt(@truncate(@ctz(self.int())));
	}

	pub fn popSquare(self: *BitBoard, s: Square) void {
		self.* = self.bitAnd(s.bb().flip());
	}

	pub fn setSquare(self: *BitBoard, s: Square) void {
		self.* = self.bitOr(s.bb());
	}

	pub fn popCount(self: BitBoard) u8 {
		return @popCount(self.int());
	}

	pub fn getLow(self: BitBoard) BitBoard {
		std.debug.assert(self != .nil);
		return self.bitAnd(fromInt(0 -% self.int()));
	}

	pub fn popLow(self: *BitBoard) void {
		std.debug.assert(self.* != .nil);
		self.* = self.bitAnd(fromInt(self.int() - 1));
	}

	pub fn permute(self: BitBoard, idx: usize) BitBoard {
		var i = idx;
		var m = self;
		var r = BitBoard.nil;

		while (i != 0) {
			if (i % 2 != 0) {
				r.setSquare(m.lowSquare());
			}
			i /= 2;
			m.popLow();
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

	pub const cnt = max - min + 1;
	pub const max = std.math.maxInt(Int);
	pub const min = std.math.minInt(Int);

	pub const values = std.enums.values(Castle);

	pub fn char(self: Castle) ?u8 {
		return char_map.get(self);
	}

	pub fn int(self: Castle) Int {
		return @intFromEnum(self);
	}

	pub fn fromChar(c: u8) ?Castle {
		inline for (values) |v| {
			if (v.char()) |from_value| {
				if (from_value == c) {
					return v;
				}
			}
		}
		return null;
	}

	pub fn fromColor(c: Color) Castle {
		return switch (c) {
			.white => Castle.nil.bitOr(.wk).bitOr(.wq),
			.black => Castle.nil.bitOr(.bk).bitOr(.bq),
		};
	}

	pub fn fromInt(i: Int) Castle {
		return @enumFromInt(i);
	}

	pub fn flip(self: Castle) Castle {
		return self.bitXor(.all);
	}

	pub fn bitAnd(self: Castle, other: Castle) Castle {
		return fromInt(self.int() & other.int());
	}

	pub fn bitOr(self: Castle, other: Castle) Castle {
		return fromInt(self.int() | other.int());
	}

	pub fn bitXor(self: Castle, other: Castle) Castle {
		return fromInt(self.int() ^ other.int());
	}
};

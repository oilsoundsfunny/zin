const std = @import("std");

pub const IO = @import("IO.zig");

const SquareSet = enum(std.meta.Int(.unsigned, Square.cnt)) {
	none = (1 << (Square.cnt * 0)) - 1,
	full = (1 << (Square.cnt * 1)) - 1,
	_,

	pub const Tag = std.meta.Tag(SquareSet);

	fn fromRank(r: Rank) SquareSet {
		// TODO: make this fn order-agnostic
		const s = @as(Square.Tag, r.tag()) * File.cnt;
		return fromTag(std.math.shl(Tag, 0x00000000000000ff, s));
	}

	fn fromFile(f: File) SquareSet {
		// TODO: make this fn order-agnostic
		const s = @as(Square.Tag, f.tag());
		return fromTag(std.math.shl(Tag, 0x0101010101010101, s));
	}

	fn fromSquare(s: Square) SquareSet {
		return fromTag(1).shl(s.tag());
	}

	pub fn fromSlice(comptime T: type, slice: []const T) SquareSet {
		var b = SquareSet.none;
		for (slice) |item| {
			b = b.bwo(switch (T) {
				Square, Rank, File => item.toSet(),
				SquareSet => item,
				Tag => fromTag(item),
				else => @compileError("unexpected type " ++ @typeName(T)),
			});
		}
		return b;
	}

	pub fn fromTag(i: Tag) SquareSet {
		return @enumFromInt(i);
	}

	pub fn tag(self: SquareSet) Tag {
		return @intFromEnum(self);
	}

	pub fn bwa(self: SquareSet, other: SquareSet) SquareSet {
		return fromTag(self.tag() & other.tag());
	}

	pub fn bwo(self: SquareSet, other: SquareSet) SquareSet {
		return fromTag(self.tag() | other.tag());
	}

	pub fn bwx(self: SquareSet, other: SquareSet) SquareSet {
		return fromTag(self.tag() ^ other.tag());
	}

	pub fn flip(self: SquareSet) SquareSet {
		return self.bwx(.full);
	}

	pub fn flipRank(self: SquareSet) SquareSet {
		// TODO: make this fn order-agnostic
		const i = self.tag();
		return fromTag(@byteSwap(i));
	}

	pub fn flipFile(self: SquareSet) SquareSet {
		// TODO: make this fn order-agnostic
		const k = [_]Tag {
			0x5555555555555555,
			0x3333333333333333,
			0x0f0f0f0f0f0f0f0f,
		};
		var x = self.tag();

		for (k, 0 ..) |c, i| {
			const s = std.math.shl(usize, 1, i);
			const m = std.math.shl(usize, 1, s);

			const lhs = (x >> s) & c;
			const rhs = (x & c) *% m;
			x = lhs + rhs;
		}
		return fromTag(x);
	}

	pub fn shl(self: SquareSet, amt: anytype) SquareSet {
		const i = std.math.shl(Tag, self.tag(), amt);
		return fromTag(i);
	}

	pub fn shr(self: SquareSet, amt: anytype) SquareSet {
		const i = std.math.shr(Tag, self.tag(), amt);
		return fromTag(i);
	}

	pub fn get(self: SquareSet, s: Square) bool {
		return self.bwa(s.toSet()) != .none;
	}

	pub fn pop(self: *SquareSet, s: Square) void {
		self.popOther(s.toSet());
	}

	pub fn set(self: *SquareSet, s: Square) void {
		self.setOther(s.toSet());
	}

	pub fn getLow(self: SquareSet) SquareSet {
		return self.bwa(fromTag(0 -% self.tag()));
	}

	pub fn popLow(self: *SquareSet) void {
		self.* = self.bwa(fromTag(self.tag() -% 1));
	}

	pub fn popOther(self: *SquareSet, other: SquareSet) void {
		self.* = self.bwa(other.flip());
	}

	pub fn setOther(self: *SquareSet, other: SquareSet) void {
		self.* = self.bwo(other);
	}

	pub fn count(self: SquareSet) u8 {
		return @popCount(self.tag());
	}

	pub fn lowSquare(self: SquareSet) ?Square {
		const ctz = @ctz(self.tag());
		return if (ctz >= Square.cnt) null else Square.fromTag(@intCast(ctz));
	}
};

const CastleSet = enum(std.meta.Int(.unsigned, Castle.cnt)) {
	none = (1 << (Castle.cnt * 0)) - 1,
	full = (1 << (Castle.cnt * 1)) - 1,
	_,

	pub const Tag = std.meta.Tag(CastleSet);

	pub fn fromCastle(c: Castle) CastleSet {
		const i = std.math.shl(Tag, 1, c.tag());
		return fromTag(i);
	}

	pub fn fromTag(i: Tag) CastleSet {
		return @enumFromInt(i);
	}

	pub fn tag(self: CastleSet) Tag {
		return @intFromEnum(self);
	}

	pub fn bwa(self: CastleSet, other: CastleSet) CastleSet {
		return fromTag(self.tag() & other.tag());
	}

	pub fn bwo(self: CastleSet, other: CastleSet) CastleSet {
		return fromTag(self.tag() | other.tag());
	}

	pub fn bwx(self: CastleSet, other: CastleSet) CastleSet {
		return fromTag(self.tag() ^ other.tag());
	}

	pub fn flip(self: CastleSet) CastleSet {
		return self.bwx(.full);
	}

	pub fn get(self: CastleSet, s: Castle) bool {
		return self.bwa(s.toSet()) != .none;
	}

	pub fn pop(self: *CastleSet, s: Castle) void {
		self.popOther(s.toSet());
	}

	pub fn set(self: *CastleSet, s: Castle) void {
		self.setOther(s.toSet());
	}

	pub fn popOther(self: *CastleSet, other: CastleSet) void {
		self.* = self.bwa(other.flip());
	}

	pub fn setOther(self: *CastleSet, other: CastleSet) void {
		self.* = self.bwo(other);
	}

	pub fn count(self: CastleSet) u8 {
		return @popCount(self.tag());
	}
};

pub const Ptype = enum(u3) {
	pawn,
	knight,
	bishop,
	rook,
	queen,
	king,
	none,

	const char_array = std.EnumArray(Ptype, u8).init(.{
		.pawn = 'p',
		.knight = 'n',
		.bishop = 'b',
		.rook = 'r',
		.queen = 'q',
		.king = 'k',
		.none = '.',
	});

	pub const Tag = std.meta.Tag(Ptype);
	pub const tag_info = @typeInfo(Tag).int;

	pub const cnt: comptime_int = values.len - 1;
	pub const values = std.enums.values(Ptype);

	pub fn fromTag(i: Tag) Ptype {
		return @enumFromInt(i);
	}

	pub fn tag(self: Ptype) Tag {
		return @intFromEnum(self);
	}

	pub fn char(self: Ptype) u8 {
		return char_array.getPtrConst(self).*;
	}

	pub fn fromChar(c: u8) ?Ptype {
		inline for (values) |v| {
			if (c == v.char()) {
				return v;
			}
		}
		return null;
	}
};

pub const Color = enum(u1) {
	white,
	black,

	const char_array = std.EnumArray(Color, u8).init(.{
		.white = 'w',
		.black = 'b',
	});

	pub const Tag = std.meta.Tag(Color);
	pub const tag_info = @typeInfo(Tag).int;

	pub const cnt: comptime_int = values.len;
	pub const values = std.enums.values(Color);

	pub fn fromTag(i: Tag) Color {
		return @enumFromInt(i);
	}

	pub fn tag(self: Color) Tag {
		return @intFromEnum(self);
	}

	pub fn char(self: Color) u8 {
		return char_array.getPtrConst(self).*;
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

	pub fn fromChar(c: u8) ?Color {
		inline for (values) |v| {
			if (c == v.char()) {
				return v;
			}
		}
		return null;
	}
};

pub const Piece = enum(std.meta.Int(.unsigned, Color.tag_info.bits + Ptype.tag_info.bits)) {
	w_pawn,
	b_pawn,

	w_knight,
	b_knight,

	w_bishop,
	b_bishop,

	w_rook,
	b_rook,

	w_queen,
	b_queen,

	w_king,
	b_king,

	none,

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

		.none = '.',
	});

	pub const Tag = std.meta.Tag(Piece);
	pub const tag_info = @typeInfo(Tag).int;

	pub const cnt: comptime_int = values.len - 1;
	pub const values = std.enums.values(Piece);

	pub const w_pieces = [_]Piece {
		.w_pawn,
		.w_knight,
		.w_bishop,
		.w_rook,
		.w_queen,
		.w_king,
	};

	pub const b_pieces = [_]Piece {
		.b_pawn,
		.b_knight,
		.b_bishop,
		.b_rook,
		.b_queen,
		.b_king,
	};

	pub fn init(c: Color, p: Ptype) Piece {
		const pi = @as(Tag, p.tag()) * Color.cnt;
		const ci = @as(Tag, c.tag());
		return fromTag(pi + ci);
	}

	pub fn tag(self: Piece) Tag {
		return @intFromEnum(self);
	}

	pub fn char(self: Piece) ?u8 {
		return char_map.get(self);
	}

	pub fn color(self: Piece) Color {
		const i = self.tag() % Color.cnt;
		return Color.fromTag(@truncate(i));
	}

	pub fn ptype(self: Piece) Ptype {
		const i = self.tag() / Color.cnt;
		return Ptype.fromTag(@truncate(i));
	}

	pub fn score(self: Piece) i16 {
		return if (self != .none) self.ptype().score() else 0;
	}

	pub fn fromChar(c: u8) ?Piece {
		for (values) |v| {
			const from_v = v.char() orelse continue;
			if (c == from_v) {
				return v;
			}
		}
		return null;
	}

	pub fn fromTag(i: Tag) Piece {
		return @enumFromInt(i);
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

	const Tag = std.meta.Tag(Rank);
	const tag_info = @typeInfo(Tag).int;

	const char_array = std.EnumArray(Rank, u8).init(.{
		.rank_1 = '1',
		.rank_2 = '2',
		.rank_3 = '3',
		.rank_4 = '4',
		.rank_5 = '5',
		.rank_6 = '6',
		.rank_7 = '7',
		.rank_8 = '8',
	});

	pub const cnt: comptime_int = values.len;
	pub const values = std.enums.values(Rank);

	fn fromTag(i: Tag) Rank {
		return @enumFromInt(i);
	}

	fn tag(self: Rank) Tag {
		return @intFromEnum(self);
	}

	pub fn char(self: Rank) u8 {
		return char_array.getPtrConst(self).*;
	}

	pub fn flip(self: Rank) Rank {
		const i = self.tag();
		const m = cnt - 1;
		return fromTag(i ^ m);
	}

	pub fn fromChar(c: u8) ?Rank {
		inline for (values) |v| {
			if (c == v.char()) {
				return v;
			}
		}
		return null;
	}

	pub fn toSet(self: Rank) Square.Set {
		return Square.Set.fromRank(self);
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

	const Tag = std.meta.Tag(File);
	const tag_info = @typeInfo(Tag).int;

	const char_array = std.EnumArray(File, u8).init(.{
		.file_a = 'a',
		.file_b = 'b',
		.file_c = 'c',
		.file_d = 'd',
		.file_e = 'e',
		.file_f = 'f',
		.file_g = 'g',
		.file_h = 'h',
	});

	pub const cnt: comptime_int = values.len;
	pub const values = std.enums.values(File);

	fn fromTag(i: Tag) File {
		return @enumFromInt(i);
	}

	fn tag(self: File) Tag {
		return @intFromEnum(self);
	}

	pub fn char(self: File) u8 {
		return char_array.getPtrConst(self).*;
	}

	pub fn flip(self: File) File {
		const i = self.tag();
		const m = cnt - 1;
		return fromTag(i ^ m);
	}

	pub fn fromChar(c: u8) ?File {
		inline for (values) |v| {
			if (c == v.char()) {
				return v;
			}
		}
		return null;
	}

	pub fn toSet(self: File) Square.Set {
		return Square.Set.fromFile(self);
	}
};

pub const Square = enum(std.meta.Int(.unsigned, Rank.tag_info.bits + File.tag_info.bits)) {
	a1, b1, c1, d1, e1, f1, g1, h1,
	a2, b2, c2, d2, e2, f2, g2, h2,
	a3, b3, c3, d3, e3, f3, g3, h3,
	a4, b4, c4, d4, e4, f4, g4, h4,
	a5, b5, c5, d5, e5, f5, g5, h5,
	a6, b6, c6, d6, e6, f6, g6, h6,
	a7, b7, c7, d7, e7, f7, g7, h7,
	a8, b8, c8, d8, e8, f8, g8, h8,

	const Tag = std.meta.Tag(Square);
	const tag_info = @typeInfo(Tag).int;

	pub const Set = SquareSet;

	pub const cnt: comptime_int = values.len;
	pub const values = std.enums.values(Square);

	fn fromTag(i: Tag) Square {
		return @enumFromInt(i);
	}

	pub fn init(r: Rank, f: File) Square {
		const ri = @as(Tag, r.tag()) * File.cnt;
		const fi = @as(Tag, f.tag());
		return fromTag(ri + fi);
	}

	pub fn tag(self: Square) Tag {
		return @intFromEnum(self);
	}

	pub fn rank(self: Square) Rank {
		const i = self.tag() / File.cnt;
		return Rank.fromTag(@truncate(i));
	}

	pub fn file(self: Square) File {
		const i = self.tag() % File.cnt;
		return File.fromTag(@truncate(i));
	}

	pub fn flipRank(self: Square) Square {
		return init(self.rank().flip(), self.file());
	}

	pub fn flipFile(self: Square) Square {
		return init(self.rank(), self.file().flip());
	}

	pub fn toSet(self: Square) Square.Set {
		return Square.Set.fromSquare(self);
	}

	pub fn okShift(self: Square, dir: Direction, amt: anytype) bool {
		return switch (dir) {
			.northnorthwest => self.okShift(.north, amt * 2) and self.okShift(.west, amt * 1),
			 .westnorthwest => self.okShift(.north, amt * 1) and self.okShift(.west, amt * 2),
			 .westsouthwest => self.okShift(.south, amt * 1) and self.okShift(.west, amt * 2),
			.southsouthwest => self.okShift(.south, amt * 2) and self.okShift(.west, amt * 1),
			.southsoutheast => self.okShift(.south, amt * 2) and self.okShift(.east, amt * 1),
			 .eastsoutheast => self.okShift(.south, amt * 1) and self.okShift(.east, amt * 2),
			 .eastnortheast => self.okShift(.north, amt * 1) and self.okShift(.east, amt * 2),
			.northnortheast => self.okShift(.north, amt * 2) and self.okShift(.east, amt * 1),

			.northwest => self.okShift(.north, amt) and self.okShift(.west, amt),
			.southwest => self.okShift(.south, amt) and self.okShift(.west, amt),
			.southeast => self.okShift(.south, amt) and self.okShift(.east, amt),
			.northeast => self.okShift(.north, amt) and self.okShift(.east, amt),

			.north, .south => vert: {
				const r: Direction.Tag = self.rank().tag();
				const d: Direction.Tag = std.math.sign(dir.tag());
				const a: Direction.Tag = @intCast(amt);

				const val = r + d * a;
				const min = std.math.minInt(Rank.Tag);
				const max = std.math.maxInt(Rank.Tag);

				break :vert val == std.math.clamp(val, min, max);
			},

			.west, .east => horz: {
				const f: Direction.Tag = self.file().tag();
				const d: Direction.Tag = std.math.sign(dir.tag());
				const a: Direction.Tag = @intCast(amt);

				const val = f + d * a;
				const min = std.math.minInt(File.Tag);
				const max = std.math.maxInt(File.Tag);

				break :horz val == std.math.clamp(val, min, max);
			},

			else => std.debug.panic("unexpected enum tag: @enumFromInt({d})", .{@intFromEnum(dir)}),
		};
	}

	pub fn shift(self: Square, dir: Direction, amt: anytype) Square {
		const s: Direction.Tag = self.tag();
		const d: Direction.Tag = dir.mul(amt).tag();
		return fromTag(@intCast(s + d));
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

	northnorthwest = 0 - down * 2 + left * 1,
	 westnorthwest = 0 - down * 1 + left * 2,
	 westsouthwest = 0 + down * 1 + left * 2,
	southsouthwest = 0 + down * 2 + left * 1,
	southsoutheast = 0 + down * 2 - left * 1,
	 eastsoutheast = 0 + down * 1 - left * 2,
	 eastnortheast = 0 - down * 1 - left * 2,
	northnortheast = 0 - down * 2 - left * 1,

	_,

	const Tag = std.meta.Tag(Direction);
	const tag_info = @typeInfo(Tag).int;

	const down
	  = @as(comptime_int, Square.a1.tag())
	  - @as(comptime_int, Square.a2.tag());

	const left
	  = @as(comptime_int, Square.a1.tag())
	  - @as(comptime_int, Square.b1.tag());

	pub fn tag(self: Direction) Tag {
		return @intFromEnum(self);
	}

	pub fn add(self: Direction, other: Direction) Direction {
		return @enumFromInt(self.tag() + other.tag());
	}

	pub fn mul(self: Direction, amt: anytype) Direction {
		const a: Tag = @intCast(amt);
		return @enumFromInt(self.tag() * a);
	}

	pub fn flip(self: Direction) Direction {
		return self.mul(-1);
	}
};

pub const Castle = enum(u2) {
	wk,
	wq,
	bk,
	bq,

	const Tag = std.meta.Tag(Castle);
	const tag_info = @typeInfo(Tag).int;

	const char_array = std.EnumArray(Castle, u8).init(.{
		.wk = 'K',
		.wq = 'Q',
		.bk = 'k',
		.bq = 'q',
	});

	pub const Set = CastleSet;

	pub const cnt: comptime_int = values.len;
	pub const values = std.enums.values(Castle);

	fn tag(self: Castle) Tag {
		return @intFromEnum(self);
	}

	pub fn char(self: Castle) u8 {
		return char_array.getPtrConst(self).*;
	}

	pub fn color(self: Castle) Color {
		return switch (self) {
			.wk, .wq => .white,
			.bk, .bq => .black,
		};
	}

	pub fn ptype(self: Castle) Ptype {
		return switch (self) {
			.wq, .bq => .queen,
			.wk, .bk => .king,
		};
	}

	pub fn fromChar(c: u8) ?Castle {
		for (values) |v| {
			const from_v = v.char();
			if (c == from_v) {
				return v;
			}
		}
		return null;
	}

	pub fn toSet(self: Castle) Set {
		return Set.fromCastle(self);
	}
};

pub fn SameMutPtr(comptime SrcPtr: type, comptime Expected: type, comptime Dst: type) type {
	const src_info = @typeInfo(SrcPtr).pointer;
	if (src_info.child != Expected) {
		const msg = std.fmt.comptimePrint("expected pointer to type {s}",
		  .{@typeName(Expected), @typeName(src_info.child)});
		@compileError(msg);
	}

	comptime var dst_info = @typeInfo(*Dst).pointer;
	dst_info.is_const = src_info.is_const;
	return @Type(.{.pointer = dst_info});
}

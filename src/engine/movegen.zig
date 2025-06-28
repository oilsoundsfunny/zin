const misc = @import("misc");
const std = @import("std");

pub const Move = packed struct(u16) {
	flag:	Flag,
	key:	Flag.Int,
	src:	misc.types.Square,
	dst:	misc.types.Square,

	pub const Flag = enum(u2) {
		nil,
		en_passant,
		promote,
		castle,

		pub const Int = std.meta.Tag(Flag);
	};
};

pub const Ordering = @import("types.zig").Ordering;

pub fn GenericPartialOrd(
    comptime Context: type,
    comptime cmpFn: *const fn (context: Context, other: Context) ?Ordering,
) type {
    return struct {
        const Self = @This();

        context: Context,

        pub inline fn cmp(self: Self, other: Context) ?Ordering {
            return cmpFn(self.context, other);
        }

        pub fn le(self: Self, other: Context) bool {
            if (self.cmp(other)) |ord| switch (ord) {
                .less, .equal => return true,
                else => return false,
            };

            return false;
        }
        pub fn lt(self: Self, other: Context) bool {
            if (self.cmp(other)) |ord| switch (ord) {
                .less => return true,
                else => return false,
            };

            return false;
        }
        pub fn ge(self: Self, other: Context) bool {
            if (self.cmp(other)) |ord| switch (ord) {
                .greater, .equal => return true,
                else => return false,
            };

            return false;
        }
        pub fn gt(self: Self, other: Context) bool {
            if (self.cmp(other)) |ord| switch (ord) {
                .greater => return true,
                else => return false,
            };

            return false;
        }
    };
}

pub fn GenericPartialEq(
    comptime Context: type,
    comptime eqFn: *const fn (context: Context, other: Context) bool,
) type {
    return struct {
        const Self = @This();

        context: Context,

        pub inline fn eq(self: Self, other: Context) bool {
            return eqFn(self.context, other);
        }

        pub fn ne(self: Self, other: Context) bool {
            return !self.eq(other);
        }
    };
}

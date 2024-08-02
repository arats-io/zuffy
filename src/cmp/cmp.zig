pub const Ordering = @import("types.zig").Ordering;

pub fn GenericComparator(
    comptime Context: type,
    comptime ComparatorError: type,
    comptime cmpFn: fn (context: Context, other: anytype) ?Ordering,
) type {
    return struct {
        const Self = @This();
        pub const Error = ComparatorError;

        context: Context,

        pub fn cmp(self: Self, other: anytype) ?Ordering {
            return self.cmpFn(self.ptr, other);
        }

        pub fn le(self: Self, other: anytype) bool {
            if (self.any().cmp(other)) |ord| switch (ord) {
                .less, .equal => return true,
                else => return false,
            };

            return false;
        }
        pub fn lt(self: Self, other: anytype) bool {
            if (self.any().cmp(other)) |ord| switch (ord) {
                .less => return true,
                else => return false,
            };

            return false;
        }
        pub fn ge(self: Self, other: anytype) bool {
            if (self.any().cmp(other)) |ord| switch (ord) {
                .greater, .equal => return true,
                else => return false,
            };

            return false;
        }
        pub fn gt(self: Self, other: anytype) bool {
            if (self.any().cmp(other)) |ord| switch (ord) {
                .greater => return true,
                else => return false,
            };

            return false;
        }

        pub inline fn any(self: *const Self) AnyComparator {
            return .{
                .context = @ptrCast(&self.context),
                .writeFn = typeErasedWriteFn,
            };
        }

        fn typeErasedWriteFn(context: *const anyopaque, other: anytype) ?Ordering {
            const ptr: *const Context = @alignCast(@ptrCast(context));
            return cmpFn(ptr.*, other);
        }
    };
}

pub const Comparator = GenericComparator;

pub const AnyComparator = @import("comparator.zig");

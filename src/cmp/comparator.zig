const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;

const Ordering = @import("types.zig").Ordering;

context: *const anyopaque,
cmpFn: fn (context: *const anyopaque, other: anytype) ?Ordering,

const Self = @This();
pub const Error = anyerror;

pub fn cmp(self: Self, other: anytype) ?Ordering {
    return self.cmpFn(self.context, other);
}

pub fn le(self: Self, other: anytype) bool {
    if (self.cmp(other)) |ord| switch (ord) {
        .less, .equal => return true,
        else => return false,
    };

    return false;
}
pub fn lt(self: Self, other: anytype) bool {
    if (self.cmp(other)) |ord| switch (ord) {
        .less => return true,
        else => return false,
    };

    return false;
}
pub fn ge(self: Self, other: anytype) bool {
    if (self.cmp(other)) |ord| switch (ord) {
        .greater, .equal => return true,
        else => return false,
    };

    return false;
}
pub fn gt(self: Self, other: anytype) bool {
    if (self.cmp(other)) |ord| switch (ord) {
        .greater => return true,
        else => return false,
    };

    return false;
}

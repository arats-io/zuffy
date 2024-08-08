const std = @import("std");
const Ordering = @import("types.zig").Ordering;
const GenericPartialOrd = @import("partial.zig").GenericPartialOrd;

pub fn Wrapper(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const PartialOrd = GenericPartialOrd(*const Self, partial_cmp);

        value: T,

        pub fn fromLiteral(v: T) Self {
            return Self{ .value = v };
        }

        fn partial_cmp(self: *const Self, other: *const Self) ?Ordering {
            if (self.value > other.value) return .greater;
            if (self.value < other.value) return .less;
            if (self.value == other.value) return .equal;
            return null;
        }

        pub fn cmper(self: *const Self) PartialOrd {
            return .{ .context = self };
        }
    };
}

pub fn WrapperArray(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const PartialOrd = GenericPartialOrd(*const Self, partial_cmp);

        value: []const T,

        pub fn fromLiteral(v: []const T) Self {
            return Self{ .value = v };
        }

        fn partial_cmp(self: *const Self, other: *const Self) ?Ordering {
            if (self.value.len > other.value.len) return .greater;
            if (self.value.len < other.value.len) return .less;

            if (std.mem.eql(T, self.value, other.value)) return .equal;

            return null;
        }

        pub fn cmper(self: *const Self) PartialOrd {
            return .{ .context = self };
        }
    };
}

const std = @import("std");
const builtin = @import("builtin");
const CircularLifoList = @import("list/mod.zig").circular.Lifo;

pub const PoolError = error{
    NoCapacity,
};

pub fn Pool(comptime T: type) type {
    const threadsafe: bool = !builtin.single_threaded;

    return struct {
        const Self = @This();

        create: *const fn (allocator: std.mem.Allocator) T,

        allocator: std.mem.Allocator,

        mu: std.Thread.Mutex = std.Thread.Mutex{},
        queue: CircularLifoList(usize),

        counter: usize = 0,

        pub fn initWithCapacity(allocator: std.mem.Allocator, createFn: *const fn (allocator: std.mem.Allocator) T, cap: usize) !Self {
            const cl = try CircularLifoList(usize).init(allocator, cap);
            return Self{ .allocator = allocator, .queue = cl, .create = createFn };
        }

        pub fn init(allocator: std.mem.Allocator, createFn: *const fn (allocator: std.mem.Allocator) T) !Self {
            return initWithCapacity(allocator, createFn, std.math.maxInt(u16));
        }

        pub fn deinit(self: *const Self) void {
            @constCast(self).queue.deinit();
        }

        pub fn pop(self: *const Self) T {
            if (threadsafe) {
                @constCast(self).mu.lock();
                defer @constCast(self).mu.unlock();
            }

            if (@constCast(self).queue.pop()) |n| {
                _ = @atomicRmw(usize, &@constCast(self).counter, .Sub, 1, .monotonic);

                const data = @as(*T, @ptrFromInt(n)).*;
                return data;
            }

            return self.create(self.allocator);
        }

        pub fn push(self: *const Self, data: *const T) !void {
            if (threadsafe) {
                @constCast(self).mu.lock();
                defer @constCast(self).mu.unlock();
            }

            if (self.counter == self.queue.cap) {
                return PoolError.NoCapacity;
            }
            _ = @atomicRmw(usize, &@constCast(self).counter, .Add, 1, .monotonic);
            _ = @constCast(self).queue.push(@as(usize, @intFromPtr(data)));
        }
    };
}

const assert = std.debug.assert;

test "Pool Usage" {
    const StringBuilder = @import("bytes/mod.zig").StringBuilder;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const NewUtf8Buffer = struct {
        fn f(allocator: std.mem.Allocator) StringBuilder {
            return StringBuilder.init(allocator);
        }
    }.f;

    var utf8BufferPool = try Pool(StringBuilder).init(arena.allocator(), NewUtf8Buffer);
    defer utf8BufferPool.deinit();

    {
        var sb10 = utf8BufferPool.pop();
        assert(sb10.rawLength() == 0);

        try sb10.append("💯Hello💯");
        assert(sb10.compare("💯Hello💯"));

        try utf8BufferPool.push(&sb10);
    }

    var sb11 = utf8BufferPool.pop();
    assert(sb11.compare("💯Hello💯"));

    var sb21 = utf8BufferPool.pop();
    try sb21.append("💯Hello2💯");
    assert(sb21.compare("💯Hello2💯"));

    try utf8BufferPool.push(&sb21);
    try utf8BufferPool.push(&sb11);

    assert(utf8BufferPool.counter == 2);

    {
        var sb12 = utf8BufferPool.pop();
        assert(sb12.compare("💯Hello💯"));
    }

    assert(utf8BufferPool.counter == 1);

    {
        var sb22 = utf8BufferPool.pop();
        assert(sb22.compare("💯Hello2💯"));
    }

    assert(utf8BufferPool.counter == 0);
}

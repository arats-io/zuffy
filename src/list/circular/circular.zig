const std = @import("std");
const builtin = @import("builtin");

const debug = std.debug;
const assert = debug.assert;
const mem = std.mem;
const math = std.math;
const Allocator = mem.Allocator;

pub const Error = error{
    CapacityLessThenCurrrent,
};

pub const Type = enum(u2) {
    FIFO = 0,
    LIFO,
};

pub fn CircularLifoList(comptime T: type) type {
    return CircularList(T, .LIFO);
}

pub fn CircularFifoList(comptime T: type) type {
    return CircularList(T, .FIFO);
}

pub fn CircularList(comptime T: type, comptime LType: Type) type {
    return CircularListAligned(T, !builtin.single_threaded, LType, null);
}

pub fn CircularListAligned(comptime T: type, comptime threadsafe: bool, comptime LType: Type, comptime alignment: ?u29) type {
    if (alignment) |a| {
        if (a == @alignOf(T)) {
            return CircularListAligned(T, threadsafe, LType, null);
        }
    }
    return struct {
        const Self = @This();

        const Slice = if (alignment) |a| ([]align(a) T) else []T;

        mu: std.Thread.Mutex = std.Thread.Mutex{},
        items: Slice,

        tail: usize,
        head: usize,
        cap: usize,
        len: usize,

        allocator: Allocator,

        pub fn init(allocator: Allocator, cap: usize) !Self {
            return Self{
                .items = try allocator.alignedAlloc(T, alignment, cap),
                .tail = 0,
                .head = 0,
                .cap = cap,
                .len = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.items.ptr[0..self.cap]);
        }

        pub fn isFull(self: Self) bool {
            return self.len == self.cap;
        }

        pub fn resize(self: *Self, cap: usize) !void {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            if (cap < self.cap) {
                return Error.CapacityLessThenCurrrent;
            }

            var new = Self{
                .items = try self.allocator.alignedAlloc(T, alignment, cap),
                .tail = 0,
                .head = 0,
                .cap = cap,
                .len = 0,
                .allocator = self.allocator,
            };

            while (self.pop()) |x| {
                _ = new.push(x);
            }

            self.deinit();

            self.items = new.items;
            @atomicStore(usize, &self.tail, new.tail, .monotonic);
            @atomicStore(usize, &self.head, new.head, .monotonic);
            @atomicStore(usize, &self.cap, new.cap, .monotonic);
            @atomicStore(usize, &self.len, new.len, .monotonic);
        }

        pub fn push(self: *Self, item: T) T {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            return switch (LType) {
                .LIFO => self.pushLifo(item),
                .FIFO => self.pushFifo(item),
            };
        }

        fn pushLifo(self: *Self, item: T) T {
            const previous: T = self.items[self.tail];

            self.items[self.tail] = item;

            const idx = (self.tail + 1) % self.cap;
            @atomicStore(usize, &self.tail, idx, .monotonic);

            if (self.len < self.cap) {
                @atomicStore(usize, &self.len, self.len + 1, .monotonic);
            }

            return previous;
        }

        fn pushFifo(self: *Self, item: T) T {
            if (self.len == self.cap and self.tail == self.tail) {
                @atomicStore(usize, &self.head, self.head + 1, .monotonic);
                if (self.head == self.cap) {
                    @atomicStore(usize, &self.head, 0, .monotonic);
                }
            }

            return self.pushLifo(item);
        }

        pub fn pop(self: *Self) ?T {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            if (self.len == 0) {
                return null;
            }

            return switch (LType) {
                .LIFO => self.popLifo(),
                .FIFO => self.popFifo(),
            };
        }

        fn popLifo(self: *Self) T {
            var idx = self.head;
            var ptr = &self.head;
            if (idx == 0 and self.tail > 0) {
                idx = self.tail;
                ptr = &self.tail;
            } else if (idx == 0 and self.cap > 0) {
                idx = self.cap;
                ptr = &self.tail;
            }

            idx = (idx - 1) % self.cap;
            @atomicStore(usize, ptr, idx, .monotonic);
            @atomicStore(usize, &self.len, self.len - 1, .monotonic);

            if (self.len == 0) {
                @atomicStore(usize, &self.tail, 0, .monotonic);
                @atomicStore(usize, &self.head, 0, .monotonic);
            }
            return self.items[idx];
        }

        fn popFifo(self: *Self) T {
            var idx = self.head;

            const res = self.items[idx];
            idx = (idx + 1) % self.cap;
            @atomicStore(usize, &self.head, idx, .monotonic);
            @atomicStore(usize, &self.len, self.len - 1, .monotonic);

            if (self.len == 0) {
                @atomicStore(usize, &self.tail, 0, .monotonic);
                @atomicStore(usize, &self.head, 0, .monotonic);
            }

            return res;
        }

        pub fn read(self: Self, pos: usize) ?T {
            if (pos >= self.items.len or pos >= self.cap) {
                return null;
            }

            return self.items[pos];
        }
    };
}

const testing = std.testing;

test "fifo/push 1 element" {
    var cl = try CircularFifoList(i32).init(testing.allocator, 5);
    defer cl.deinit();

    try testing.expectEqual(cl.len, 0);

    _ = cl.push(34);

    try testing.expectEqual(cl.len, 1);

    if (cl.pop()) |x| {
        try testing.expectEqual(x, 34);
    }

    try testing.expectEqual(cl.len, 0);
}

test "fifo/push 5 elements" {
    var cl = try CircularFifoList(i32).init(testing.allocator, 5);
    defer cl.deinit();

    try testing.expectEqual(cl.len, 0);

    _ = cl.push(1);
    _ = cl.push(2);
    _ = cl.push(3);
    _ = cl.push(4);
    _ = cl.push(5);

    try testing.expectEqual(cl.len, 5);

    for (1..6) |i| {
        if (cl.pop()) |x| {
            try testing.expectEqual(x, @as(i32, @intCast(i)));
        }
    }

    try testing.expectEqual(cl.len, 0);
}

test "fifo/push 6 elements" {
    var cl = try CircularFifoList(i32).init(testing.allocator, 5);
    defer cl.deinit();

    try testing.expectEqual(cl.len, 0);

    _ = cl.push(1);
    _ = cl.push(2);
    _ = cl.push(3);
    _ = cl.push(4);
    _ = cl.push(5);
    _ = cl.push(6);

    try testing.expectEqual(cl.len, 5);

    for (2..7) |i| {
        if (cl.pop()) |x| {
            try testing.expectEqual(x, @as(i32, @intCast(i)));
        }
    }

    try testing.expectEqual(cl.len, 0);
}

test "lifo/push 1 element" {
    var cl = try CircularLifoList(i32).init(testing.allocator, 5);
    defer cl.deinit();

    try testing.expectEqual(cl.len, 0);

    _ = cl.push(34);

    try testing.expectEqual(cl.len, 1);

    if (cl.pop()) |x| {
        try testing.expectEqual(x, 34);
    }

    try testing.expectEqual(cl.len, 0);
}

test "lifo/push 5 elements" {
    var cl = try CircularLifoList(i32).init(testing.allocator, 5);
    defer cl.deinit();

    try testing.expectEqual(cl.len, 0);

    _ = cl.push(5);
    _ = cl.push(4);
    _ = cl.push(3);
    _ = cl.push(2);
    _ = cl.push(1);

    try testing.expectEqual(cl.len, 5);

    for (1..6) |i| {
        if (cl.pop()) |x| {
            try testing.expectEqual(x, @as(i32, @intCast(i)));
        }
    }

    try testing.expectEqual(cl.len, 0);
}

test "lifo/push 6 elements" {
    var cl = try CircularLifoList(i32).init(testing.allocator, 5);
    defer cl.deinit();

    try testing.expectEqual(cl.len, 0);

    _ = cl.push(6);
    _ = cl.push(5);
    _ = cl.push(4);
    _ = cl.push(3);
    _ = cl.push(2);
    _ = cl.push(1);

    try testing.expectEqual(cl.len, 5);

    for (1..6) |i| {
        if (cl.pop()) |x| {
            try testing.expectEqual(x, @as(i32, @intCast(i)));
        }
    }

    try testing.expectEqual(cl.len, 0);
}

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
            return Self{ .allocator = allocator, .queue = try CircularLifoList(usize).init(allocator, cap), .create = createFn };
        }

        pub fn init(allocator: std.mem.Allocator, createFn: *const fn (allocator: std.mem.Allocator) T) !Self {
            return initWithCapacity(allocator, createFn, std.math.maxInt(u16));
        }

        pub fn deinit(self: Self) void {
            self.queue.deinit();
        }

        pub fn pop(self: *Self) !T {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            if (self.queue.pop()) |n| {
                _ = @atomicRmw(usize, &self.counter, .Sub, 1, .Monotonic);

                return @as(*T, @ptrFromInt(n)).*;
            }

            return self.create(self.allocator);
        }

        pub fn push(self: *Self, data: *const T) !void {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            if (self.counter == self.queue.cap) {
                return PoolError.NoCapacity;
            }
            _ = @atomicRmw(usize, &self.counter, .Add, 1, .Monotonic);
            _ = self.queue.push(@as(usize, @intFromPtr(data)));
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
        var sb10 = try utf8BufferPool.pop();
        assert(sb10.rawLength() == 0);

        try sb10.append("💯Hello💯");
        assert(sb10.compare("💯Hello💯"));

        try utf8BufferPool.push(&sb10);
    }

    var sb11 = try utf8BufferPool.pop();
    assert(sb11.compare("💯Hello💯"));

    var sb21 = try utf8BufferPool.pop();
    try sb21.append("💯Hello2💯");
    assert(sb21.compare("💯Hello2💯"));

    try utf8BufferPool.push(&sb21);
    try utf8BufferPool.push(&sb11);

    assert(utf8BufferPool.counter == 2);

    {
        var sb12 = try utf8BufferPool.pop();
        assert(sb12.compare("💯Hello💯"));
    }

    assert(utf8BufferPool.counter == 1);

    {
        var sb22 = try utf8BufferPool.pop();
        assert(sb22.compare("💯Hello2💯"));
    }

    assert(utf8BufferPool.counter == 0);
}

// const std = @import("std");
// const debug = std.debug;
// const assert = debug.assert;
// const math = std.math;
// const mem = std.mem;
// const Allocator = mem.Allocator;
// const AllocatorError = mem.Allocator.Error;

// const Error = @import("xstd/bytes/buffer.zig").Error;
// const Utf8BufferPool = @import("xstd/bytes/utf8_buffer.zig").Utf8BufferPool;
// const Utf8Buffer = @import("xstd/bytes/utf8_buffer.zig").Utf8Buffer;

// const Pool = @import("xstd/pool.zig").Pool;

// pub fn NewUtf8Buffer(allocator: std.mem.Allocator) Utf8Buffer {
//     return Utf8Buffer.init(allocator);
// }

// pub fn PrintElement(ch: []const u8) void {
//     std.debug.print("{s}", .{ch});
// }

// pub fn main() !void {
//     std.debug.print("Starting application.\n", .{});

//     var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     defer arena.deinit();

//     const allocator = arena.allocator();

//     // var utf8BufferPool = Utf8BufferPool(true).init(allocator);
//     // var sb = try utf8BufferPool.pop();
//     // defer sb.deinit();

//     var utf8BufferPool = try Pool(Utf8Buffer).init(allocator, NewUtf8Buffer);
//     var sb = try utf8BufferPool.pop();

//     try sb.append("SB------");
//     try sb.append("A");
//     try sb.append("\u{5360}");
//     try sb.append("💯");
//     try sb.append("Hell");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

//     try sb.appendf("🔥 Hello {s} World 🔥", .{"Ionel"});
//     std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

//     _ = try sb.replaceFirst("💯", "+++++💯+++++");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });
//     _ = try sb.replaceFirst("+++++💯+++++", "💯");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });
//     _ = try sb.replaceFirst("💯", "");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

//     try sb.insertAt("🔥", 1);
//     std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

//     _ = try sb.replaceLast("🔥", "§");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

//     _ = try sb.removeAll("🔥");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

//     try utf8BufferPool.push(&sb);

//     var sb10 = try utf8BufferPool.pop();
//     try sb10.append("-Second Round SB");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb10.bytes(), @intFromPtr(&sb10) });

//     var sb2 = try utf8BufferPool.pop();
//     try sb2.append("SB2------");
//     try sb2.append("💯");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb2.bytes(), @intFromPtr(&sb2) });

//     try utf8BufferPool.push(&sb10);
//     try utf8BufferPool.push(&sb2);

//     var sb21 = try utf8BufferPool.pop();
//     try sb21.append("Finally");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb21.bytes(), @intFromPtr(&sb21) });

//     var sb11 = try utf8BufferPool.pop();
//     try sb11.append("Finally");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb11.bytes(), @intFromPtr(&sb11) });

//     try utf8BufferPool.push(&sb11);
//     try utf8BufferPool.push(&sb21);

//     var sb12 = try utf8BufferPool.pop();
//     try sb12.append("Finally2");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb12.bytes(), @intFromPtr(&sb12) });

//     var sb22 = try utf8BufferPool.pop();
//     try sb22.append("Finally2");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb22.bytes(), @intFromPtr(&sb22) });

//     var sb3 = try utf8BufferPool.pop();
//     try sb3.append("SB3------");
//     try sb3.append("New Finally");
//     std.debug.print("[{s}] --- from {any}\n", .{ sb3.bytes(), @intFromPtr(&sb3) });

//     try utf8BufferPool.push(&sb12);
//     try utf8BufferPool.push(&sb22);
//     try utf8BufferPool.push(&sb3);
//     try utf8BufferPool.push(&sb3);

//     std.debug.print("=============================\n", .{});
//     var sb31 = try utf8BufferPool.pop();
//     std.debug.print("[{s}] --- from {any}\n", .{ sb31.bytes(), @intFromPtr(&sb31) });
//     var sb32 = try utf8BufferPool.pop();
//     std.debug.print("[{s}] --- from {any}\n", .{ sb32.bytes(), @intFromPtr(&sb32) });
//     var sb23 = try utf8BufferPool.pop();
//     std.debug.print("[{s}] --- from {any}\n", .{ sb23.bytes(), @intFromPtr(&sb23) });

//     var sb24 = try utf8BufferPool.pop();
//     std.debug.print("[{s}] --- from {any}\n", .{ sb24.bytes(), @intFromPtr(&sb24) });

//     var sb4 = try utf8BufferPool.pop();
//     std.debug.print("--- [{s}] --- from {any}\n", .{ sb4.bytes(), @intFromPtr(&sb4) });
// }

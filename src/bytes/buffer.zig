const std = @import("std");
const builtin = @import("builtin");

const Stack = std.atomic.Stack;

const assert = std.debug.assert;

pub const Error = error{
    OutOfMemory,
    InvalidRange,
};

pub fn BufferPool(comptime threadsafe: bool) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        queue: Stack(Buffer(threadsafe)),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{ .queue = Stack(Buffer(threadsafe)).init(), .allocator = allocator };
        }

        pub fn pop(self: *Self) !Buffer(threadsafe) {
            if (self.queue.pop()) |n| {
                return n.data;
            }

            return try Buffer(threadsafe).init(self.allocator);
        }

        pub fn push(self: *Self, data: Buffer(threadsafe)) void {
            var n = Stack(Buffer(threadsafe)).Node{
                .data = data,
                .next = null,
            };
            self.queue.push(&n);
        }
    };
}

pub const Buffer = BufferManaged(!builtin.single_threaded);

pub fn BufferManaged(comptime threadsafe: bool) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        mu: std.Thread.Mutex = std.Thread.Mutex{},

        ptr: [*]u8,

        cap: usize = 0,
        len: usize = 0,
        factor: u4,

        pub fn initWithFactor(allocator: std.mem.Allocator, factor: u4) Self {
            return Self{
                .ptr = @as([*]u8, @ptrFromInt(0xFF)),
                .allocator = allocator,
                .cap = 0,
                .len = 0,
                .factor = if (factor <= 0) 1 else factor,
            };
        }

        pub fn init(allocator: std.mem.Allocator) Self {
            return initWithFactor(allocator, 1);
        }

        pub fn deinit(self: *Self) void {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            self.allocator.free(self.ptr[0..self.cap]);
        }

        pub fn resize(self: *Self, cap: usize) !void {
            const l = self.len;

            var slice = try self.allocator.alloc(u8, cap);

            _copy(u8, slice, self.ptr[0..l]);
            self.allocator.free(self.ptr[0..self.cap]);

            self.ptr = slice.ptr;
            self.cap = cap;
        }

        pub fn shrink(self: *Self) !void {
            try self.resize(self.len);
        }

        pub fn write(self: *Self, array: []const u8) !usize {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            if (self.len + array.len > self.cap) {
                try self.resize((self.len + array.len) * self.factor);
            }

            var i: usize = 0;
            while (i < array.len) : (i += 1) {
                self.ptr[self.len + i] = array[i];
            }

            self.len += array.len;

            return array.len;
        }

        fn read(self: *Self, dst: []u8) !usize {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            var size = if (self.len < dst.len) self.len else dst.len;
            _copy(u8, dst, self.ptr[0..size]);
            return size;
        }

        pub fn compare(self: *Self, array: []const u8) bool {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            return std.mem.eql(u8, self.ptr[0..self.len], array.ptr[0..array.len]);
        }

        pub fn bytes(self: *Self) []const u8 {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            return self.ptr[0..self.len];
        }

        pub fn byteAt(self: *Self, index: usize) ?u8 {
            if (threadsafe) {
                self.buffer.mu.lock();
                defer self.buffer.mu.unlock();
            }

            if (index < self.len) {
                return self.buffer.ptr[index];
            }
            return null;
        }

        pub fn rangeBytes(self: *Self, start: usize, end: usize) ?u8 {
            if (threadsafe) {
                self.buffer.mu.lock();
                defer self.buffer.mu.unlock();
            }

            if (start < self.len and end < self.len and start < end) {
                return self.buffer.ptr[start..end];
            }
            return null;
        }

        pub fn clone(self: *Self) !Self {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            return self.cloneUsingAllocator(self.allocator);
        }

        pub fn cloneUsingAllocator(self: *Self, allocator: std.mem.Allocator) !Self {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            var buf = init(allocator);
            _ = try buf.write(self.ptr[0..self.len]);
            return buf;
        }

        pub fn copy(self: *Self) ![]u8 {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            return self.copyUsingAllocator(self.allocator);
        }

        pub fn copyUsingAllocator(self: *Self, allocator: std.mem.Allocator) ![]u8 {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            const s = self.bytes();
            if (allocator.alloc(u8, s.len)) |newStr| {
                std.mem.copy(u8, newStr, s);
                return newStr;
            } else |_| {
                return Error.OutOfMemory;
            }
        }

        pub fn repeat(self: *Self, n: usize) !void {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            try self.resize(self.cap * (n + 1));

            var i: usize = 1;
            while (i <= n) : (i += 1) {
                var j: usize = 0;
                while (j < self.len) : (j += 1) {
                    self.ptr[((i * self.len) + j)] = self.ptr[j];
                }
            }

            self.len *= (n + 1);
        }

        pub fn isEmpty(self: *Self) bool {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            return self.len == 0;
        }

        pub fn clear(self: *Self) void {
            if (threadsafe) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            for (0..self.len) |i| {
                self.ptr[i] = 0;
            }
            self.len = 0;
        }

        fn _copy(comptime Type: type, dest: []Type, src: []const Type) void {
            assert(dest.len >= src.len);

            if (@intFromPtr(src.ptr) == @intFromPtr(dest.ptr) or src.len == 0) return;

            const input: []const u8 = std.mem.sliceAsBytes(src);
            const output: []u8 = std.mem.sliceAsBytes(dest);

            assert(input.len > 0);
            assert(output.len > 0);

            const is_input_or_output_overlaping = (@intFromPtr(input.ptr) < @intFromPtr(output.ptr) and
                @intFromPtr(input.ptr) + input.len > @intFromPtr(output.ptr)) or
                (@intFromPtr(output.ptr) < @intFromPtr(input.ptr) and
                @intFromPtr(output.ptr) + output.len > @intFromPtr(input.ptr));

            if (is_input_or_output_overlaping) {
                @memcpy(output, input);
            } else {
                std.mem.copyBackwards(u8, output, input);
            }
        }

        // Reader and Writer functionality.
        pub usingnamespace struct {
            pub const Writer = std.io.Writer(*Self, Error, appendWrite);
            pub const Reader = std.io.Reader(*Self, Error, readFn);

            pub fn reader(self: *Self) Reader {
                return .{ .context = self };
            }

            fn readFn(self: *Self, m: []u8) !usize {
                return try self.read(m);
            }

            pub fn writer(self: *Self) Writer {
                return .{ .context = self };
            }

            fn appendWrite(self: *Self, m: []const u8) !usize {
                return try self.write(m);
            }
        };
    };
}

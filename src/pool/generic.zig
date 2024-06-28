const std = @import("std");
const builtin = @import("builtin");
const CircularLifoList = @import("../list/circular.zig").CircularLifoList;

pub fn Generic(comptime T: type) type {
    const threadsafe: bool = !builtin.single_threaded;

    return struct {
        const Self = @This();

        create: *const fn (allocator: std.mem.Allocator) T,

        allocator: std.mem.Allocator,

        mu: std.Thread.Mutex = std.Thread.Mutex{},
        queue: CircularLifoList(usize),

        pub fn init(allocator: std.mem.Allocator, createFn: *const fn (allocator: std.mem.Allocator) T) Self {
            return initWithCapacity(allocator, createFn, 5);
        }
        pub fn initWithCapacity(allocator: std.mem.Allocator, createFn: *const fn (allocator: std.mem.Allocator) T, cap: usize) Self {
            const cl = CircularLifoList(usize).init(allocator, cap, .{ .mode = .flexible });
            return Self{ .allocator = allocator, .queue = cl, .create = createFn };
        }

        pub fn initFixed(allocator: std.mem.Allocator, createFn: *const fn (allocator: std.mem.Allocator) T) Self {
            return initWithCapacityFixed(allocator, createFn, 5);
        }

        pub fn initWithCapacityFixed(allocator: std.mem.Allocator, createFn: *const fn (allocator: std.mem.Allocator) T, cap: usize) Self {
            const cl = CircularLifoList(usize).init(allocator, cap, .{ .mode = .fixed });
            return Self{ .allocator = allocator, .queue = cl, .create = createFn };
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

            _ = @constCast(self).queue.push(@as(usize, @intFromPtr(data)));
        }
    };
}

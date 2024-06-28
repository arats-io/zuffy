const std = @import("std");
const xstd = @import("xstd");

pub fn main() !void {
    std.debug.print("Start application \n", .{});

    const PoolLockAllocationFree = xstd.pool.LockAllocationFree(u32);

    var list = PoolLockAllocationFree.init();
    defer list.deinit();

    var t1 = PoolLockAllocationFree.Entry{ .value = 1 };
    list.push(PoolLockAllocationFree.Batch.from(&t1));
    std.debug.print("Push - {any}\n", .{t1.value});

    list.registerCurrentThread();
    std.debug.print("Registered Thread\n", .{});

    var t2 = PoolLockAllocationFree.Entry{ .value = 2 };
    list.push(PoolLockAllocationFree.Batch.from(&t2));
    std.debug.print("Push - {any}\n", .{t2.value});

    var t3 = PoolLockAllocationFree.Entry{ .value = 3 };
    list.push(PoolLockAllocationFree.Batch.from(&t3));
    std.debug.print("Push - {any}\n", .{t3.value});

    if (list.pop()) |entry| {
        std.debug.print("Pop - {any}\n", .{entry.value});
    }

    list.unregisterCurrentThread();
    std.debug.print("UnRegistered Thread\n", .{});

    while (list.pop()) |entry| {
        std.debug.print("Pop - {any}\n", .{entry.value});
    }

    std.debug.print("End application \n", .{});
}

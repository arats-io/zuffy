const std = @import("std");
const xstd = @import("xstd");

const math = std.math;
const Allocator = std.mem.Allocator;

const SkipList = xstd.list.SkipList;

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var list = try SkipList(f128, usize).init(allocator);

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
    const random = prng.random();

    const total = std.math.maxInt(u4);

    var keys = std.ArrayList(f64).init(allocator);
    defer keys.deinit();

    for (0..total) |v| {
        const key = random.float(f64);
        try keys.append(key);

        const startTime = std.time.nanoTimestamp();
        _ = try list.Insert(key, v);
        const endTime = (std.time.nanoTimestamp() - startTime);
        std.debug.print("Inserting value {}:{}, took {} millisec \n", .{ v, key, @divTrunc(endTime, 1000) });
    }

    for (keys.items) |key| {
        if (list.Get(key)) |v| {
            std.debug.print("Got - {}:{}\n", .{ v, key });
        }

        const startTime = std.time.nanoTimestamp();
        const v = try list.Remove(key);
        const endTime = (std.time.nanoTimestamp() - startTime);
        std.debug.print("Removed - {}:{}, took {} millisec \n", .{ v.?, key, @divTrunc(endTime, 1000) });
    }

    std.debug.print("=============================== \n", .{});

    for (keys.items) |key| {
        if (list.Get(key)) |v| {
            std.debug.print("Should not be there; Got - {}:{}\n", .{ v, key });
        }

        if (try list.Remove(key)) |v| {
            std.debug.print("Should not be there; Removed - {}:{}\n", .{ v, key });
        }
    }

    std.debug.print("Finished removing data \n", .{});
}

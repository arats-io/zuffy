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

    var list = try SkipList(f128, usize).init(allocator, .{});
    defer list.deinit();

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
    const random = prng.random();

    const total = std.math.maxInt(u4);

    var keys = std.ArrayList(f64).init(allocator);
    defer keys.deinit();

    list.Print();

    for (0..total) |v| {
        const key = random.float(f64);
        try keys.append(key);

        const startTime = std.time.nanoTimestamp();
        _ = try list.Insert(key, v);
        _ = try list.Insert(key, v + 100);
        const endTime = (std.time.nanoTimestamp() - startTime);
        std.debug.print("Inserting value {}:{}, took {} millisec \n", .{ v, key, @divTrunc(endTime, 1000) });
    }

    for (keys.items) |key| {
        const startTime = std.time.nanoTimestamp();
        const v = list.Remove(key);
        const endTime = (std.time.nanoTimestamp() - startTime);
        std.debug.print("Removed - {}:{}, took {} millisec \n", .{ v.?, key, @divTrunc(endTime, 1000) });
    }

    std.debug.print("Size {} \n", .{list.size(.bytes)});

    list.Print();

    std.debug.print("=============================== \n", .{});

    for (keys.items) |key| {
        if (list.Get(key)) |v| {
            std.debug.print("Should not be there; Got - {}:{}\n", .{ v, key });
        }

        if (list.Remove(key)) |v| {
            std.debug.print("Should not be there; Removed - {}:{}\n", .{ v, key });
        }
    }

    list.deinit();

    std.debug.print("Finished removing data \n", .{});

    std.time.sleep(@as(u64, 1 * 60 * 60) * std.time.ns_per_s);
}

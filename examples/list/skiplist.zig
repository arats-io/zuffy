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

    var list = try SkipList(f128, usize).init(allocator, .{
        .allow_multiple_values_same_key = true,
    });
    defer list.deinit();

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
    const random = prng.random();

    const total = std.math.maxInt(u4);

    const handler = struct {
        pub fn f(key: f128, value: usize) void {
            std.debug.print("{}:{} \n", .{ value, key });
        }
    }.f;

    var keys = std.ArrayList(f64).init(allocator);
    defer keys.deinit();

    for (0..total) |v| {
        const key = random.float(f64);
        try keys.append(key);

        const startTime = std.time.nanoTimestamp();
        _ = try list.insert(key, v);
        _ = try list.insert(key, v + 100);
        const endTime = (std.time.nanoTimestamp() - startTime);
        std.debug.print("Inserting value {}:{}, took {} millisec \n", .{ v, key, @divTrunc(endTime, 1000) });
    }

    for (keys.items) |key| {
        const startTime = std.time.nanoTimestamp();
        const v = list.remove(key);
        const endTime = (std.time.nanoTimestamp() - startTime);
        std.debug.print("Removed - {}:{}, took {} millisec \n", .{ v.?, key, @divTrunc(endTime, 1000) });
    }

    std.debug.print("Size {} \n", .{list.contentSize(.bytes)});

    std.debug.print("=======================================================================\n", .{});
    list.forEach(handler);
    std.debug.print("=======================================================================\n", .{});

    for (keys.items) |key| {
        if (list.get(key)) |v| {
            std.debug.print("Should not be there; Got - {}:{}\n", .{ v, key });
        }

        if (list.remove(key)) |v| {
            std.debug.print("Should not be there; Removed - {}:{}\n", .{ v, key });
        }
    }

    std.debug.print("Finished removing data \n", .{});

    //std.time.sleep(@as(u64, 1 * 60 * 60) * std.time.ns_per_s);
}

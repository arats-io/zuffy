const std = @import("std");
const xstd = @import("xstd");

const math = std.math;
const Allocator = std.mem.Allocator;

const SkipList = xstd.list.SkipList;
const Skip = xstd.list.Skip;

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
    const random = prng.random();

    const total = std.math.maxInt(u4);

    const F64 = xstd.cmp.Wrapper(f64);

    const handler = struct {
        pub fn f(key: F64, value: usize) void {
            std.debug.print("{}:{} \n", .{ value, key.value });
        }
    }.f;

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    for (0..1000000000000) |_| {
        var list = try SkipList(F64, usize).init(allocator, .{});
        defer list.deinit();

        var keys = std.ArrayList(F64).init(allocator);
        errdefer keys.deinit();
        defer keys.deinit();

        for (0..total) |v| {
            const key = F64.fromLiteral(random.float(f64));
            try keys.append(key);

            // const startTime = std.time.nanoTimestamp();
            _ = try list.insert(key, v);
            // const endTime = (std.time.nanoTimestamp() - startTime);
            // std.debug.print("Inserting value {}:{}, took {} millisec \n", .{ v, key, @divTrunc(endTime, 1000) });
        }

        // std.debug.print("Size {} bytes \n", .{list.contentSize(.bytes)});

        for (keys.items) |key| {
            // const startTime = std.time.nanoTimestamp();
            const v = list.remove(key);
            if (v == null) unreachable;
            // const endTime = (std.time.nanoTimestamp() - startTime);
            // std.debug.print("Removed - {}:{}, took {} millisec \n", .{ v.?, key, @divTrunc(endTime, 1000) });
        }

        // std.debug.print("Size {} bytes \n", .{list.contentSize(.bytes)});

        //std.debug.print("=======================================================================\n", .{});
        list.forEach(handler);

        for (keys.items) |key| {
            if (list.get(key)) |v| {
                std.debug.print("Should not be there; Got - {}:{}\n", .{ v, key });
            }

            if (list.remove(key)) |v| {
                std.debug.print("Should not be there; Removed - {}:{}\n", .{ v, key });
            }
        }

        // std.debug.print("Finished removing data \n", .{});
    }

    //std.time.sleep(@as(u64, 1 * 60 * 60) * std.time.ns_per_s);
}

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

    const total = std.math.maxInt(u22);

    //const F64 = xstd.cmp.Wrapper(f64);

    const handler = struct {
        pub fn f(key: f64, value: usize) void {
            std.debug.print("{}:{} \n", .{ value, key });
        }
    }.f;

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();

    for (0..1000000000000) |i| {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var list = try SkipList(f64, usize).init(allocator, .{});
        defer list.deinit();

        var keys = std.ArrayList(f64).init(allocator);
        errdefer keys.deinit();
        defer keys.deinit();

        var nanos: i128 = 0;
        var items: i128 = 0;
        for (0..total) |v| {
            //const key = F64.fromLiteral(random.float(f64));
            const key = random.float(f64);
            try keys.append(key);

            const startTime = std.time.nanoTimestamp();
            _ = try list.insert(key, v);
            const timeConsuption = (std.time.nanoTimestamp() - startTime);
            nanos += timeConsuption;
            items += 1;

            if (v > 0 and v % 100000 == 0 or v == total - 1) {
                std.debug.print("Inserting {} average took {} nanosec \n", .{ v, @divTrunc(nanos, items) });
                nanos = 0;
                items = 0;
            }
        }

        std.debug.print("{} - Added - Size {} bytes; Length {} \n", .{ i, list.contentSize(.bytes), list.len });

        nanos = 0;
        items = 0;
        for (keys.items, 0..) |key, idx| {
            const startTime = std.time.nanoTimestamp();
            const v = list.remove(key);
            if (v == null) {
                std.debug.panic("Value retrived is null", .{});
            }

            nanos += (std.time.nanoTimestamp() - startTime);
            items += 1;

            if (idx > 0 and idx % 100000 == 0 or idx == keys.items.len - 1) {
                std.debug.print("Removed {} average took {} nanosec \n", .{ idx, @divTrunc(nanos, items) });
                nanos = 0;
                items = 0;
            }
        }

        std.debug.print("{} - Removed - Size {} bytes; Length {} \n", .{ i, list.contentSize(.bytes), list.len });

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

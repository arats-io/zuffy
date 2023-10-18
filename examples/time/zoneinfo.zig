const std = @import("std");
const xstd = @import("xstd");

pub fn main() !void {
    const startTime = std.time.nanoTimestamp();
    const z = try xstd.time.zoneinfo.Local.Get();
    const o = z.Lookup();
    std.debug.print("Zone: {}\n", .{o.offset});

    std.debug.print("Time spent to call GetLocation: {d} nano\n", .{std.time.nanoTimestamp() - startTime});

    const z1 = try xstd.time.zoneinfo.Local.Get();
    const o1 = z1.Lookup();

    std.debug.print("Zone: {}\n", .{o1.offset});
}

const std = @import("std");
const xstd = @import("xstd");

pub fn main() !void {
    std.debug.print("\n--------------------------------------------\n", .{});

    var startTime = std.time.nanoTimestamp();
    const z = try xstd.time.zoneinfo.Local.Get();

    std.debug.print("Location Name: {s}\n", .{z.name});

    const o = z.Lookup();
    std.debug.print("Zone: {}\n", .{o});

    std.debug.print("Time spent to call GetLocation: {d} nano\n", .{std.time.nanoTimestamp() - startTime});

    std.debug.print("\n--------------------------------------------\n", .{});
    startTime = std.time.nanoTimestamp();
    const z1 = try xstd.time.zoneinfo.Local.Get();
    const o1 = z1.Lookup();
    std.debug.print("Second Time spent to call GetLocation: {d} nano\n", .{std.time.nanoTimestamp() - startTime});

    std.debug.print("Zone: {}\n", .{o1});
    std.debug.print("Zone Offset: {d}\n", .{o1.offset});
    std.debug.print("Zone Name: {s}\n", .{o1.name});
}

const std = @import("std");
const zuffy = @import("zuffy");

pub fn main() !void {
    std.debug.print("\n--------------------------------------------\n", .{});

    var startTime = std.time.nanoTimestamp();
    const z = try zuffy.time.zoneinfo.Local.Get();

    std.debug.print("Location Name: {s}\n", .{z.name});
    std.debug.print("Location Extend: {s}\n", .{z.extend});

    const o = z.Lookup();
    std.debug.print("Zone: {}\n", .{o});
    std.debug.print("Zone Offset: {d}\n", .{o.offset});
    std.debug.print("Zone Name: {s}\n", .{o.name});

    std.debug.print("Time spent to call GetLocation: {d} nano\n", .{std.time.nanoTimestamp() - startTime});

    std.debug.print("\n--------------------------------------------\n", .{});
    startTime = std.time.nanoTimestamp();
    const z1 = try zuffy.time.zoneinfo.Local.Get();
    const o1 = z1.Lookup();
    std.debug.print("Second Time spent to call GetLocation: {d} nano\n", .{std.time.nanoTimestamp() - startTime});

    std.debug.print("Zone: {}\n", .{o1});
    std.debug.print("Zone Offset: {d}\n", .{o1.offset});
    std.debug.print("Zone Name: {s}\n", .{o1.name});
}

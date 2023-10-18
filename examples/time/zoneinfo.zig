const std = @import("std");
const xstd = @import("xstd");

pub fn main() !void {
    const startTime = std.time.nanoTimestamp();
    _ = try xstd.time.zoneinfo.GetLocation();
    std.debug.print("Time spent to call GetLocation: {d} nano\n", .{std.time.nanoTimestamp() - startTime});

    const z = try xstd.time.zoneinfo.GetLocation();
    const o = z.Lookup();

    var buff = [_]u8{undefined} ** 100;
    const name = try std.fmt.bufPrint(&buff, "{s}", .{o.name});
    std.debug.print("Zone: {s}\n", .{name});
}

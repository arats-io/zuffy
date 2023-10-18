const std = @import("std");
const xstd = @import("xstd");

pub fn main() !void {
    var z = xstd.time.zoneinfo.GetLocation();

    std.debug.print("{s}\n", .{z.extend});

    z = xstd.time.zoneinfo.GetLocation();

    std.debug.print("{s}\n", .{z.extend});
}

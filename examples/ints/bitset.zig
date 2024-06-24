const std = @import("std");
const xstd = @import("xstd");

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    const bitset = xstd.ints.toBitSet(u16, 999);
    std.debug.print("bitset - {any}\n", .{bitset});

    std.debug.print("bitset - ", .{});
    for (0..16) |idx| {
        const bit = bitset.isSet(idx);
        switch (bit) {
            true => std.debug.print("1", .{}),
            else => std.debug.print("0", .{}),
        }
    }
    std.debug.print("\n", .{});

    const value = xstd.ints.fromBitSet(u16, bitset);
    std.debug.print("value - {any}\n", .{value});

    std.debug.print("Stoping application.\n", .{});
}

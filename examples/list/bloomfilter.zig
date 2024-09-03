const std = @import("std");
const zuffy = @import("zuffy");

const Allocator = std.mem.Allocator;

const BloomFilter = zuffy.BloomFilter;

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var bloomf = try BloomFilter.init(10000, 5, allocator);
    defer bloomf.deinit();

    var hash = std.hash.Fnv1a_64.init();
    hash.update("asdasd");

    try bloomf.Add(&hash);

    var hash2 = std.hash.Fnv1a_64.init();
    hash2.update("asdasd1");
    const result = try bloomf.Contains(&hash2);
    std.debug.print("Contains {}.\n", .{result});
}

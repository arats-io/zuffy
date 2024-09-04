const std = @import("std");
const zuffy = @import("zuffy");

const Allocator = std.mem.Allocator;

const BloomFilter = zuffy.BloomFilter(u128);

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var bloomf = try BloomFilter.init(1_000_000, 500, allocator);
    defer bloomf.deinit();

    var hash = std.hash.Fnv1a_128.init();
    hash.update("asdasd");

    var hash2 = std.hash.Fnv1a_128.init();
    hash2.update("dfgasdf");

    std.debug.print("Added = asdasd.\n", .{});
    try bloomf.Add(&hash);

    const result1 = try bloomf.Contains(&hash);
    const result2 = try bloomf.Contains(&hash2);
    std.debug.print("Contains asdasd={} dfgasdf={}.\n", .{ result1, result2 });
}

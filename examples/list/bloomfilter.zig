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
    try bloomf.add(&hash);

    const result1_bloomf = try bloomf.contains(&hash);
    const result2_bloomf = try bloomf.contains(&hash2);
    const false_positive_bloomf = bloomf.falsePosititveProbability();

    std.debug.print("Contains asdasd={} dfgasdf={} - with false positive = {}.\n", .{ result1_bloomf, result2_bloomf, false_positive_bloomf });

    const bytes = try bloomf.marchal();
    defer allocator.free(bytes);

    std.debug.print("Marchal Bytes = {}.\n", .{bytes.len});

    var newbloomf = try BloomFilter.init(1_000_000, 500, allocator);
    defer newbloomf.deinit();

    try newbloomf.unmarchal(bytes);
    const result1_newbloomf = try newbloomf.contains(&hash);
    const result2_newbloomf = try newbloomf.contains(&hash2);
    const false_positive_newbloomf = newbloomf.falsePosititveProbability();

    std.debug.print("Contains asdasd={} dfgasdf={} - with false positive = {}.\n", .{ result1_newbloomf, result2_newbloomf, false_positive_newbloomf });

    if (bloomf.eql(newbloomf)) {
        std.debug.print("Success: Bloomfilter after unmarchaling is the same.\n", .{});
    } else {
        std.debug.print("Error: Bloomfilter after unmarchaling is NOT the same.\n", .{});
    }
}

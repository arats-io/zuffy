const std = @import("std");
const zuffy = @import("zuffy");

const math = std.math;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    // Allocator for the String
    const page_allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    var buffer = zuffy.bytes.Utf8Buffer.init(arena.allocator());
    defer buffer.deinit();

    try buffer.append("💯Hello💯💯Hello💯💯Hello💯💯💯💯");

    var counter: usize = 0;

    var splitSequence = buffer.splitSequence("💯");
    std.debug.print("\n ----- splitSequence ----- \n", .{});
    counter = 0;
    while (splitSequence.next()) |n| {
        counter += 1;
        std.debug.print("{} - [{s}]={d}\n", .{ counter, n, n.len });
    }

    var tokenizeSequence = buffer.tokenizeSequence("💯");
    std.debug.print("\n ----- tokenizeSequence ----- \n", .{});
    counter = 0;
    while (tokenizeSequence.next()) |n| {
        counter += 1;
        std.debug.print("{} - [{s}]={d}\n", .{ counter, n, n.len });
    }

    var splitAny = buffer.splitAny("💯");
    std.debug.print("\n ----- splitAny ----- \n", .{});
    counter = 0;
    while (splitAny.next()) |n| {
        counter += 1;
        std.debug.print("{} - [{s}]={d}\n", .{ counter, n, n.len });
    }

    var splitBackwardsSequence = buffer.splitBackwardsSequence("💯");
    std.debug.print("\n ----- splitBackwardsSequence ----- \n", .{});
    counter = 0;
    while (splitBackwardsSequence.next()) |n| {
        counter += 1;
        std.debug.print("{} - [{s}]={d}\n", .{ counter, n, n.len });
    }

    var splitBackwardsAny = buffer.splitBackwardsAny("💯");
    std.debug.print("\n ----- splitBackwardsAny ----- \n", .{});
    counter = 0;
    while (splitBackwardsAny.next()) |n| {
        counter += 1;
        std.debug.print("{} - [{s}]={d}\n", .{ counter, n, n.len });
    }

    var tokenizeAny = buffer.tokenizeAny("💯");
    std.debug.print("\n ----- tokenizeAny ----- \n", .{});
    counter = 0;
    while (tokenizeAny.next()) |n| {
        counter += 1;
        std.debug.print("{} - [{s}]={d}\n", .{ counter, n, n.len });
    }

    var tokenizeScalar = buffer.tokenizeScalar('H');
    std.debug.print("\n ----- tokenizeScalar ----- \n", .{});
    counter = 0;
    while (tokenizeScalar.next()) |n| {
        counter += 1;
        std.debug.print("{} - [{s}]={d}\n", .{ counter, n, n.len });
    }
}

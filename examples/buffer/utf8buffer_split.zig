const std = @import("std");
const xstd = @import("xstd");

const math = std.math;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    // Allocator for the String
    const page_allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    var buffer = xstd.bytes.Utf8Buffer.init(arena.allocator());
    defer buffer.deinit();

    try buffer.append("💯Hello💯💯Hello💯💯Hello💯");

    var iter = buffer.splitSequence("💯");

    std.debug.print("\n ----- Elements ----- \n", .{});
    std.debug.print("1 - [{s}]\n", .{iter.next().?});
    std.debug.print("2 - [{s}]\n", .{iter.next().?});
    std.debug.print("3 - [{s}]\n", .{iter.next().?});
    std.debug.print("4 - [{s}]\n", .{iter.next().?});
    std.debug.print("5 - [{s}]\n", .{iter.next().?});
    std.debug.print("6 - [{s}]\n", .{iter.next().?});
    std.debug.print("7 - [{s}]\n", .{iter.next().?});

    var tokens = buffer.tokenizeSequence("💯");
    std.debug.print("\n ----- Tokens ----- \n", .{});
    std.debug.print("1 - [{s}]\n", .{tokens.next().?});
    std.debug.print("2 - [{s}]\n", .{tokens.next().?});
    std.debug.print("3 - [{s}]\n", .{tokens.next().?});
}

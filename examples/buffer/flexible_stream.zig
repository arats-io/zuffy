const std = @import("std");
const zuffy = @import("zuffy");

const math = std.math;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var buff = zuffy.bytes.Buffer.init(arena.allocator());
    defer buff.deinit();
    errdefer buff.deinit();

    var fbs = zuffy.bytes.BufferStream(zuffy.bytes.Buffer).init(buff);

    const stream = fbs.writer();

    try stream.print("{s}{s}!", .{ "Hello", "World" });

    const d = fbs.bytes();

    std.debug.print("Result [{s}]!\n", .{d});

    const reader = fbs.reader();

    var dest: [4]u8 = undefined;

    var size = try reader.read(&dest);
    std.debug.print("Result - {s}\n", .{dest[0..size]});

    size = try reader.read(&dest);
    std.debug.print("Result - {s}\n", .{dest[0..size]});

    size = try reader.read(&dest);
    std.debug.print("Result - {s}\n", .{dest[0..size]});
}

const std = @import("std");
const xstd = @import("xstd");

const math = std.math;
const Allocator = std.mem.Allocator;

const CircularLifoList = xstd.list.circular.CircularLifoList;
const CircularFifoList = xstd.list.circular.CircularFifoList;

const Package = struct {
    value: i128,
};

fn printList(l: anytype) void {
    for (0..l.cap) |i| {
        if (l.read(i)) |x| {
            std.debug.print("{}, ", .{x});
        }
    }
    std.debug.print("\n", .{});
}

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var d = CircularFifoList(i32).init(allocator, 3, .{ .mode = .fixed });
    defer d.deinit();

    _ = d.push(1);
    _ = d.push(2);
    _ = d.push(3);

    printList(d);

    _ = d.push(4);

    printList(d);

    if (d.pop()) |x| {
        std.debug.print("\n======== Pop ======== : {}\n", .{x});

        printList(d);
    }

    _ = d.push(5);
    _ = d.push(6);
    _ = d.push(7);

    printList(d);

    if (d.pop()) |x| {
        std.debug.print("\n======== Pop ======== : {}\n", .{x});
        printList(d);
    }

    _ = d.push(8);
    _ = d.push(9);

    printList(d);

    std.debug.print("\n======== Pop ======== : ", .{});
    while (d.pop()) |x| {
        std.debug.print("{},", .{x});
    }
    std.debug.print("\n", .{});

    _ = d.push(11);
    _ = d.push(12);
    _ = d.push(13);
    _ = d.push(14);
    _ = d.push(15);
    _ = d.push(16);
    _ = d.push(17);
    _ = d.push(37);
    _ = d.push(18);
    _ = d.push(19);

    printList(d);

    try d.resize(10);
    std.debug.print("\nResized to 10 =>", .{});

    printList(d);

    _ = d.push(19);
    _ = d.push(20);
    _ = d.push(21);
    _ = d.push(22);
    _ = d.push(23);
    _ = d.push(24);

    printList(d);

    std.debug.print("\n======== Pop ======== : ", .{});
    while (d.pop()) |x| {
        std.debug.print("{},", .{x});
    }

    std.debug.print("\n", .{});
}

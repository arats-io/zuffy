const std = @import("std");

const math = std.math;
const Allocator = std.mem.Allocator;
const expect = @import("std").testing.expect;

var foo: u8 align(8) = 2;

const Data = extern struct { a: i32, b: u8, c: f32, d: bool, e: bool };

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    std.debug.print("{}\n", .{@typeInfo(@TypeOf(&foo)).pointer.alignment});
    std.debug.print("{}\n", .{@TypeOf(&foo) == *align(8) u8});
    const as_pointer_to_array: *align(8) [1]u8 = &foo;
    const as_slice: []align(8) u8 = as_pointer_to_array;
    const as_unaligned_slice: []u8 = as_slice;
    std.debug.print("{}\n", .{as_unaligned_slice[0]});

    std.debug.print("{}\n", .{@alignOf(i128)});
    std.debug.print("{}\n", .{@alignOf(struct { u128 })});

    const x = Data{
        .a = 10005,
        .b = 42,
        .c = -10.5,
        .d = false,
        .e = true,
    };
    const z = @as([*]const u8, @ptrCast(&x));
    std.debug.print("{any}\n", .{x});

    try expect(@as(*const i32, @ptrCast(@alignCast(z))).* == 10005);
    try expect(@as(*const u8, @ptrCast(z + 4)).* == 42);
    try expect(@as(*const f32, @ptrCast(@alignCast(z + 8))).* == -10.5);
    try expect(@as(*const bool, @ptrCast(z + 12)).* == false);
    try expect(@as(*const bool, @ptrCast(z + 13)).* == true);

    const ptr1: *align(1) const u32 = @ptrFromInt(0x1000);
    std.debug.print("ptr1 {any}\n", .{ptr1});
    const ptr2: *u8 = @constCast(@alignCast(@ptrCast(ptr1)));
    std.debug.print("ptr2 {any}\n", .{ptr2});
    const ptr3: *u64 = @constCast(@ptrCast(@alignCast(ptr1)));
    std.debug.print("ptr3 {any}\n", .{ptr3});

    std.debug.print("Stoping application.\n", .{});
}

const std = @import("std");
const mem = std.mem;

pub inline fn toHexBytes(comptime T: type, case: std.fmt.Case, src: T) [@divExact(@typeInfo(T).Int.bits, 8) * 2]u8 {
    var srcBytes: [@divExact(@typeInfo(T).Int.bits, 8)]u8 = undefined;
    @as(*align(1) T, @ptrCast(&srcBytes)).* = src;
    return std.fmt.bytesToHex(srcBytes, case);
}

pub inline fn fromHexBytes(comptime R: type, endian: std.builtin.Endian, input: []const u8) !R {
    var srcBytes: [@divExact(@typeInfo(R).Int.bits, 8)]u8 = undefined;
    const result = try std.fmt.hexToBytes(&srcBytes, input);

    var s = std.io.fixedBufferStream(result);
    return s.reader().readInt(R, endian);
}

pub inline fn fromHexBytes2(comptime size: usize, input: []const u8) ![]u8 {
    var srcBytes: [size]u8 = undefined;
    return try std.fmt.hexToBytes(&srcBytes, input);
}

pub inline fn toBytes(comptime T: type, value: T, endian: std.builtin.Endian) [@divExact(@typeInfo(T).Int.bits, 8)]u8 {
    var bytes: [@divExact(@typeInfo(T).Int.bits, 8)]u8 = undefined;
    mem.writeInt(T, &bytes, value, endian);
    return bytes;
}

pub fn toBitSet(comptime T: type, value: T) std.StaticBitSet(@bitSizeOf(T)) {
    var bitset = std.StaticBitSet(@bitSizeOf(T)).initEmpty();
    if (value == 0) return bitset;

    switch (@typeInfo(T)) {
        .Int => {},
        else => unreachable,
    }

    var idx: usize = 0;
    var bf = value;
    while (bf > 0) {
        const shift = bf % 2;
        if (shift == 1) {
            bitset.set(idx);
        }
        bf = bf / 2;
        idx = idx + 1;
    }

    return bitset;
}

pub fn fromBitSet(comptime T: type, bitset: std.StaticBitSet(@bitSizeOf(T))) T {
    const t = @typeInfo(T);
    const bits = switch (t) {
        .Int => t.Int.bits,
        else => unreachable,
    };

    var bf: T = 0;
    for (0..(bits - 1)) |idx| {
        const bit: u8 = if (bitset.isSet(idx)) 1 else 0;
        bf += (bit * std.math.pow(T, 2, @intCast(idx)));
    }
    return bf;
}

const std = @import("std");
const builtin = @import("builtin");

const io = std.io;
const testing = std.testing;
const mem = std.mem;

const Buffer = @import("buffer.zig");

const Self = @This();

/// This turns a byte buffer into an `io.Writer`, `io.Reader`, or `io.SeekableStream`.
/// If the supplied byte buffer is const, then `io.Writer` is not available.
buffer: Buffer,
pos: usize,

pub const ReadError = error{} || Buffer.Error;
pub const WriteError = error{} || Buffer.Error;
pub const SeekError = error{};
pub const GetSeekPosError = error{IsEmpty};

pub const Error = ReadError || WriteError || SeekError || GetSeekPosError;

pub const Reader = io.Reader(*Self, ReadError, read);
pub const Writer = io.Writer(*Self, WriteError, write);

pub const SeekableStream = io.SeekableStream(
    *Self,
    SeekError,
    GetSeekPosError,
    seekTo,
    seekBy,
    getPos,
    getEndPos,
);

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{ .buffer = Buffer.init(allocator), .pos = 0 };
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
}

pub fn reader(self: *Self) Reader {
    return .{ .context = self };
}

pub fn writer(self: *Self) Writer {
    return .{ .context = self };
}

pub fn bytes(self: *Self) []const u8 {
    return self.buffer.bytes();
}

pub fn clear(self: *Self) void {
    self.buffer.clear();
    self.reset();
}

pub fn seekableStream(self: *Self) SeekableStream {
    self.reset();

    return .{ .context = self };
}

pub fn read(self: *Self, dest: []u8) ReadError!usize {
    const size = @min(dest.len, self.buffer.len - self.pos);
    if (size == 0) return 0;

    const end = self.pos + size;

    const data = try self.buffer.rangeBytes(self.pos, end);

    @memcpy(dest[0..size], data[0..]);
    self.pos = end;

    return size;
}

pub fn write(self: *Self, data: []const u8) WriteError!usize {
    return try self.buffer.write(data);
}

pub fn seekTo(self: *Self, pos: u64) SeekError!void {
    self.pos = @min(std.math.lossyCast(usize, pos), self.buffer.len);
}

pub fn seekBy(self: *Self, amt: i64) SeekError!void {
    if (amt < 0) {
        const abs_amt = @abs(amt);
        const abs_amt_usize = std.math.cast(usize, abs_amt) orelse std.math.maxInt(usize);
        if (abs_amt_usize > self.pos) {
            self.pos = 0;
        } else {
            self.pos -= abs_amt_usize;
        }
    } else {
        const amt_usize = std.math.cast(usize, amt) orelse std.math.maxInt(usize);
        const new_pos = std.math.add(usize, self.pos, amt_usize) catch std.math.maxInt(usize);
        self.pos = @min(self.buffer.rawLength(), new_pos);
    }
}

pub fn getEndPos(self: *Self) GetSeekPosError!u64 {
    if (self.buffer.len == 0) return GetSeekPosError.IsEmpty;
    return self.buffer.len;
}

pub fn getPos(self: *Self) GetSeekPosError!u64 {
    if (self.buffer.len == 0) return GetSeekPosError.IsEmpty;
    return self.pos;
}

pub fn reset(self: *Self) void {
    self.pos = 0;
}

const assert = std.debug.assert;
test "output" {
    // Allocator
    const page_allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    var fbs = Self.init(arena.allocator());
    defer fbs.deinit();

    const writero = fbs.writer();

    try writero.print("{s}{s}!", .{ "Hello", "World" });
    try testing.expectEqualSlices(u8, "HelloWorld!", fbs.buffer.bytes());
}

test "input" {
    const page_allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    var fbs = Self.init(arena.allocator());
    defer fbs.deinit();

    var writero = fbs.writer();

    const byteso = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };
    _ = try writero.write(&byteso);

    var readero = fbs.reader();

    var dest: [4]u8 = undefined;

    var size = try readero.read(&dest);
    try testing.expect(size == 4);
    try testing.expect(mem.eql(u8, dest[0..4], byteso[0..4]));

    size = try readero.read(&dest);
    try testing.expect(size == 3);
    try testing.expect(mem.eql(u8, dest[0..3], byteso[4..7]));

    size = try readero.read(&dest);
    try testing.expect(size == 0);

    try fbs.seekTo((try fbs.getEndPos()) + 1);
    size = try readero.read(&dest);
    try testing.expect(size == 0);
}

const std = @import("std");
const builtin = @import("builtin");

const assert = std.debug.assert;

/// A byte buffer will make a best effort to perform native I/O operations directly upon it.
/// That is, it will attempt to avoid copying the buffer's content to (or from) an intermediate
/// buffer before (or after) each invocation of one of the underlying operating system's native I/O operations.
const Self = @This();
pub const Error = error{
    InvalidRange,
    InvalidCapacity,
} || std.mem.Allocator.Error;

allocator: std.mem.Allocator,

ptr: [*]u8,

cap: usize = 0,
len: usize = 0,
factor: f16 = 0.75,

/// Init the byte buffer with a factor value neccessary when resizing is required
pub fn initWithFactor(allocator: std.mem.Allocator, factor: f16) Self {
    return Self{
        .ptr = &[_]u8{},
        .allocator = allocator,
        .cap = 0,
        .len = 0,
        .factor = if (factor <= 0) 0.75 else factor,
    };
}

/// Init the byte buffer with default factor
pub fn init(allocator: std.mem.Allocator) Self {
    return initWithFactor(allocator, 0.75);
}

/// Rreeing the allocation of array of bytes and set all values on zero
pub fn deinit(self: *Self) void {
    self.allocator.free(self.ptr[0..self.cap]);
    self.ptr = &[_]u8{};
    self.len = 0;
    self.cap = 0;
}

/// Resizing the buffer to given capacity.
/// Will not resize back to loose the data
pub fn resize(self: *Self, cap: usize) !void {
    if (cap < self.len) return Error.InvalidCapacity;

    const new_source = try self.allocator.realloc(self.ptr[0..self.cap], cap);
    self.ptr = new_source.ptr;
    self.cap = new_source.len;
    if (self.len > cap) {
        self.len = new_source.len;
    }
}

/// Shrink the buffer capacity to the active length
pub fn shrink(self: *Self) !void {
    try self.resize(self.len);
}

/// Write a byte to the buffer
pub fn writeByte(self: *Self, byte: u8) !void {
    if (self.len + 1 > self.cap) {
        const new_cap = self.len + 1 +
            @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.len)) * @as(f64, self.factor)));
        try self.resize(new_cap);
    }

    self.ptr[self.len] = byte;

    self.len += 1;
}

/// Write given `max_num` number of bytes which are read from the given `reader`
pub fn writeNBytes(self: *Self, reader: anytype, max_num: usize) !void {
    for (0..max_num) |_| {
        const byte = try reader.readByte();
        try self.writeByte(byte);
    }
}

/// Write an array of bytes to the buffer
pub fn writeAll(self: *Self, array: []const u8) !void {
    _ = try self.write(array);
}

/// Write an array of bytes to the buffer
pub fn write(self: *Self, array: []const u8) !usize {
    if (array.len == 0) return 0;

    if (self.len + array.len > self.cap) {
        const new_cap = self.len + array.len +
            @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.len)) * @as(f64, self.factor)));
        try self.resize(new_cap);
    }

    var i: usize = 0;
    while (i < array.len) : (i += 1) {
        self.ptr[self.len + i] = array[i];
    }

    self.len += array.len;

    return array.len;
}

/// Write any array of values by formating them on given format
pub fn print(self: *Self, comptime format: []const u8, args: anytype) !void {
    const writer = self.writer();
    return std.fmt.format(writer, format, args);
}

/// Read the content of buffer into the given destination
pub fn read(self: *Self, dst: []u8) !usize {
    const size = if (self.len < dst.len) self.len else dst.len;
    _copy(u8, dst, self.ptr[0..size]);
    return size;
}

pub fn readFrom(self: *Self, pos: usize, dst: []u8) !usize {
    if ((self.len - pos) <= 0) return 0;

    const size = if (self.len - pos < dst.len) self.len - pos else dst.len;
    _copy(u8, dst, self.ptr[pos..size]);
    return size;
}

/// Compare the buffer with given array
pub fn compare(self: *Self, str: []const u8) bool {
    if (self.len < str.len) return false;

    return std.mem.eql(u8, self.ptr[0..str.len], str.ptr[0..str.len]);
}

/// Compare the buffer from a given position with given array
pub fn compareStartPos(self: *Self, pos: usize, str: []const u8) bool {
    if (pos >= self.len) return false;
    if ((self.len - pos) < str.len) return false;

    return std.mem.eql(u8, self.ptr[pos..str.len], str.ptr[0..str.len]);
}

/// Retun the buffer bytes up to current length
pub fn bytes(self: *Self) []const u8 {
    return self.ptr[0..self.len];
}

/// Return the byte at given position
pub fn byteAt(self: *Self, index: usize) !u8 {
    if (index < self.len) {
        return self.ptr[index];
    }
    return Error.InvalidRange;
}

/// Return a portion of bytes from the buffer based on the given range of indexes
pub fn bytesRange(self: *Self, start: usize, end: usize) ![]const u8 {
    if (start < self.len and end <= self.len and start < end) {
        return self.ptr[start..end];
    }
    return Error.InvalidRange;
}

/// Return a portion of bytes from the buffer based on the given start position
pub fn bytesFrom(self: *Self, start: usize) ![]const u8 {
    if (start < self.len) {
        return self.ptr[start..self.len];
    }
    return Error.InvalidRange;
}

/// Return a portion of bytes from the buffer up to a given end position
pub fn bytesUpTo(self: *Self, end: usize) ![]const u8 {
    if (end < self.len) {
        return self.ptr[0..end];
    }
    return Error.InvalidRange;
}

/// Deep copy of buffer, retrieved as a clone using buffer allocator.
pub fn clone(self: *Self) !Self {
    return self.cloneUsingAllocator(self.allocator);
}

/// Deep copy of buffer, retrieved as a clone using a given allocator.
pub fn cloneUsingAllocator(self: *Self, allocator: std.mem.Allocator) !Self {
    var buf = init(allocator);
    errdefer buf.deinit();

    _ = try buf.write(self.ptr[0..self.len]);
    return buf;
}

/// Retrieve the the whole copy of buffer as an array of bytes, using buffer allocator
pub fn copy(self: *Self) ![]u8 {
    return self.copyUsingAllocator(self.allocator);
}

/// Retrieve the the whole copy of buffer as an array of bytes, using a given allocator
pub fn copyUsingAllocator(self: *Self, allocator: std.mem.Allocator) ![]u8 {
    const new_str = try allocator.alloc(u8, self.len);
    _copy(u8, new_str, self.ptr[0..self.len]);
    return new_str;
}

/// Repead same buffer content `N` times
pub fn repeat(self: *Self, n: usize) !void {
    try self.resize(self.cap * (n + 1));

    var i: usize = 1;
    while (i <= n) : (i += 1) {
        var j: usize = 0;
        while (j < self.len) : (j += 1) {
            self.ptr[((i * self.len) + j)] = self.ptr[j];
        }
    }

    self.len *= (n + 1);
}

/// Verify if the buffer is empty
pub fn isEmpty(self: *Self) bool {
    return self.len == 0;
}

/// Clear the whole buffer content
pub fn clear(self: *Self) void {
    @memset(self.ptr[0..self.len], 0);
    self.len = 0;
}

///Free and clear the whole buffer content
pub fn clearAndFree(self: *Self) void {
    self.deinit();
}

fn _copy(comptime Type: type, dest: []Type, src: []const Type) void {
    assert(dest.len >= src.len);

    if (@intFromPtr(src.ptr) == @intFromPtr(dest.ptr) or src.len == 0) return;

    const input: []const Type = std.mem.sliceAsBytes(src);
    const output: []Type = std.mem.sliceAsBytes(dest);

    assert(input.len > 0);
    assert(output.len > 0);

    const is_input_or_output_overlaping = (@intFromPtr(input.ptr) < @intFromPtr(output.ptr) and
        @intFromPtr(input.ptr) + input.len > @intFromPtr(output.ptr)) or
        (@intFromPtr(output.ptr) < @intFromPtr(input.ptr) and
        @intFromPtr(output.ptr) + output.len > @intFromPtr(input.ptr));

    if (is_input_or_output_overlaping) {
        @memcpy(output, input);
    } else {
        std.mem.copyBackwards(Type, output, input);
    }
}

/// Returns an iterator that iterates over the slices of `buffer` that
/// are separated by the byte sequence in `delimiter`.
///
/// `splitSequence(u8, "abc||def||||ghi", "||")` will return slices
/// for "abc", "def", "", "ghi", null, in that order.
///
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
/// The delimiter length must not be zero.
pub fn splitSequence(self: *Self, delimiters: []const u8) std.mem.SplitIterator(u8, .sequence) {
    assert(delimiters.len != 0);
    return .{
        .index = 0,
        .buffer = self.ptr[0..self.len],
        .delimiter = delimiters,
    };
}

/// Returns an iterator that iterates over the slices of `buffer` that
/// are separated by any item in `delimiters`.
///
/// `splitAny(u8, "abc,def||ghi", "|,")` will return slices
/// for "abc", "def", "", "ghi", null, in that order.
///
/// If none of `delimiters` exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub fn splitAny(self: *Self, delimiters: []const u8) std.mem.SplitIterator(u8, .any) {
    return .{
        .index = 0,
        .buffer = self.ptr[0..self.len],
        .delimiter = delimiters,
    };
}

/// Returns an iterator that iterates over the slices of `buffer` that
/// are separated by `delimiter`.
///
/// `splitScalar(u8, "abc|def||ghi", '|')` will return slices
/// for "abc", "def", "", "ghi", null, in that order.
///
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub fn splitScalar(self: *Self, delimiter: u8) std.mem.SplitIterator(u8, .scalar) {
    return .{
        .index = 0,
        .buffer = self.ptr[0..self.len],
        .delimiter = delimiter,
    };
}
/// Returns an iterator that iterates backwards over the slices of `buffer` that
/// are separated by the sequence in `delimiter`.
///
/// `splitBackwardsSequence(u8, "abc||def||||ghi", "||")` will return slices
/// for "ghi", "", "def", "abc", null, in that order.
///
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
/// The delimiter length must not be zero.
pub fn splitBackwardsSequence(self: *Self, delimiters: []const u8) std.mem.SplitBackwardsIterator(u8, .sequence) {
    assert(delimiters.len != 0);
    return .{
        .index = self.len,
        .buffer = self.ptr[0..self.len],
        .delimiter = delimiters,
    };
}

/// Returns an iterator that iterates backwards over the slices of `buffer` that
/// are separated by any item in `delimiters`.
///
/// `splitBackwardsAny(u8, "abc,def||ghi", "|,")` will return slices
/// for "ghi", "", "def", "abc", null, in that order.
///
/// If none of `delimiters` exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub fn splitBackwardsAny(self: *Self, delimiters: []const u8) std.mem.SplitBackwardsIterator(u8, .any) {
    return .{
        .index = self.len,
        .buffer = self.ptr[0..self.len],
        .delimiter = delimiters,
    };
}

/// Returns an iterator that iterates backwards over the slices of `buffer` that
/// are separated by `delimiter`.
///
/// `splitBackwardsScalar(u8, "abc|def||ghi", '|')` will return slices
/// for "ghi", "", "def", "abc", null, in that order.
///
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub fn splitBackwardsScalar(self: *Self, delimiter: u8) std.mem.SplitBackwardsIterator(u8, .scalar) {
    return .{
        .index = self.len,
        .buffer = self.ptr[0..self.len],
        .delimiter = delimiter,
    };
}

/// Returns an iterator that iterates over the slices of `buffer` that are not
/// any of the items in `delimiters`.
///
/// `tokenizeAny(u8, "   abc|def ||  ghi  ", " |")` will return slices
/// for "abc", "def", "ghi", null, in that order.
///
/// If `buffer` is empty, the iterator will return null.
/// If none of `delimiters` exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub fn tokenizeAny(self: *Self, delimiters: []const u8) std.mem.TokenIterator(u8, .any) {
    return .{
        .index = 0,
        .buffer = self.ptr[0..self.len],
        .delimiter = delimiters,
    };
}

/// Returns an iterator that iterates over the slices of `buffer` that are not
/// the sequence in `delimiter`.
///
/// `tokenizeSequence(u8, "<>abc><def<><>ghi", "<>")` will return slices
/// for "abc><def", "ghi", null, in that order.
///
/// If `buffer` is empty, the iterator will return null.
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
/// The delimiter length must not be zero.
pub fn tokenizeSequence(self: *Self, delimiter: []const u8) std.mem.TokenIterator(u8, .sequence) {
    assert(delimiter.len != 0);
    return .{
        .index = 0,
        .buffer = self.ptr[0..self.len],
        .delimiter = delimiter,
    };
}

/// Returns an iterator that iterates over the slices of `buffer` that are not
/// `delimiter`.
///
/// `tokenizeScalar(u8, "   abc def     ghi  ", ' ')` will return slices
/// for "abc", "def", "ghi", null, in that order.
///
/// If `buffer` is empty, the iterator will return null.
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub fn tokenizeScalar(self: *Self, delimiter: u8) std.mem.TokenIterator(u8, .scalar) {
    return .{
        .index = 0,
        .buffer = self.ptr[0..self.len],
        .delimiter = delimiter,
    };
}

/// Retrieve the raw length of teh buffer
pub fn rawLength(self: *Self) usize {
    return self.len;
}

// Reader and Writer functionality.
pub usingnamespace struct {
    pub const Writer = std.io.Writer(*Self, Error, appendWrite);

    pub fn writer(self: *Self) Writer {
        return .{ .context = self };
    }

    fn appendWrite(self: *Self, m: []const u8) !usize {
        return try self.write(m);
    }
};

// Iterator support
pub usingnamespace struct {
    pub const Iterator = struct {
        sb: *Self,
        index: usize,

        pub fn next(it: *Iterator) ?[]const u8 {
            if (it.index >= it.sb.len) return null;
            const i = it.index;
            return it.sb.ptr[i..it.index];
        }

        pub fn nextBytes(it: *Iterator, size: usize) ?[]const u8 {
            if ((it.index + size) >= it.sb.len) return null;

            const i = it.index;
            it.index += size;
            return it.sb.ptr[i..it.index];
        }
    };

    pub fn iterator(self: *Self) Iterator {
        return Iterator{
            .sb = self,
            .index = 0,
        };
    }
};

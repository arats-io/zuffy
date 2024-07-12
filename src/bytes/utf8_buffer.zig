const std = @import("std");
const builtin = @import("builtin");

const Buffer = @import("buffer.zig");

/// A UTF8 buffer will make a best effort to perform native I/O operations directly upon it.
/// That is, it will attempt to avoid copying the buffer's content to (or from) an intermediate
/// buffer before (or after) each invocation of one of the underlying operating system's native I/O operations.
const Self = @This();
const Error = Buffer.Error;

buffer: Buffer,

/// Init a new UTF8 buffer using a given byte buffer
pub fn initWithBuffer(buffer: Buffer) Self {
    return Self{ .buffer = buffer };
}

/// Init a new UTF8 buffer
pub fn init(allocator: std.mem.Allocator) Self {
    return Self{ .buffer = Buffer.init(allocator) };
}

/// Init the UTF8 buffer with a factor value neccessary when resizing is required
pub fn initWithFactor(allocator: std.mem.Allocator, factor: f16) Self {
    return Self{ .buffer = Buffer.initWithFactor(allocator, factor) };
}

/// Init the UTF8 buffer and resizing to the desired size
pub inline fn initWithCapacity(allocator: std.mem.Allocator, size: usize) !Self {
    var d = init(allocator);
    errdefer d.deinit();

    try d.buffer.resize(size);
    return d;
}

/// Destroy the buffer
pub inline fn deinit(self: *Self) void {
    self.buffer.deinit();
}

/// Append to the buffer an specific number of runes from the given bytes
pub inline fn appendN(self: *Self, str: []const u8, numOfChars: usize) !void {
    try self.insertAtWithLength(self.buffer.len, str, numOfChars);
}

/// Append to the buffer the whole given string
pub inline fn append(self: *Self, str: []const u8) !void {
    try self.insertAtWithLength(self.buffer.len, str, str.len);
}

/// Insert the string st given position
pub inline fn insertAt(self: *Self, str: []const u8, index: usize) !void {
    try self.insertAtWithLength(index, str, str.len);
}

noinline fn insertAtWithLength(self: *Self, index: usize, array: []const u8, len: usize) !void {
    if (len == 0) return;

    const numberOfChars = if (len > array.len) array.len else len;

    // Make sure buffer has enough space
    if (self.buffer.len + numberOfChars > self.buffer.cap) {
        const f = if (self.buffer.len > 0) result: {
            const t: f64 = @round(@as(f64, @floatFromInt(self.buffer.len)) * @as(f64, @floatCast(self.buffer.factor)));
            const res: usize = @truncate(@as(usize, @intFromFloat(t)));
            break :result @abs(res);
        } else 1;

        try self.buffer.resize(self.buffer.len + numberOfChars + f);
    }

    // If the index is >= len, then simply push to the end.
    // If not, then copy contents over and insert the given array.
    if (index == self.buffer.len) {
        var i: usize = 0;
        while (i < numberOfChars) : (i += 1) {
            self.buffer.ptr[self.buffer.len + i] = array[i];
        }
    } else {
        if (self.utf8Position(index, true)) |k| {
            // Move existing contents over
            var i: usize = self.buffer.len - 1;
            while (i >= k) : (i -= 1) {
                if (i + numberOfChars < self.buffer.cap) {
                    self.buffer.ptr[i + numberOfChars] = self.buffer.ptr[i];
                }

                if (i == 0) break;
            }

            i = 0;
            while (i < numberOfChars) : (i += 1) {
                self.buffer.ptr[index + i] = array[i];
            }
        }
    }

    @atomicStore(usize, &self.buffer.len, self.buffer.len + numberOfChars, .monotonic);
}

/// Return a portion of bytes from the buffer based on the given range of indexes
pub inline fn bytesRange(self: *Self, start: usize, end: usize) ![]const u8 {
    return self.buffer.rangeBytes(start, end);
}

/// Return a portion of bytes from the buffer based on the given start position
pub inline fn bytesFrom(self: *Self, start: usize) ![]const u8 {
    self.buffer.bytesFromPos(start);
}

/// Return a portion of bytes from the buffer up to a given end position
pub inline fn bytesUpTo(self: *Self, end: usize) ![]const u8 {
    self.buffer.bytesUpTo(end);
}

/// Append to the buffer using formating
pub inline fn appendf(self: *Self, comptime format: []const u8, args: anytype) !void {
    return self.buffer.print(format, args);
}

/// Write to the buffer the given array
pub inline fn write(self: *Self, array: []const u8) !usize {
    return self.buffer.write(array);
}

/// Print/Append to the buffer using formating
pub inline fn print(self: *Self, comptime format: []const u8, args: anytype) !void {
    return self.buffer.print(format, args);
}

/// Repead same buffer content `N` times
pub inline fn repeat(self: *Self, n: usize) !void {
    try self.buffer.repeat(n);
}

noinline fn replace(self: *Self, index: usize, src: []const u8, dst: []const u8) !void {
    if (dst.len > src.len) {
        // Make sure buffer has enough space
        const size = self.buffer.len + (dst.len - src.len);
        if (size > self.buffer.cap) {
            try self.buffer.resize(size);
        }

        // Move existing contents over, as expanding
        for (0..(dst.len - src.len)) |_| {
            var i: usize = self.buffer.len;
            while (i >= (index + src.len)) : (i -= 1) {
                self.buffer.ptr[i] = self.buffer.ptr[i - 1];
            }
            @atomicStore(usize, &self.buffer.len, self.buffer.len + 1, .monotonic);
        }
    } else if (dst.len < src.len) {
        // Move existing contents over, as shriking
        const diff = src.len - dst.len;

        var i: usize = index + dst.len;
        while (i < self.buffer.len) : (i += 1) {
            self.buffer.ptr[i] = self.buffer.ptr[i + diff];
        }

        @atomicStore(usize, &self.buffer.len, self.buffer.len - diff, .monotonic);
    }
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        self.buffer.ptr[index + i] = dst.ptr[i];
    }
}

/// Replace last matche in the buffer the source with destination
pub inline fn replaceLast(self: *Self, src: []const u8, dst: []const u8) !bool {
    if (std.mem.lastIndexOfLinear(u8, self.buffer.ptr[0..self.buffer.len], src)) |pos| {
        try self.replace(pos, src, dst);
        return true;
    }
    return false;
}

/// Replace first matche in the buffer the source with destination
pub inline fn replaceFirst(self: *Self, src: []const u8, dst: []const u8) !bool {
    if (std.mem.indexOf(u8, self.buffer.ptr[0..self.buffer.len], src)) |pos| {
        try self.replace(pos, src, dst);
        return true;
    }
    return false;
}

/// Replace all matches in the buffer the source with destination
pub inline fn replaceAll(self: *Self, src: []const u8, dst: []const u8) !bool {
    return self.replaceAllFromPos(0, src, dst);
}

/// Replace all matches in the buffer the source with destination from given start position
pub noinline fn replaceAllFromPos(self: *Self, startPos: usize, src: []const u8, dst: []const u8) !bool {
    var pos: usize = startPos;
    var found = false;
    while (std.mem.indexOf(u8, self.buffer.ptr[pos..self.buffer.len], src)) |index| {
        try self.replace(pos + index, src, dst);
        found = true;
        pos += index + dst.len;
    }
    return found;
}

/// Remove last matche with the source from the buffer
pub inline fn removeLast(self: *Self, src: []const u8) !bool {
    if (std.mem.lastIndexOfLinear(u8, self.buffer.ptr[0..self.buffer.len], src)) |index| {
        try self.replace(index, src, "");
        return true;
    }

    return false;
}

/// Remove first matche with the source from the buffer
pub inline fn removeFirst(self: *Self, src: []const u8) !bool {
    if (std.mem.indexOf(u8, self.buffer.ptr[0..self.buffer.len], src)) |index| {
        try self.replace(index, src, "");
        return true;
    }

    return false;
}

/// Remove all matches with the source from the buffer
pub inline fn removeAll(self: *Self, src: []const u8) !bool {
    return self.replaceAll(src, "");
}

/// Remove data from the buffer starting with given position
pub inline fn removeFrom(self: *Self, pos: usize) !void {
    try self.removeRange(pos, self.buffer.len);
}

/// Remove data from the buffer from beggining up to with given position
pub inline fn removeEnd(self: *Self, len: usize) !void {
    try self.removeRange(self.buffer.len - len, self.buffer.len);
}

/// Remove data from the beggining of buffer up to given length
pub inline fn removeStart(self: *Self, len: usize) !void {
    try self.removeRange(0, len);
}

/// Remove data from the buffer in the given range
pub noinline fn removeRange(self: *Self, start: usize, end: usize) !void {
    if (end < start or end > self.buffer.len) return Buffer.Error.InvalidRange;

    const rStart = self.utf8Position(start, true).?;
    const rEnd = self.utf8Position(end, true).?;
    const difference = rEnd - rStart;

    var i: usize = rEnd;
    while (i < self.buffer.len) : (i += 1) {
        self.buffer.ptr[i - difference] = self.buffer.ptr[i];
    }

    self.buffer.len -= difference;
}

/// Reverse all runes in the buffer
pub noinline fn reverse(self: *Self) void {
    var i: usize = 0;
    while (i < self.buffer.len) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (size > 1) std.mem.reverse(u8, self.buffer.ptr[i..(i + size)]);
        i += size;
    }

    std.mem.reverse(u8, self.buffer.ptr[0..self.buffer.len]);
}

/// Substract a portion of buffer from a given Range
pub noinline fn substractRange(self: *Self, start: usize, end: usize) !Self {
    var result = Self{ .buffer = Buffer.init(self.buffer.allocator) };

    if (self.utf8Position(start, true)) |rStart| {
        if (self.utf8Position(end, true)) |rEnd| {
            if (rEnd < rStart or rEnd > self.buffer.len)
                return Buffer.Error.InvalidRange;
            try result.append(self.buffer.ptr[rStart..rEnd]);
        }
    }

    return result;
}

/// Trim from a begging of the buffer matching the given string
pub noinline fn trimStart(self: *Self, str: []const u8) void {
    var i: usize = 0;
    while (i < self.buffer.len) : (i += 1) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (size > 1 or !in(self.buffer.ptr[i], str)) break;
    }

    if (self.utf8Position(i, false)) |k| {
        self.removeRange(0, k) catch {};
    }
}
noinline fn in(byte: u8, arr: []const u8) bool {
    var i: usize = 0;
    while (i < arr.len) : (i += 1) {
        if (arr[i] == byte) return true;
    }

    return false;
}

/// Trim at the end of the buffer matching the given string
pub inline fn trimEnd(self: *Self, str: []const u8) void {
    self.reverse();
    self.trimStart(str);
    self.reverse();
}

/// Trim on both ends of the buffer matching the given string
pub inline fn trim(self: *Self, str: []const u8) void {
    self.trimStart(str);
    self.trimEnd(str);
}

/// Split block at specific index from the buffer
pub inline fn splitBlockAt(self: *Self, delimiters: []const u8, index: usize) ?[]const u8 {
    return spliter(self.buffer.ptr[0..self.buffer.len], delimiters, index);
}

/// Split block at specific index from the buffer as a copy of buffer
pub noinline fn splitBlockAtAsCopy(self: *Self, delimiters: []const u8, index: usize) !?Self {
    if (self.splitBlockAt(delimiters, index)) |block| {
        var s = Self{ .buffer = Buffer.init(self.buffer.allocator) };
        errdefer s.deinit();

        try s.append(block);
        return s;
    }

    return null;
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
pub inline fn splitSequence(self: *Self, delimiters: []const u8) std.mem.SplitIterator(u8, .sequence) {
    return self.buffer.splitSequence(delimiters);
}

/// Returns an iterator that iterates over the slices of `buffer` that
/// are separated by any item in `delimiters`.
///
/// `splitAny(u8, "abc,def||ghi", "|,")` will return slices
/// for "abc", "def", "", "ghi", null, in that order.
///
/// If none of `delimiters` exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub inline fn splitAny(self: *Self, delimiters: []const u8) std.mem.SplitIterator(u8, .any) {
    return self.buffer.splitAny(delimiters);
}

/// Returns an iterator that iterates over the slices of `buffer` that
/// are separated by `delimiter`.
///
/// `splitScalar(u8, "abc|def||ghi", '|')` will return slices
/// for "abc", "def", "", "ghi", null, in that order.
///
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub inline fn splitScalar(self: *Self, delimiter: u8) std.mem.SplitIterator(u8, .scalar) {
    return self.buffer.splitScalar(delimiter);
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
pub inline fn splitBackwardsSequence(self: *Self, delimiters: []const u8) std.mem.SplitBackwardsIterator(u8, .sequence) {
    return self.buffer.splitBackwardsSequence(delimiters);
}

/// Returns an iterator that iterates backwards over the slices of `buffer` that
/// are separated by any item in `delimiters`.
///
/// `splitBackwardsAny(u8, "abc,def||ghi", "|,")` will return slices
/// for "ghi", "", "def", "abc", null, in that order.
///
/// If none of `delimiters` exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub inline fn splitBackwardsAny(self: *Self, delimiters: []const u8) std.mem.SplitBackwardsIterator(u8, .any) {
    return self.buffer.splitBackwardsAny(delimiters);
}

/// Returns an iterator that iterates backwards over the slices of `buffer` that
/// are separated by `delimiter`.
///
/// `splitBackwardsScalar(u8, "abc|def||ghi", '|')` will return slices
/// for "ghi", "", "def", "abc", null, in that order.
///
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
pub inline fn splitBackwardsScalar(self: *Self, delimiter: u8) std.mem.SplitBackwardsIterator(u8, .scalar) {
    return self.buffer.splitBackwardsScalar(delimiter);
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
pub inline fn tokenizeAny(self: *Self, delimiters: []const u8) std.mem.TokenIterator(u8, .any) {
    return self.buffer.tokenizeAny(delimiters);
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
pub inline fn tokenizeSequence(self: *Self, delimiter: []const u8) std.mem.TokenIterator(u8, .sequence) {
    return self.buffer.tokenizeSequence(delimiter);
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
pub inline fn tokenizeScalar(self: *Self, delimiter: u8) std.mem.TokenIterator(u8, .scalar) {
    return self.buffer.tokenizeScalar(delimiter);
}

/// Lowercase all runes in the buffer
pub noinline fn toLowercase(self: *Self) void {
    var i: usize = 0;
    while (i < self.buffer.len) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (size == 1) self.buffer.ptr[i] = std.ascii.toLower(self.buffer.ptr[i]);
        i += size;
    }
}

/// Uppercase all runes in the buffer
pub noinline fn toUppercase(self: *Self) void {
    var i: usize = 0;
    while (i < self.buffer.len) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (size == 1) self.buffer.ptr[i] = std.ascii.toUpper(self.buffer.ptr[i]);
        i += size;
    }
}

/// Clear the whole buffer
pub inline fn clear(self: *Self) void {
    self.buffer.clear();
}

/// Clear and free the whole buffer
pub inline fn clearAndFree(self: *Self) void {
    self.buffer.clearAndFree();
}

/// Shrink the whole buffer
pub inline fn shrink(self: *Self) !void {
    try self.buffer.shrink();
}

pub noinline fn pop(self: *Self) ?[]const u8 {
    if (self.buffer.len == 0) return null;

    var i: usize = 0;
    while (i < self.buffer.len) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (i + size >= self.buffer.len) break;
        i += size;
    }

    const ret = self.buffer.ptr[i..self.buffer.len];
    self.buffer.len -= (self.buffer.len - i);
    return ret;
}

/// Get a rune at given index
pub noinline fn runeAt(self: *Self, index: usize) ?[]const u8 {
    if (self.utf8Position(index, true)) |i| {
        const size = utf8Size(self.buffer.ptr[i]);
        return self.buffer.ptr[i..(i + size)];
    }
    return null;
}

/// For each rune in the buffer
pub inline fn forEach(self: *Self, eachFn: *const fn ([]const u8) void) void {
    var iter = self.iterator();
    while (iter.next()) |item| {
        eachFn(item);
    }
}

/// Find the position index of the given string
pub inline fn find(self: *Self, str: []const u8) ?usize {
    return self.findOn(str, 0);
}

/// Find the position index of the given string
pub inline fn findOn(self: *Self, str: []const u8, pos: usize) ?usize {
    if (pos > self.buffer.len) return null;
    const index = std.mem.indexOf(u8, self.buffer.ptr[pos..self.buffer.len], str);
    if (index) |i| {
        return self.utf8Position(i, false);
    }
    return null;
}

/// Check if the string does contain in the buffer
pub inline fn contains(self: *Self, str: []const u8) bool {
    if (str.len == 0) return false;

    if (self.findOn(str, 0)) |_| {
        return true;
    }
    return false;
}

pub inline fn containsStartWith(self: *Self, str: []const u8, pos: usize) bool {
    if (str.len == 0) return false;

    if (self.findOn(str, pos)) |_| {
        return true;
    }
    return false;
}

/// Check if the buffer content does start with given string
pub inline fn startWith(self: *Self, str: []const u8) bool {
    if (str.len == 0) return false;

    if (self.find(str)) |pos| {
        return pos == 0;
    }
    return false;
}

/// Check if the buffer content does end with given string
pub inline fn endWith(self: *Self, str: []const u8) bool {
    if (str.len == 0) return false;

    if (self.find(str)) |pos| {
        return pos == self.buffer.len - str.len;
    }
    return false;
}

/// Compare the buffer content with given string
pub inline fn compare(self: *Self, str: []const u8) bool {
    return self.buffer.compare(str);
}

pub inline fn eql(self: *Self, dst: *const Self) bool {
    return std.mem.eql(self.buffer.ptr, dst.buffer.ptr);
}

/// Clone the content of buffer using a given allocator
pub inline fn cloneUsingAllocator(self: *Self, allocator: std.mem.Allocator) !Self {
    return Self{ .buffer = try self.buffer.cloneUsingAllocator(allocator) };
}

/// Clone the content of buffer using same allocator
pub inline fn clone(self: *Self) !Self {
    return Self{ .buffer = try self.buffer.clone() };
}

/// Copy the content into a array of bytes
pub inline fn copy(self: *Self) !?[]u8 {
    return try self.buffer.copy();
}

/// Retrieve the buffer bytes
pub inline fn bytes(self: *Self) []const u8 {
    return self.buffer.bytes();
}

/// Read the buffer bytes into a destination
inline fn read(self: *Self, dst: []u8) !usize {
    return self.bytesInto(dst);
}

/// Read the buffer bytes into a destination
pub inline fn bytesInto(self: *Self, dst: []const u8) !usize {
    try self.shrink();
    const bs = self.bytes();
    std.mem.copyForwards(u8, @constCast(dst), bs);
    return bs.len;
}

/// Retrive the bytes using an external allocator
pub inline fn bytesWithAllocator(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
    return try self.buffer.copyUsingAllocator(allocator);
}

/// Capacity of the buffer
pub inline fn capacity(self: *Self) usize {
    return self.buffer.cap;
}

/// Verify the buffer if is empty
pub inline fn isEmpty(self: *Self) bool {
    return self.buffer.len == 0;
}

/// Retrieve the raw length of teh buffer
pub inline fn rawLength(self: *Self) usize {
    return self.buffer.len;
}

/// Retrieve the length rune string
pub noinline fn length(self: *Self) usize {
    var l: usize = 0;
    var i: usize = 0;

    while (i < self.buffer.len) {
        i += utf8Size(self.buffer.ptr[i]);
        l += 1;
    }

    return l;
}

noinline fn utf8Position(self: *Self, index: usize, real: bool) ?usize {
    var i: usize = 0;
    var j: usize = 0;
    while (i < self.buffer.cap) {
        if (real) {
            if (j == index) return i;
        } else {
            if (i == index) return j;
        }
        i += utf8Size(self.buffer.ptr[i]);
        j += 1;
    }

    if (real) {
        if (j == index) return i;
    } else {
        if (i == index) return j;
    }

    return null;
}

// Reader and Writer functionality.
pub usingnamespace struct {
    pub const Writer = std.io.Writer(*Self, Buffer.Error, appendWrite);

    pub fn writer(self: *Self) Writer {
        return .{ .context = self };
    }

    fn appendWrite(self: *Self, m: []const u8) !usize {
        return try self.write(m);
    }
};

/// Checks if byte is part of UTF-8 character
inline fn isUTF8Byte(byte: u8) bool {
    return ((byte & 0x80) > 0) and (((byte << 1) & 0x80) == 0);
}

/// Returns the UTF-8 character's size
inline fn utf8Size(byte: u8) u3 {
    return std.unicode.utf8ByteSequenceLength(byte) catch {
        return 1;
    };
}

inline fn spliter(data: []const u8, delimiters: []const u8, index: usize) ?[]const u8 {
    var i: usize = 0;
    var block: usize = 0;
    var start: usize = 0;

    while (i < data.len) {
        const size = utf8Size(data.ptr[i]);
        if (size == delimiters.len) {
            if (std.mem.eql(u8, delimiters, data.ptr[i..(i + size)])) {
                if (block == index) return data.ptr[start..i];
                start = i + size;
                block += 1;
            }
        }

        i += size;
    }

    if (i >= data.len - 1 and block == index) {
        return data.ptr[start..data.len];
    }

    return null;
}

// Iterator support
pub usingnamespace struct {
    pub const Iterator = struct {
        sb: *Self,
        index: usize,

        pub fn next(it: *Iterator) ?[]const u8 {
            if (it.index >= it.sb.buffer.len) return null;
            const i = it.index;
            it.index += utf8Size(it.sb.buffer.ptr[i]);
            return it.sb.buffer.ptr[i..it.index];
        }

        pub fn nextBytes(it: *Iterator, size: usize) ?[]const u8 {
            if ((it.index + size) >= it.sb.buffer.len) return null;

            const i = it.index;
            it.index += size;
            return it.sb.buffer.ptr[i..it.index];
        }
    };

    pub fn iterator(self: *Self) Iterator {
        return Iterator{
            .sb = self,
            .index = 0,
        };
    }
};

const ArenaAllocator = std.heap.ArenaAllocator;
const assert = std.debug.assert;

test "Basic Usage" {
    // Use your favorite allocator
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var buffer = Self.init(arena.allocator());
    defer buffer.deinit();

    // Use functions provided
    try buffer.append("🔥 Hello!");
    _ = buffer.pop();
    try buffer.append(", World 🔥");

    // Success!
    assert(buffer.compare("🔥 Hello, World 🔥"));
}

test "Format Usage" {
    // Use your favorite allocator
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var buffer = Self.init(arena.allocator());
    defer buffer.deinit();

    // Use functions provided
    try buffer.appendf("🔥 Hello {s} World 🔥", .{"Ionel"});

    // Success!
    assert(buffer.compare("🔥 Hello Ionel World 🔥"));
}

test "UTF8 Buffer Tests" {
    // Allocator for the String
    const page_allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    var buffer = Self.init(arena.allocator());
    defer buffer.deinit();

    // truncate
    buffer.clear();
    assert(buffer.capacity() == 0);
    assert(buffer.rawLength() == 0);

    // append
    try buffer.append("A");
    try buffer.append("\u{5360}");
    try buffer.append("💯");
    try buffer.append("Hello🔥");

    assert(buffer.rawLength() == 17);

    // pop & length
    assert(buffer.length() == 9);
    assert(std.mem.eql(u8, buffer.pop().?, "🔥"));
    assert(buffer.length() == 8);
    assert(std.mem.eql(u8, buffer.pop().?, "o"));
    assert(buffer.length() == 7);

    // str & cmp
    assert(buffer.compare("A\u{5360}💯Hell"));
    assert(buffer.compare(buffer.bytes()));

    // charAt
    assert(std.mem.eql(u8, buffer.runeAt(2).?, "💯"));
    assert(std.mem.eql(u8, buffer.runeAt(1).?, "\u{5360}"));
    assert(std.mem.eql(u8, buffer.runeAt(0).?, "A"));

    // insert
    try buffer.insertAt("🔥", 1);
    assert(std.mem.eql(u8, buffer.runeAt(1).?, "🔥"));
    assert(buffer.compare("A🔥\u{5360}💯Hell"));

    // find
    assert(buffer.find("🔥").? == 1);
    assert(buffer.find("💯").? == 3);
    assert(buffer.find("Hell").? == 4);

    // remove & removeRange
    try buffer.removeRange(0, 3);
    assert(buffer.compare("💯Hell"));
    try buffer.removeFrom(buffer.rawLength() - 1);
    assert(buffer.compare("💯Hel"));

    const whitelist = [_]u8{ ' ', '\t', '\n', '\r' };

    // trimStart
    try buffer.insertAt("      ", 0);
    buffer.trimStart(whitelist[0..]);
    assert(buffer.compare("💯Hel"));

    // trimEnd
    _ = try buffer.append("lo💯\n      ");
    buffer.trimEnd(whitelist[0..]);
    assert(buffer.compare("💯Hello💯"));

    // clone
    var testStr = try buffer.clone();
    defer testStr.deinit();
    assert(testStr.compare(buffer.bytes()));

    // reverse
    buffer.reverse();
    assert(buffer.compare("💯olleH💯"));
    buffer.reverse();
    assert(buffer.compare("💯Hello💯"));

    // repeat
    try buffer.repeat(2);
    assert(buffer.compare("💯Hello💯💯Hello💯💯Hello💯"));

    // isEmpty
    assert(!buffer.isEmpty());

    // split
    assert(std.mem.eql(u8, buffer.splitBlockAt("💯", 0).?, ""));
    assert(std.mem.eql(u8, buffer.splitBlockAt("💯", 1).?, "Hello"));
    assert(std.mem.eql(u8, buffer.splitBlockAt("💯", 2).?, ""));
    assert(std.mem.eql(u8, buffer.splitBlockAt("💯", 3).?, "Hello"));
    assert(std.mem.eql(u8, buffer.splitBlockAt("💯", 5).?, "Hello"));
    assert(std.mem.eql(u8, buffer.splitBlockAt("💯", 6).?, ""));

    var splitStr = Self.init(arena.allocator());
    defer splitStr.deinit();

    try splitStr.append("variable='value'");
    assert(std.mem.eql(u8, splitStr.splitBlockAt("=", 0).?, "variable"));
    assert(std.mem.eql(u8, splitStr.splitBlockAt("=", 1).?, "'value'"));

    // splitToString
    var newSplit = try splitStr.splitBlockAtAsCopy("=", 0);
    assert(newSplit != null);
    defer newSplit.?.deinit();

    assert(std.mem.eql(u8, newSplit.?.bytes(), "variable"));

    // toLowercase & toUppercase
    buffer.toUppercase();
    assert(buffer.compare("💯HELLO💯💯HELLO💯💯HELLO💯"));
    buffer.toLowercase();
    assert(buffer.compare("💯hello💯💯hello💯💯hello💯"));

    // substr
    var subStr = try buffer.substractRange(0, 7);
    defer subStr.deinit();
    assert(subStr.compare("💯hello💯"));

    // clear
    buffer.clear();
    const cap = buffer.capacity();
    assert(buffer.rawLength() == 0);
    assert(buffer.capacity() == cap);

    // writer
    const writer = buffer.writer();
    const len = try writer.write("This is a Test!");
    assert(len == 15);

    // owned
    const mySlice = try buffer.copy();
    assert(std.mem.eql(u8, mySlice.?, "This is a Test!"));
    arena.allocator().free(mySlice.?);

    // Iterator
    var i: usize = 0;
    var iter = buffer.iterator();
    while (iter.next()) |ch| {
        if (i == 0) {
            assert(std.mem.eql(u8, "T", ch));
        }
        i += 1;
    }

    assert(i == buffer.length());

    // Replace
    buffer.clear();
    try buffer.append("💯Hello💯");
    assert(buffer.compare("💯Hello💯"));

    assert(try buffer.replaceFirst("💯", "++++++++++"));
    assert(buffer.compare("++++++++++Hello💯"));

    assert(!try buffer.replaceFirst("Hello1", "unknown"));

    assert(try buffer.replaceLast("💯", "1"));
    assert(buffer.compare("++++++++++Hello1"));

    assert(!try buffer.replaceLast("💯", "unknown"));

    assert(try buffer.replaceAll("++++++++++", "💯"));
    assert(try buffer.replaceAll("1", "💯"));
    assert(buffer.compare("💯Hello💯"));

    // Remove
    buffer.clear();
    try buffer.append("💯Hello💯 ==== 💯Hello💯");
    assert(buffer.compare("💯Hello💯 ==== 💯Hello💯"));

    assert(try buffer.removeFirst("💯"));
    assert(buffer.compare("Hello💯 ==== 💯Hello💯"));

    assert(try buffer.removeLast("💯"));
    assert(buffer.compare("Hello💯 ==== 💯Hello"));

    assert(try buffer.removeAll("💯"));
    assert(buffer.compare("Hello ==== Hello"));

    assert(!try buffer.removeAll("💯"));
    assert(buffer.compare("Hello ==== Hello"));

    // contains
    buffer.clear();
    try buffer.append("💯Hello💯 ==== 💯Hello💯");
    assert(buffer.compare("💯Hello💯 ==== 💯Hello💯"));
    assert(buffer.contains("= 💯"));
    assert(!buffer.contains("= 💯 ="));

    // appendN
    buffer.clear();
    try buffer.append("💯Hello💯");
    assert(buffer.compare("💯Hello💯"));

    try buffer.appendN("VaselicaPuiu", 8);
    assert(buffer.compare("💯Hello💯Vaselica"));
}

test "UTF8 Buffer Split Tests" {
    // Allocator for the String
    const page_allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    var buffer = Self.init(arena.allocator());
    defer buffer.deinit();

    try buffer.append("💯Hello💯💯Hello💯💯Hello💯");

    var iter = buffer.splitSequence("💯");

    assert(std.mem.eql(u8, "", iter.next().?));
    assert(std.mem.eql(u8, "Hello", iter.next().?));
    assert(std.mem.eql(u8, "", iter.next().?));
    assert(std.mem.eql(u8, "Hello", iter.next().?));
    assert(std.mem.eql(u8, "", iter.next().?));
    assert(std.mem.eql(u8, "Hello", iter.next().?));
    assert(std.mem.eql(u8, "", iter.next().?));
}

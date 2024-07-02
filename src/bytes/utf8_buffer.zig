const std = @import("std");
const builtin = @import("builtin");

const Buffer = @import("buffer.zig");

const Self = @This();

buffer: Buffer,

pub fn initWithBuffer(buffer: Buffer) Self {
    return Self{ .buffer = buffer };
}

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{ .buffer = Buffer.init(allocator) };
}

pub fn initWithFactor(allocator: std.mem.Allocator, factor: u4) Self {
    return Self{ .buffer = Buffer.initWithFactor(allocator, factor) };
}

pub fn initWithCapacity(allocator: std.mem.Allocator, size: usize) !Self {
    var d = init(allocator);
    errdefer d.deinit();

    try d.buffer.resize(size);
    return d;
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
}

pub fn appendN(self: *Self, array: []const u8, numOfChars: usize) !void {
    try self.insertAtWithLength(self.buffer.len, array, numOfChars);
}

pub fn append(self: *Self, array: []const u8) !void {
    try self.insertAtWithLength(self.buffer.len, array, array.len);
}

pub fn insertAt(self: *Self, array: []const u8, index: usize) !void {
    try self.insertAtWithLength(index, array, array.len);
}

fn insertAtWithLength(self: *Self, index: usize, array: []const u8, len: usize) !void {
    if (len == 0) return;

    const numberOfChars = if (len > array.len) array.len else len;

    // Make sure buffer has enough space
    if (self.buffer.len + numberOfChars > self.buffer.cap) {
        try self.buffer.resize((self.buffer.len + numberOfChars) * self.buffer.factor);
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

pub fn rangeBytes(self: *Self, start: usize, end: usize) ![]const u8 {
    return self.buffer.rangeBytes(start, end);
}

pub fn fromBytes(self: *Self, start: usize) ![]const u8 {
    self.buffer.fromBytes(start);
}

pub fn appendf(self: *Self, comptime format: []const u8, args: anytype) !void {
    return self.buffer.print(format, args);
}

pub fn write(self: *Self, array: []const u8) !usize {
    return self.buffer.write(array);
}

pub fn print(self: *Self, comptime format: []const u8, args: anytype) !void {
    return self.buffer.print(format, args);
}

pub fn repeat(self: *Self, n: usize) !void {
    try self.buffer.repeat(n);
}

const Direction = enum(u1) {
    first = 0,
    last,
};

fn replace(self: *Self, index: usize, src: []const u8, dst: []const u8) !void {
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

pub fn replaceLast(self: *Self, src: []const u8, dst: []const u8) !bool {
    if (std.mem.lastIndexOfLinear(u8, self.buffer.ptr[0..self.buffer.len], src)) |pos| {
        try self.replace(pos, src, dst);
        return true;
    }
    return false;
}

pub fn replaceFirst(self: *Self, src: []const u8, dst: []const u8) !bool {
    if (std.mem.indexOf(u8, self.buffer.ptr[0..self.buffer.len], src)) |pos| {
        try self.replace(pos, src, dst);
        return true;
    }
    return false;
}

pub fn replaceAll(self: *Self, src: []const u8, dst: []const u8) !bool {
    return self.replaceAllFromPos(0, src, dst);
}

pub fn replaceAllFromPos(self: *Self, startPos: usize, src: []const u8, dst: []const u8) !bool {
    var pos: usize = startPos;
    var found = false;
    while (std.mem.indexOf(u8, self.buffer.ptr[pos..self.buffer.len], src)) |index| {
        try self.replace(pos + index, src, dst);
        found = true;
        pos += index + dst.len;
    }
    return found;
}

pub fn removeLast(self: *Self, src: []const u8) !bool {
    if (std.mem.lastIndexOfLinear(u8, self.buffer.ptr[0..self.buffer.len], src)) |index| {
        try self.replace(index, src, "");
        return true;
    }

    return false;
}

pub fn removeFirst(self: *Self, src: []const u8) !bool {
    if (std.mem.indexOf(u8, self.buffer.ptr[0..self.buffer.len], src)) |index| {
        try self.replace(index, src, "");
        return true;
    }

    return false;
}

pub fn removeAll(self: *Self, src: []const u8) !bool {
    return self.replaceAll(src, "");
}

pub fn removeFrom(self: *Self, pos: usize) !void {
    try self.removeRange(pos, self.buffer.len);
}

pub fn removeEnd(self: *Self, len: usize) !void {
    try self.removeRange(self.buffer.len - len, self.buffer.len);
}

pub fn removeStart(self: *Self, len: usize) !void {
    try self.removeRange(0, len);
}

pub fn removeRange(self: *Self, start: usize, end: usize) !void {
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

pub fn reverse(self: *Self) void {
    var i: usize = 0;
    while (i < self.buffer.len) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (size > 1) std.mem.reverse(u8, self.buffer.ptr[i..(i + size)]);
        i += size;
    }

    std.mem.reverse(u8, self.buffer.ptr[0..self.buffer.len]);
}

pub fn substract(self: *Self, start: usize, end: usize) !Self {
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

pub fn trimStart(self: *Self, cut: []const u8) void {
    var i: usize = 0;
    while (i < self.buffer.len) : (i += 1) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (size > 1 or !in(self.buffer.ptr[i], cut)) break;
    }

    if (self.utf8Position(i, false)) |k| {
        self.removeRange(0, k) catch {};
    }
}
fn in(byte: u8, arr: []const u8) bool {
    var i: usize = 0;
    while (i < arr.len) : (i += 1) {
        if (arr[i] == byte) return true;
    }

    return false;
}

/// Trims all characters at the end.
pub fn trimEnd(self: *Self, cut: []const u8) void {
    self.reverse();
    self.trimStart(cut);
    self.reverse();
}

pub fn trim(self: *Self, cut: []const u8) void {
    self.trimStart(cut);
    self.trimEnd(cut);
}

pub fn split(self: *Self, delimiters: []const u8, index: usize) ?[]const u8 {
    var i: usize = 0;
    var block: usize = 0;
    var start: usize = 0;

    while (i < self.buffer.len) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (size == delimiters.len) {
            if (std.mem.eql(u8, delimiters, self.buffer.ptr[i..(i + size)])) {
                if (block == index) return self.buffer.ptr[start..i];
                start = i + size;
                block += 1;
            }
        }

        i += size;
    }

    if (i >= self.buffer.len - 1 and block == index) {
        return self.buffer.ptr[start..self.buffer.len];
    }

    return null;
}

pub fn splitAsCopy(self: *Self, delimiters: []const u8, index: usize) !?Self {
    if (self.split(delimiters, index)) |block| {
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
pub fn splitSequence(self: *Self, delimiters: []const u8) std.mem.SplitIterator(u8, .sequence) {
    assert(delimiters.len != 0);
    return .{
        .index = 0,
        .buffer = self.buffer.bytes(),
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
        .buffer = self.buffer.bytes(),
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
        .buffer = self.buffer.bytes(),
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
        .index = self.buffer.len,
        .buffer = self.buffer.bytes(),
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
        .index = self.buffer.len,
        .buffer = self.buffer.bytes(),
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
        .index = self.buffer.len,
        .buffer = self.buffer.bytes(),
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
        .buffer = self.buffer.bytes(),
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
        .buffer = self.buffer.bytes(),
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
        .buffer = self.buffer.bytes(),
        .delimiter = delimiter,
    };
}

pub fn toLowercase(self: *Self) void {
    var i: usize = 0;
    while (i < self.buffer.len) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (size == 1) self.buffer.ptr[i] = std.ascii.toLower(self.buffer.ptr[i]);
        i += size;
    }
}

pub fn toUppercase(self: *Self) void {
    var i: usize = 0;
    while (i < self.buffer.len) {
        const size = utf8Size(self.buffer.ptr[i]);
        if (size == 1) self.buffer.ptr[i] = std.ascii.toUpper(self.buffer.ptr[i]);
        i += size;
    }
}

pub fn clear(self: *Self) void {
    self.buffer.clear();
}

pub fn shrink(self: *Self) !void {
    try self.buffer.shrink();
}

pub fn pop(self: *Self) ?[]const u8 {
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

pub fn runeAt(self: *Self, index: usize) ?[]const u8 {
    if (self.utf8Position(index, true)) |i| {
        const size = utf8Size(self.buffer.ptr[i]);
        return self.buffer.ptr[i..(i + size)];
    }
    return null;
}

pub fn forEach(self: *Self, eachFn: *const fn ([]const u8) void) void {
    var iter = self.iterator();
    while (iter.next()) |item| {
        eachFn(item);
    }
}

pub fn find(self: *Self, array: []const u8) ?usize {
    const index = std.mem.indexOf(u8, self.buffer.ptr[0..self.buffer.len], array);
    if (index) |i| {
        return self.utf8Position(i, false);
    }
    return null;
}

pub fn contains(self: *Self, array: []const u8) bool {
    if (array.len == 0) return false;

    if (self.find(array)) |_| {
        return true;
    }
    return false;
}

pub fn startWith(self: *Self, array: []const u8) bool {
    if (array.len == 0) return false;

    if (self.find(array)) |pos| {
        return pos == 0;
    }
    return false;
}

pub fn endWith(self: *Self, array: []const u8) bool {
    if (array.len == 0) return false;

    if (self.find(array)) |pos| {
        return pos == self.buffer.len - array.len;
    }
    return false;
}

pub fn compare(self: *Self, array: []const u8) bool {
    return self.buffer.compare(array);
}

pub fn cloneUsingAllocator(self: *Self, allocator: std.mem.Allocator) !Self {
    return Self{ .buffer = try self.buffer.cloneUsingAllocator(allocator) };
}

pub fn clone(self: *Self) !Self {
    return Self{ .buffer = try self.buffer.clone() };
}

pub fn copy(self: *Self) !?[]u8 {
    return try self.buffer.copy();
}

pub fn bytes(self: *Self) []const u8 {
    return self.buffer.bytes();
}

fn read(self: *Self, dst: []u8) !usize {
    return self.read(dst);
}

pub fn bytesInto(self: *Self, dst: []const u8) !usize {
    try self.shrink();
    const bs = self.bytes();
    std.mem.copyForwards(u8, @constCast(dst), bs);
    return bs.len;
}

pub fn bytesWithAllocator(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
    return try self.buffer.copyUsingAllocator(allocator);
}

pub fn capacity(self: *Self) usize {
    return self.buffer.cap;
}

pub inline fn isEmpty(self: *Self) bool {
    return self.buffer.len == 0;
}

pub fn rawLength(self: *Self) usize {
    return self.buffer.len;
}

pub fn length(self: *Self) usize {
    var l: usize = 0;
    var i: usize = 0;

    while (i < self.buffer.len) {
        i += utf8Size(self.buffer.ptr[i]);
        l += 1;
    }

    return l;
}

fn utf8Position(self: *Self, index: usize, real: bool) ?usize {
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
    pub const Reader = std.io.Reader(*Self, Buffer.Error, readFn);

    pub fn reader(self: *Self) Reader {
        return .{ .context = self };
    }

    fn readFn(self: *Self, m: []u8) !usize {
        return try self.read(m);
    }

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
const eql = std.mem.eql;
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
    assert(eql(u8, buffer.pop().?, "🔥"));
    assert(buffer.length() == 8);
    assert(eql(u8, buffer.pop().?, "o"));
    assert(buffer.length() == 7);

    // str & cmp
    assert(buffer.compare("A\u{5360}💯Hell"));
    assert(buffer.compare(buffer.bytes()));

    // charAt
    assert(eql(u8, buffer.runeAt(2).?, "💯"));
    assert(eql(u8, buffer.runeAt(1).?, "\u{5360}"));
    assert(eql(u8, buffer.runeAt(0).?, "A"));

    // insert
    try buffer.insertAt("🔥", 1);
    assert(eql(u8, buffer.runeAt(1).?, "🔥"));
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
    assert(eql(u8, buffer.split("💯", 0).?, ""));
    assert(eql(u8, buffer.split("💯", 1).?, "Hello"));
    assert(eql(u8, buffer.split("💯", 2).?, ""));
    assert(eql(u8, buffer.split("💯", 3).?, "Hello"));
    assert(eql(u8, buffer.split("💯", 5).?, "Hello"));
    assert(eql(u8, buffer.split("💯", 6).?, ""));

    var splitStr = Self.init(arena.allocator());
    defer splitStr.deinit();

    try splitStr.append("variable='value'");
    assert(eql(u8, splitStr.split("=", 0).?, "variable"));
    assert(eql(u8, splitStr.split("=", 1).?, "'value'"));

    // splitToString
    var newSplit = try splitStr.splitAsCopy("=", 0);
    assert(newSplit != null);
    defer newSplit.?.deinit();

    assert(eql(u8, newSplit.?.bytes(), "variable"));

    // toLowercase & toUppercase
    buffer.toUppercase();
    assert(buffer.compare("💯HELLO💯💯HELLO💯💯HELLO💯"));
    buffer.toLowercase();
    assert(buffer.compare("💯hello💯💯hello💯💯hello💯"));

    // substr
    var subStr = try buffer.substract(0, 7);
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
    assert(eql(u8, mySlice.?, "This is a Test!"));
    arena.allocator().free(mySlice.?);

    // Iterator
    var i: usize = 0;
    var iter = buffer.iterator();
    while (iter.next()) |ch| {
        if (i == 0) {
            assert(eql(u8, "T", ch));
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

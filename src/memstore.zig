const std = @import("std");
const builtin = @import("builtin");

const SkipList = @import("list/skiplist.zig").SkipList;

const Self = @This();

pub const Type = enum(u4) {
    plain = 0,
    gzip = 1,
};
pub const Options = struct {
    type: Type = .gzip,
};

const ValueStruct = @import("cmp/wrapper.zig").Wrapper(?[]const u8);

skiplist: SkipList([]const u8, ValueStruct),

pub fn init(allocator: std.mem.Allocator) !Self {
    return Self{
        .skiplist = try SkipList([]const u8, ValueStruct).init(allocator, .{}),
    };
}

pub fn add(self: *Self, key: []const u8, value: []const u8) ?[]const u8 {
    _ = self.upsertInternal(key, value, true);
}

fn upsertInternal(self: *Self, key: []const u8, value: []const u8, nothingIfKeyExist: bool) ?[]const u8 {
    const element = self.skiplist.get(key);
    if (element) |item| {
        if (nothingIfKeyExist) {
            return null;
        } else {
            const prevValue = item.value;
            item.value = value;
            return prevValue;
        }
    } else {
        _ = self.skiplist.insert(key, ValueStruct.fromLiteral(&value));
    }
}

pub fn contains(self: *Self, key: []const u8) bool {
    if (self.skiplist.get(key)) |item| if (item.value != null) {
        return true;
    };
    return false;
}

pub fn get(self: *Self, key: []const u8) ?[]const u8 {
    const element = self.skiplist.get(key);

    if (element) |item| {
        if (item.value) |v| {
            return v;
        }
        return null;
    } else {
        return null;
    }
}

pub fn upsert(self: *Self, key: []const u8, value: []const u8) ?[]const u8 {
    return self.upsertInternal(key, value, false);
}

pub fn delete(self: *Self, key: []const u8) ?[]const u8 {
    return self.deleteInternal(key);
}

pub fn deleteIfExists(self: *Self, key: []const u8) ?[]const u8 {
    return self.deleteInternal(key);
}

fn deleteInternal(self: *Self, key: []const u8) ?[]const u8 {
    if (self.skiplist.get(key)) |item| {
        const prevValue = item.value;
        item.value = null;
        return prevValue;
    }

    return null;
}

pub fn tombstone(self: *Self, key: []const u8) ?[]const u8 {
    if (self.skiplist.get(key)) |item| {
        const prevValue = item.value;
        item.value = null;
        return prevValue;
    } else {
        _ = self.skiplist.insert(key, ValueStruct.fromLiteral(null));
        return null;
    }
}

pub fn estimatedSizeInBytes(self: *Self) u128 {
    // we account for ~15% overhead
    const v = 1.15 * @as(f64, @floatFromInt(self.size()));
    return @as(u128, @intFromFloat(v));
}

pub fn size(self: *Self) u128 {
    return self.skiplist.contentSize(.bytes);
}

pub fn flush(self: *Self, filepath: []const u8, options: Options) !void {
    const file = try std.fs.cwd().createFile(
        filepath,
        .{ .read = false },
    );
    errdefer {
        file.close();
        std.fs.cwd().deleteFile(filepath);
    }
    defer file.close();

    var raw_content = std.ArrayList(u8).init(self.skiplist.allocator);
    errdefer raw_content.deinit();

    const handler = BinaryWritingHandler.init(raw_content);
    self.skiplist.forEachWithContext(BinaryWritingHandler, handler, handler.f);

    const bytes_content = raw_content.toOwnedSlice();
    errdefer self.skiplist.allocator.free(bytes_content);
    defer self.skiplist.allocator.free(bytes_content);

    switch (options.type) {
        inline .plain => {
            try file.writeAll(bytes_content);
        },
        inline .gzip => {
            var in_stream = std.io.fixedBufferStream(bytes_content);

            const fbs = std.ArrayList(u8).init(self.skiplist.allocator);
            try std.compress.gzip.compress(in_stream.reader(), fbs.writer());

            const gziped = try fbs.toOwnedSlice();
            errdefer self.skiplist.allocator.free(gziped);
            defer self.skiplist.allocator.free(gziped);
            try file.writeAll(gziped);
        },
    }
}

const BinaryWritingHandler = struct {
    const HSelf = @This();

    content: std.ArrayList(u8),

    pub fn init(arr: std.ArrayList(u8)) HSelf {
        return HSelf{
            .content = arr,
        };
    }

    pub fn f(hself: HSelf, key: []const u8, value: ValueStruct) void {
        _ = hself;
        std.debug.print("{}:{} \n", .{ value, key });
    }
};

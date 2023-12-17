const std = @import("std");
const xstd = @import("xstd");
const zip = xstd.archive.zip;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const data = @embedFile("zoneinfo.zip.gz");

    var in_stream = std.io.fixedBufferStream(data);

    var gzip_stream = try std.compress.gzip.decompress(allocator, in_stream.reader());
    defer gzip_stream.deinit();

    const buf = try gzip_stream.reader().readAllAlloc(allocator, std.math.maxInt(usize));

    var entries = try zip.reader.Entries(allocator, std.io.fixedBufferStream(buf));
    defer entries.deinit();

    var filters = std.ArrayList([]const u8).init(allocator);
    defer filters.deinit();

    try filters.append("New_York");
    try filters.append("Berlin");

    const Collector = struct {
        const Self = @This();

        pub const GenericContent = xstd.archive.GenericContent(*Self, receive);

        arr: std.ArrayList([]const u8),

        pub fn init(all: std.mem.Allocator) Self {
            return Self{ .arr = std.ArrayList([]const u8).init(all) };
        }

        pub fn receive(self: *Self, filename: []const u8, fileContent: []const u8) !void {
            _ = filename;
            var buffer: [500 * 1024]u8 = undefined;
            std.mem.copyBackwards(u8, &buffer, fileContent);
            try self.arr.append(buffer[0..fileContent.len]);
        }

        pub fn content(self: *Self) GenericContent {
            return .{ .context = self };
        }
    };

    var collector = Collector.init(allocator);

    _ = try entries.readWithFilters(filters, collector.content().receiver());

    for (collector.arr.items) |item| {
        std.debug.print("\n-----------------------------------------\n", .{});
        std.debug.print("\n{s}\n", .{item});
    }

    // --------------- Extract the Extra Fields ----------------------------
    var ef = ExtraField.init();
    for (entries.central_directory.headers.items) |item| {
        try item.extraFields(ef.generic().handler());
    }
}

const ExtraField = struct {
    const Self = @This();

    pub const GenericExtraField = zip.types.GenericExtraField(*Self, exec);

    pub fn init() Self {
        return Self{};
    }

    pub fn exec(self: *Self, headerId: u16, args: *const anyopaque) !void {
        switch (headerId) {
            zip.extrafields.ExtendedTimestamp.CODE => {
                const ptr: *const zip.extrafields.ExtendedTimestamp = @alignCast(@ptrCast(args));
                std.debug.print("ExtendedTimestamp = {}, {}, {}\n", .{ ptr.data_size, ptr.flags, ptr.tolm });
            },
            zip.extrafields.ZIPUNIX3rdGenerationGenericUIDGIDInfo.CODE => {
                const ptr: *const zip.extrafields.ZIPUNIX3rdGenerationGenericUIDGIDInfo = @alignCast(@ptrCast(args));
                std.debug.print("ZIPUNIX3rdGenerationGenericUIDGIDInfo = {}, {}, {}, {}, {}, {}\n", .{ ptr.data_size, ptr.version, ptr.uid_size, ptr.uid, ptr.gid_size, ptr.gid });
            },
            else => {},
        }

        _ = self;
    }

    pub fn generic(self: *Self) GenericExtraField {
        return GenericExtraField{ .context = self };
    }
};

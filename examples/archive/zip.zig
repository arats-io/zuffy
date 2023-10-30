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

        pub const Error = error{OutOfMemory};
        pub const Receiver = xstd.archive.GenericReceiver(*Self, Error, receive);

        arr: std.ArrayList([]const u8),

        pub fn init(all: std.mem.Allocator) Self {
            return Self{ .arr = std.ArrayList([]const u8).init(all) };
        }

        pub fn receive(self: *Self, filename: []const u8, content: []const u8) Error!void {
            _ = filename;
            var buffer: [500 * 1024]u8 = undefined;
            std.mem.copy(u8, &buffer, content);
            try self.arr.append(buffer[0..content.len]);
        }

        pub fn receiver(self: *Self) Receiver {
            return .{ .context = self };
        }
    };

    var collector = Collector.init(allocator);

    _ = try entries.readWithFilters(filters, collector.receiver());

    for (collector.arr.items) |item| {
        std.debug.print("\n-----------------------------------------\n", .{});
        std.debug.print("\n{s}\n", .{item});
    }
}

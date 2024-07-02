const std = @import("std");
const xstd = @import("xstd");
const zip = xstd.archive.zip;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var fbs = xstd.bytes.FlexibleBufferStream.init(arena.allocator());
    defer fbs.deinit();

    var zipFile = xstd.archive.zip.fromBufferStream(allocator, fbs);
    defer zipFile.deinit();

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

    _ = try zipFile.deccompress(collector.content().receiver());

    for (collector.arr.items) |item| {
        std.debug.print("\n-----------------------------------------\n", .{});
        std.debug.print("\n{s}\n", .{item});
    }
}

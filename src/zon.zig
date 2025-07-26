const std = @import("std");
const strings = @import("strings.zig");

pub const Manifest = struct { version: []const u8, minimum_zig_version: []const u8 };

pub fn parse(T: type, allocator: std.mem.Allocator, file_path: []const u8) !T {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    errdefer file.close();

    var buffer: [10 * 1024 * 1024]u8 = undefined;
    const size = try file.preadAll(&buffer, 0) + 1;
    buffer[size - 1] = 0;

    return try std.zon.parse.fromSlice(Manifest, allocator, buffer[0 .. size - 1 :0], null, .{ .ignore_unknown_fields = true });
}

pub fn semanticVersionDefault(allocator: std.mem.Allocator) !std.SemanticVersion {
    return try semanticVersion(allocator, "build.zig.zon");
}

pub fn semanticVersion(allocator: std.mem.Allocator, file_path: []const u8) !std.SemanticVersion {
    const zon = try parse(Manifest, allocator, file_path);
    return try std.SemanticVersion.parse(zon.version);
}

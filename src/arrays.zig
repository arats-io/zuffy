const std = @import("std");
const mem = std.mem;

pub fn fromHexBytes(comptime size: usize, input: []const u8) ![]u8 {
    var srcBytes: [size]u8 = undefined;
    return try std.fmt.hexToBytes(&srcBytes, input);
}

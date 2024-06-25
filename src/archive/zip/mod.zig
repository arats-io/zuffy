const std = @import("std");
const archive = @import("archive.zig");

pub const extrafield = @import("extra_field.zig");
pub const types = @import("types.zig");

pub const Archive = archive.Archive;
pub fn fromBufferStream(allocator: std.mem.Allocator, stream: anytype) Archive(@TypeOf(stream)) {
    return Archive(@TypeOf(stream)).init(allocator, stream);
}

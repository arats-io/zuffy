context: *const anyopaque,
receiveFn: *const fn (context: *const anyopaque, filname: []const u8, content: []const u8) anyerror!void,

/// Returns the uncompressed content of un archive.
/// If the number of bytes read is 0, it means end of stream.
/// End of stream is not an error condition.
pub fn entryContent(self: Self, filname: []const u8, content: []const u8) anyerror!void {
    return self.receiveFn(self.context, filname, content);
}

const Self = @This();

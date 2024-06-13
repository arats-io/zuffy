context: *const anyopaque,
receiveFn: *const fn (context: *const anyopaque, filname: []const u8, content: []const u8) anyerror!void,

/// Returns the uncompressed content of un archive.
pub fn entryContent(self: Self, filname: []const u8, content: []const u8) anyerror!void {
    return self.receiveFn(self.context, filname, content);
}

const Self = @This();

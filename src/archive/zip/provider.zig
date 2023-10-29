context: *const anyopaque,
provideFn: fn (context: *const anyopaque, filname: []const u8, content: []const u8) Error!void,

pub const Error = anyerror;

/// Returns the number of bytes read. It may be less than buffer.len.
/// If the number of bytes read is 0, it means end of stream.
/// End of stream is not an error condition.
pub fn provide(self: Self, filname: []const u8, content: []const u8) anyerror!void {
    return self.readFn(self.context, filname, content);
}

const Self = @This();

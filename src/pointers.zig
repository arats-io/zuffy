pub inline fn fromOpaque(ptr: ?*anyopaque, comptime T: type) T {
    return @ptrCast(@alignCast(ptr));
}

pub inline fn fromConstOpaque(ptr: ?*anyopaque, comptime T: type) T {
    return @constCast(@ptrCast(@alignCast(ptr)));
}

pub fn fromOpaque(ptr: ?*anyopaque, comptime T: type) T {
    return @ptrCast(@alignCast(ptr));
}

pub fn fromConstOpaque(ptr: ?*anyopaque, comptime T: type) T {
    return @constCast(fromOpaque(ptr, T));
}

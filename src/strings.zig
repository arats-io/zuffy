const std = @import("std");

pub const Error = error{
    InvalidContent,
};

pub fn stringSentinelTerminated(str: []u8, offset: usize) Error![:0]const u8 {
    const last = std.mem.indexOfScalarPos(u8, str, offset, 0) orelse return Error.InvalidContent;
    return str[offset..last :0];
}

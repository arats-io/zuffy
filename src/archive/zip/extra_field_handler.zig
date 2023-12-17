context: *const anyopaque,
handlerFn: *const fn (context: *const anyopaque, header: u16, args: *const anyopaque) anyerror!void,

pub fn exec(self: Self, header: u16, args: *const anyopaque) anyerror!void {
    return self.handlerFn(self.context, header, args);
}

const Self = @This();

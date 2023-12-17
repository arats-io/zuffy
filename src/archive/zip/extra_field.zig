pub const types = @import("extra_field_types.zig");

pub const ExtraFieldHandler = @import("extra_field_handler.zig");

pub fn GenericExtraField(
    comptime Context: type,
    comptime Fn: anytype,
) type {
    return struct {
        context: Context,

        pub inline fn handler(self: *const Self) ExtraFieldHandler {
            return .{
                .context = @ptrCast(&self.context),
                .handlerFn = typeErasedFn,
            };
        }

        const Self = @This();

        fn typeErasedFn(context: *const anyopaque, header: u16, args: *const anyopaque) anyerror!void {
            const ptr: *const Context = @alignCast(@ptrCast(context));
            return Fn(ptr.*, header, args);
        }
    };
}

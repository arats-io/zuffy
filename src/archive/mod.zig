pub const zip = @import("zip/mod.zig");

pub const ContentReceiver = @import("content_receiver.zig");

pub fn GenericContent(
    comptime Context: type,
    comptime Fn: anytype,
) type {
    return struct {
        context: Context,

        pub inline fn receiver(self: *const Self) ContentReceiver {
            return .{
                .context = @ptrCast(&self.context),
                .receiveFn = typeErasedReceiverFn,
            };
        }

        const Self = @This();

        fn typeErasedReceiverFn(context: *const anyopaque, filename: []const u8, content: []const u8) anyerror!void {
            const ptr: *const Context = @alignCast(@ptrCast(context));
            return Fn(ptr.*, filename, content);
        }
    };
}

pub const zip = @import("zip/mod.zig");

pub const AnycReceiver = @import("provider.zig");

pub fn GenericReceiver(
    comptime Context: type,
    comptime ReadError: type,
    comptime receiveFn: fn (context: Context, filename: []const u8, content: []const u8) ReadError!void,
) type {
    return struct {
        context: Context,

        pub const Error = ReadError;

        pub inline fn uncompressed(self: Self, filename: []const u8, content: []const u8) Error!void {
            return receiveFn(self.context, filename, content);
        }

        pub inline fn any(self: *const Self) AnycReceiver {
            return .{
                .context = @ptrCast(&self.context),
                .receiveFn = typeErasedReceiverFn,
            };
        }

        const Self = @This();

        fn typeErasedReceiverFn(context: *const anyopaque, filename: []const u8, content: []const u8) anyerror!void {
            const ptr: *const Context = @alignCast(@ptrCast(context));
            return receiveFn(ptr.*, filename, content);
        }
    };
}

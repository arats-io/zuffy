pub const zip = @import("zip/mod.zig");

pub const AnyProvider = @import("provider.zig");

pub fn GenericProvider(
    comptime Context: type,
    comptime ReadError: type,
    comptime provideFn: fn (context: Context, filename: []const u8, content: []const u8) ReadError!void,
) type {
    return struct {
        context: Context,

        pub const Error = ReadError;

        pub inline fn uncompressed(self: Self, filename: []const u8, content: []const u8) Error!void {
            return provideFn(self.context, filename, content);
        }

        pub inline fn any(self: *const Self) AnyProvider {
            return .{
                .context = @ptrCast(&self.context),
                .provideFn = typeErasedProviderFn,
            };
        }

        const Self = @This();

        fn typeErasedProviderFn(context: *const anyopaque, filename: []const u8, content: []const u8) anyerror!void {
            const ptr: *const Context = @alignCast(@ptrCast(context));
            return provideFn(ptr.*, filename, content);
        }
    };
}

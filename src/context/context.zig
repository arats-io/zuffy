const std = @import("std");

pub const CancelFn = fn () void;

var empty_context = Context{
    .parent = null,
    .done_event = null,
};

pub const CancelResult = struct {
    context: *Context,
    cancel_fn: CancelFn,
};
pub const Context = struct {
    parent: ?*Context,
    done_event: std.Once = std.once(struct {
        fn do() void {}
    }.do),

    pub fn background() *Context {
        return &empty_context;
    }

    pub fn todo() *Context {
        return &empty_context;
    }

    pub fn done(self: *Context) bool {
        return self.done_event.done;
    }

    pub fn withCancel(parent: *Context, allocator: std.mem.Allocator) !CancelResult {
        const ctx = try allocator.create(Context);
        ctx.* = Context{
            .parent = parent,
        };
        ctx.done_event.* = std.Thread.Event{};
        const cancel_fn = struct {
            ctx: *Context,
            pub fn call(self: *@This()) void {
                self.ctx.done_event.call();
            }
        }{ .ctx = ctx };
        return .{
            .context = ctx,
            .cancel_fn = cancel_fn.call,
        };
    }
};

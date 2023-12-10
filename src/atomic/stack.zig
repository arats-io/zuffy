const std = @import("std");
const builtin = @import("builtin");

/// Many reader, many writer, non-allocating, thread-safe
/// Uses a spinlock to protect push() and pop()
/// When building in single threaded mode, this is a simple linked list.
pub fn Stack(comptime T: type) type {
    return struct {
        mu: std.Thread.Mutex = std.Thread.Mutex{},
        root: std.atomic.Value(?*Node),

        pub const Self = @This();

        pub const Node = struct {
            next: ?*Node,
            data: T,
        };

        pub fn init() Self {
            return Self{
                .root = std.atomic.Value(?*Node).init(null),
            };
        }

        pub fn push(self: *Self, node: *Node) void {
            if (!builtin.single_threaded) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            const root = self.root.load(.SeqCst);
            node.next = root;

            self.root.cmpxchgStrong(root, node, .SeqCst, .SeqCst);
        }

        pub fn pop(self: *Self) ?*Node {
            if (!builtin.single_threaded) {
                self.mu.lock();
                defer self.mu.unlock();
            }

            const root = self.root.load(.SeqCst);
            if (root == null) {
                return null;
            }
            const nextRoot = root.next;

            self.root.cmpxchgStrong(root, nextRoot, .SeqCst, .SeqCst);
            return root;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.root.load(.SeqCst) == null;
        }
    };
}

const Context = struct {
    allocator: std.mem.Allocator,
    stack: *Stack(i32),
    put_sum: isize,
    get_sum: isize,
    get_count: usize,
    puts_done: bool,
};
// TODO add lazy evaluated build options and then put puts_per_thread behind
// some option such as: "AggressiveMultithreadedFuzzTest". In the AppVeyor
// CI we would use a less aggressive setting since at 1 core, while we still
// want this test to pass, we need a smaller value since there is so much thrashing
// we would also use a less aggressive setting when running in valgrind
const puts_per_thread = 500;
const put_thread_count = 3;

const expect = std.testing.expect;
test "std.atomic.stack" {
    const plenty_of_memory = try std.heap.page_allocator.alloc(u8, 300 * 1024);
    defer std.heap.page_allocator.free(plenty_of_memory);

    var fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(plenty_of_memory);
    const a = fixed_buffer_allocator.threadSafeAllocator();

    var stack = Stack(i32).init();
    var context = Context{
        .allocator = a,
        .stack = &stack,
        .put_sum = 0,
        .get_sum = 0,
        .puts_done = false,
        .get_count = 0,
    };

    if (builtin.single_threaded) {
        {
            var i: usize = 0;
            while (i < put_thread_count) : (i += 1) {
                try expect(startPuts(&context) == 0);
            }
        }
        context.puts_done = true;
        {
            var i: usize = 0;
            while (i < put_thread_count) : (i += 1) {
                try expect(startGets(&context) == 0);
            }
        }
    } else {
        var putters: [put_thread_count]std.Thread = undefined;
        for (&putters) |*t| {
            t.* = try std.Thread.spawn(.{}, startPuts, .{&context});
        }
        var getters: [put_thread_count]std.Thread = undefined;
        for (&getters) |*t| {
            t.* = try std.Thread.spawn(.{}, startGets, .{&context});
        }

        for (putters) |t|
            t.join();
        @atomicStore(bool, &context.puts_done, true, .SeqCst);
        for (getters) |t|
            t.join();
    }

    if (context.put_sum != context.get_sum) {
        std.debug.panic("failure\nput_sum:{} != get_sum:{}", .{ context.put_sum, context.get_sum });
    }

    if (context.get_count != puts_per_thread * put_thread_count) {
        std.debug.panic("failure\nget_count:{} != puts_per_thread:{} * put_thread_count:{}", .{
            context.get_count,
            @as(u32, puts_per_thread),
            @as(u32, put_thread_count),
        });
    }
}

fn startPuts(ctx: *Context) u8 {
    var put_count: usize = puts_per_thread;
    var prng = std.rand.DefaultPrng.init(0xdeadbeef);
    const random = prng.random();
    while (put_count != 0) : (put_count -= 1) {
        std.time.sleep(1); // let the os scheduler be our fuzz
        const x = @as(i32, @bitCast(random.int(u32)));
        const node = ctx.allocator.create(Stack(i32).Node) catch unreachable;
        node.* = Stack(i32).Node{
            .next = undefined,
            .data = x,
        };
        ctx.stack.push(node);
        _ = @atomicRmw(isize, &ctx.put_sum, .Add, x, .SeqCst);
    }
    return 0;
}

fn startGets(ctx: *Context) u8 {
    while (true) {
        const last = @atomicLoad(bool, &ctx.puts_done, .SeqCst);

        while (ctx.stack.pop()) |node| {
            std.time.sleep(1); // let the os scheduler be our fuzz
            _ = @atomicRmw(isize, &ctx.get_sum, .Add, node.data, .SeqCst);
            _ = @atomicRmw(usize, &ctx.get_count, .Add, 1, .SeqCst);
        }

        if (last) return 0;
    }
}

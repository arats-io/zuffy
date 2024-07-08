const std = @import("std");
const builtin = @import("builtin");

/// Many reader, many writer, non-allocating, thread-safe
/// Uses a spinlock to protect push() and pop()
/// When building in single threaded mode, this is a simple linked list.
pub fn Stack(comptime T: type) type {
    return struct {
        mu: std.Thread.Mutex = std.Thread.Mutex{},
        root: std.atomic.Value(?*Node) = std.atomic.Value(?*Node).init(null),

        pub const Self = @This();

        pub const Node = struct {
            next: ?*Node,
            data: T,
        };

        pub fn init() Self {
            return Self{};
        }

        pub fn push(self: *Self, newNode: *Node) void {
            self.mu.lock();
            defer self.mu.unlock();

            const oldNode = self.root.load(.seq_cst);
            newNode.next = oldNode;

            _ = self.root.cmpxchgStrong(oldNode, newNode, .seq_cst, .seq_cst);
        }

        pub fn pop(self: *Self) ?*Node {
            self.mu.lock();
            defer self.mu.unlock();

            const root = self.root.load(.seq_cst);
            if (root) |item| {
                _ = self.root.cmpxchgStrong(item, item.next, .seq_cst, .seq_cst);

                item.next = undefined;
                return item;
            }

            return null;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.root.load(.seq_cst) == null;
        }
    };
}

const Context = struct {
    allocator: std.mem.Allocator,
    stack: *Stack(i8),
    put_sum: i128,
    get_sum: i128,
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

    var stack = Stack(i8).init();
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

        for (putters) |t| {
            t.join();
        }

        @atomicStore(bool, &context.puts_done, true, .seq_cst);

        for (getters) |t| {
            t.join();
        }
    }

    if (context.get_count != puts_per_thread * put_thread_count) {
        std.debug.panic("failure\nget_count:{} != puts_per_thread:{} * put_thread_count:{}", .{
            context.get_count,
            @as(u32, puts_per_thread),
            @as(u32, put_thread_count),
        });
    }

    if (context.put_sum != context.get_sum) {
        std.debug.panic("failure\nput_sum:{} != get_sum:{}", .{ context.put_sum, context.get_sum });
    }
}

fn startPuts(ctx: *Context) u8 {
    var put_count: usize = puts_per_thread;
    const RndGen = std.Random.DefaultPrng;
    var rnd = RndGen.init(0xdeadbeef);

    const random = rnd.random();
    while (put_count != 0) : (put_count -= 1) {
        std.time.sleep(1); // let the os scheduler be our fuzz
        const x = @as(i8, @bitCast(random.int(i8)));
        const node = ctx.allocator.create(Stack(i8).Node) catch unreachable;
        node.* = Stack(i8).Node{
            .next = null,
            .data = x,
        };
        ctx.stack.push(node);
        _ = @atomicRmw(i128, &ctx.put_sum, .Add, x, .seq_cst);
    }
    return 0;
}

fn startGets(ctx: *Context) u8 {
    var last = @atomicLoad(bool, &ctx.puts_done, .seq_cst);
    while (!last) {
        std.time.sleep(20); // let the os scheduler be our fuzz
        while (ctx.stack.pop()) |node| {
            _ = @atomicRmw(i128, &ctx.get_sum, .Add, node.*.data, .seq_cst);
            _ = @atomicRmw(usize, &ctx.get_count, .Add, 1, .seq_cst);
        }
        last = @atomicLoad(bool, &ctx.puts_done, .seq_cst);
    }
    return 0;
}

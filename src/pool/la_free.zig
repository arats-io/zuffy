//! Copied from Zap[1] out of ThreadPool and adapted for a generic pool.
//! In @kprotty's own words: lock-free, allocation-free*.
//!
//! The original file in Zap is licensed under the MIT license, and the
//! license and copyright is reproduced below. The zig-xstd project is also
//! MIT licensed so the entire project (including this file) are equally
//! licensed.
//!
//! MIT License
//!
//! Copyright (c) 2021 kprotty
//!
//! Permission is hereby granted, free of charge, to any person obtaining a copy
//! of this software and associated documentation files (the "Software"), to deal
//! in the Software without restriction, including without limitation the rights
//! to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//! copies of the Software, and to permit persons to whom the Software is
//! furnished to do so, subject to the following conditions:
//!
//! The above copyright notice and this permission notice shall be included in all
//! copies or substantial portions of the Software.
//!
//! THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//! IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//! FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//! AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//! LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//! OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//! SOFTWARE.
//!
//! [1]: https://github.com/kprotty/zap
//! [2]: https://zig.news/kprotty/resource-efficient-thread-pools-with-zig-3291
const std = @import("std");
const assert = std.debug.assert;
const Atomic = std.atomic.Value;

pub fn LockAllocationFree(comptime T: type) type {
    return struct {
        const Self = @This();

        const Sync = packed struct {
            /// Tracks the number of threads spawned
            spawned: u14 = 0,

            _panding: u18 = 0,
        };

        sync: Atomic(u32) = Atomic(u32).init(@bitCast(Sync{})),
        main_queue: Node.Queue = .{},
        threads: Atomic(?*Thread) = Atomic(?*Thread).init(null),

        /// Statically initialize the thread pool using the configuration.
        pub fn init() Self {
            return .{};
        }

        /// Wait for a thread to call shutdown() on the thread pool and kill the worker threads.
        pub fn deinit(self: *Self) void {
            self.* = undefined;
        }

        pub fn registerCurrentThread(noalias self: *Self) void {
            var thread = Thread{ .id = std.Thread.getCurrentId() };
            var thread_ptr = @constCast(&thread);

            Thread.current = thread_ptr;

            const one_spawned: u32 = @bitCast(Sync{ .spawned = 1 });
            _ = self.sync.fetchAdd(one_spawned, .release);

            // Push the thread onto the threads stack in a lock-free manner.
            var threads: ?*Thread = self.threads.load(.monotonic);
            while (true) {
                thread_ptr.next = threads;
                threads = self.threads.cmpxchgWeak(
                    threads,
                    thread_ptr,
                    .release,
                    .monotonic,
                ) orelse break;
            }
        }

        pub fn unregisterCurrentThread(noalias self: *Self) void {
            // Un-spawn one thread, either due to a failed OS thread spawning or the thread is exitting.
            const one_spawned: u32 = @bitCast(Sync{ .spawned = 1 });
            const sync: u32 = self.sync.fetchSub(one_spawned, .release);
            assert(sync > 0);

            var thread: ?*Thread = self.threads.load(.monotonic);

            const currentThreadId = std.Thread.getCurrentId();

            var prevThread: ?*Thread = null;
            var foundThread: ?*Thread = null;
            while (true) {
                if (thread) |th| {
                    if (th.id == currentThreadId) {
                        foundThread = th;
                        break;
                    }
                    if (th.next != null) {
                        prevThread = th;
                        thread = th.next;
                    } else break;
                } else break;
            }

            if (foundThread) |th| {
                if (prevThread) |pth| {
                    pth.next = th.next;
                } else {
                    _ = self.threads.cmpxchgWeak(
                        thread,
                        null,
                        .release,
                        .monotonic,
                    );
                }
                th.moveRemainingsTo(self);
            }
        }

        pub fn push(self: *Self, batch: Batch) void {
            // Sanity check
            if (batch.len == 0) {
                return;
            }

            // Extract out the Node's from the Entrys
            var list = Node.List{
                .head = &batch.head.?.node,
                .tail = &batch.tail.?.node,
            };

            // Push the Entry Nodes to the most approriate queue
            if (Thread.current) |thread| {
                thread.buffer.push(&list) catch thread.queue.push(list);
            } else {
                self.main_queue.push(list);
            }
        }

        /// Schedule a batch of Entrys to be executed by some thread on the thread pool.
        pub fn pop(self: *Self) ?*Entry {
            if (Thread.current) |thread| {
                if (thread.pop(self)) |stole| {
                    const entry: *Entry = @fieldParentPtr("node", stole.node);
                    return entry;
                }
            }

            var try_consumer = self.main_queue.tryAcquireConsumer() catch null;
            if (try_consumer != null) {
                defer self.main_queue.releaseConsumer(try_consumer);

                if (self.main_queue.popUsingConsumer(&try_consumer)) |node| {
                    const entry: *Entry = @fieldParentPtr("node", node);
                    return entry;
                }
            }

            if (self.main_queue.pop()) |node| {
                const entry: *Entry = @fieldParentPtr("node", node);
                return entry;
            }

            return null;
        }

        /// A Entry represents a value for the List .
        pub const Entry = struct {
            node: Node = .{},
            value: T,
        };

        /// An unordered collection of Entries which can be added as a group.
        pub const Batch = struct {
            len: usize = 0,
            head: ?*Entry = null,
            tail: ?*Entry = null,

            /// Create a batch from a single entry.
            pub fn from(entry: *Entry) Batch {
                return Batch{
                    .len = 1,
                    .head = entry,
                    .tail = entry,
                };
            }

            /// Another batch into this one, taking ownership of its entries.
            pub fn push(self: *Batch, batch: Batch) void {
                if (batch.len == 0) return;
                if (self.len == 0) {
                    self.* = batch;
                } else {
                    self.tail.?.node.next = if (batch.head) |h| &h.node else null;
                    self.tail = batch.tail;
                    self.len += batch.len;
                }
            }
        };

        const Thread = struct {
            id: std.Thread.Id,

            next: ?*Thread = null,
            target: ?*Thread = null,
            queue: Node.Queue = .{},
            buffer: Node.Buffer = .{},

            threadlocal var current: ?*Thread = null;

            /// Thread entry point which runs a worker for the List
            fn moveRemainingsTo(self: *Thread, pool: *LockAllocationFree(T)) void {
                current = null;

                // Check our local buffer first
                while (self.buffer.pop()) |node| {
                    const entry: *Entry = @fieldParentPtr("node", node);
                    pool.push(Batch.from(entry));
                }

                // Then check our local queue
                while (self.buffer.consume(&self.queue)) |stole| {
                    const entry: *Entry = @fieldParentPtr("node", stole.node);
                    pool.push(Batch.from(entry));
                }
            }

            /// Try to dequeue a Node/Entry from the List.
            /// Spurious reports of dequeue() returning empty are allowed.
            fn pop(noalias self: *Thread, noalias pool: *LockAllocationFree(T)) ?Node.Buffer.Stole {
                // Check our local buffer first
                if (self.buffer.pop()) |node| {
                    return Node.Buffer.Stole{
                        .node = node,
                        .pushed = false,
                    };
                }

                // Then check our local queue
                if (self.buffer.consume(&self.queue)) |stole| {
                    return stole;
                }

                // Then the global queue
                if (self.buffer.consume(&pool.main_queue)) |stole| {
                    return stole;
                }

                // TODO: add optimistic I/O polling here

                // Then try work stealing from other threads
                var num_threads: u32 = @as(Sync, @bitCast(pool.sync.load(.monotonic))).spawned;
                while (num_threads > 0) : (num_threads -= 1) {
                    // Traverse the stack of registered threads on the thread pool
                    const target = self.target orelse pool.threads.load(.acquire) orelse unreachable;
                    self.target = target.next;

                    // Try to steal from their queue first to avoid contention (the target steal's from queue last).
                    if (self.buffer.consume(&target.queue)) |stole| {
                        return stole;
                    }

                    // Skip stealing from the buffer if we're the target.
                    // We still steal from our own queue above given it may have just been locked the first time we tried.
                    if (target == self) {
                        continue;
                    }

                    // Steal from the buffer of a remote thread as a last resort
                    if (self.buffer.steal(&target.buffer)) |stole| {
                        return stole;
                    }
                }

                return null;
            }
        };
    };
}

const Node = struct {
    next: ?*Node = null,

    /// A linked list of Nodes
    const List = struct {
        head: *Node,
        tail: *Node,
    };

    /// An unbounded multi-producer-(non blocking)-multi-consumer queue of Node pointers.
    const Queue = struct {
        stack: Atomic(usize) = Atomic(usize).init(0),
        cache: ?*Node = null,

        const HAS_CACHE: usize = 0b01;
        const IS_CONSUMING: usize = 0b10;
        const PTR_MASK: usize = ~(HAS_CACHE | IS_CONSUMING);

        comptime {
            assert(@alignOf(Node) >= ((IS_CONSUMING | HAS_CACHE) + 1));
        }

        fn tryAcquireConsumer(self: *Queue) error{ Empty, Contended }!?*Node {
            var stack = self.stack.load(.monotonic);
            while (true) {
                if (stack & IS_CONSUMING != 0)
                    return error.Contended; // The queue already has a consumer.
                if (stack & (HAS_CACHE | PTR_MASK) == 0)
                    return error.Empty; // The queue is empty when there's nothing cached and nothing in the stack.

                // When we acquire the consumer, also consume the pushed stack if the cache is empty.
                var new_stack = stack | HAS_CACHE | IS_CONSUMING;
                if (stack & HAS_CACHE == 0) {
                    assert(stack & PTR_MASK != 0);
                    new_stack &= ~PTR_MASK;
                }

                // Acquire barrier on getting the consumer to see cache/Node updates done by previous consumers
                // and to ensure our cache/Node updates in pop() happen after that of previous consumers.
                stack = self.stack.cmpxchgWeak(
                    stack,
                    new_stack,
                    .acquire,
                    .monotonic,
                ) orelse return self.cache orelse @ptrFromInt(stack & PTR_MASK);
            }
        }

        fn releaseConsumer(noalias self: *Queue, noalias consumer: ?*Node) void {
            // Stop consuming and remove the HAS_CACHE bit as well if the consumer's cache is empty.
            // When HAS_CACHE bit is zeroed, the next consumer will acquire the pushed stack nodes.
            var remove = IS_CONSUMING;
            if (consumer == null)
                remove |= HAS_CACHE;

            // Release the consumer with a release barrier to ensure cache/node accesses
            // happen before the consumer was released and before the next consumer starts using the cache.
            self.cache = consumer;
            const stack = self.stack.fetchSub(remove, .release);

            if (consumer != null)
                assert(stack & remove != 0);
        }

        fn push(noalias self: *Queue, list: List) void {
            var stack = self.stack.load(.monotonic);
            while (true) {
                // Attach the list to the stack (pt. 1)
                list.tail.next = @ptrFromInt(stack & PTR_MASK);

                // Update the stack with the list (pt. 2).
                // Don't change the HAS_CACHE and IS_CONSUMING bits of the consumer.
                var new_stack = @intFromPtr(list.head);
                assert(new_stack & ~PTR_MASK == 0);
                new_stack |= (stack & ~PTR_MASK);

                // Push to the stack with a release barrier for the consumer to see the proper list links.
                stack = self.stack.cmpxchgWeak(
                    stack,
                    new_stack,
                    .release,
                    .monotonic,
                ) orelse break;
            }
        }

        fn pop(noalias self: *Queue) ?*Node {
            // Load the stack to see if there was anything pushed that we could grab.
            var stack = self.stack.load(.monotonic);
            if (stack & PTR_MASK == 0) {
                return null;
            }

            // Nodes have been pushed to the stack, grab then with an Acquire barrier to see the Node links.
            stack = self.stack.swap(HAS_CACHE, .acquire);
            assert(stack & PTR_MASK != 0);

            const node: *Node = @ptrFromInt(stack & PTR_MASK);
            return node;
        }

        fn popUsingConsumer(noalias self: *Queue, noalias consumer_ref: *?*Node) ?*Node {
            // Check the consumer cache (fast path)
            if (consumer_ref.*) |node| {
                consumer_ref.* = node.next;
                return node;
            }

            // Load the stack to see if there was anything pushed that we could grab.
            var stack = self.stack.load(.monotonic);
            assert(stack & IS_CONSUMING != 0);
            if (stack & PTR_MASK == 0) {
                return null;
            }

            // Nodes have been pushed to the stack, grab then with an Acquire barrier to see the Node links.
            stack = self.stack.swap(HAS_CACHE | IS_CONSUMING, .acquire);
            assert(stack & IS_CONSUMING != 0);
            assert(stack & PTR_MASK != 0);

            const node: *Node = @ptrFromInt(stack & PTR_MASK);
            consumer_ref.* = node.next;
            return node;
        }
    };

    /// A bounded single-producer, multi-consumer ring buffer for node pointers.
    const Buffer = struct {
        head: Atomic(Index) = Atomic(Index).init(0),
        tail: Atomic(Index) = Atomic(Index).init(0),
        array: [capacity]Atomic(*Node) = undefined,

        const Index = u32;
        const capacity = 256; // Appears to be a pretty good trade-off in space vs contended throughput
        comptime {
            assert(std.math.maxInt(Index) >= capacity);
            assert(std.math.isPowerOfTwo(capacity));
        }

        fn push(noalias self: *Buffer, noalias list: *List) error{Overflow}!void {
            var head = self.head.load(.monotonic);
            var tail = self.tail.raw; // we're the only thread that can change this

            while (true) {
                var size = tail -% head;
                assert(size <= capacity);

                // Push nodes from the list to the buffer if it's not empty..
                if (size < capacity) {
                    var nodes: ?*Node = list.head;
                    while (size < capacity) : (size += 1) {
                        const node = nodes orelse break;
                        nodes = node.next;

                        // Array written atomically with weakest ordering since it could be getting atomically read by steal().
                        self.array[tail % capacity].store(node, .unordered);
                        tail +%= 1;
                    }

                    // Release barrier synchronizes with Acquire loads for steal()ers to see the array writes.
                    self.tail.store(tail, .release);

                    // Update the list with the nodes we pushed to the buffer and try again if there's more.
                    list.head = nodes orelse return;
                    std.atomic.spinLoopHint();
                    head = self.head.load(.monotonic);
                    continue;
                }

                // Try to steal/overflow half of the Entrys in the buffer to make room for future push()es.
                // Migrating half amortizes the cost of stealing while requiring future pops to still use the buffer.
                // Acquire barrier to ensure the linked list creation after the steal only happens after we succesfully steal.
                var migrate = size / 2;
                head = self.head.cmpxchgWeak(
                    head,
                    head +% migrate,
                    .acquire,
                    .monotonic,
                ) orelse {
                    // Link the migrated Nodes together
                    const first = self.array[head % capacity].raw;
                    while (migrate > 0) : (migrate -= 1) {
                        const prev = self.array[head % capacity].raw;
                        head +%= 1;
                        prev.next = self.array[head % capacity].raw;
                    }

                    // Append the list that was supposed to be pushed to the end of the migrated Nodes
                    const last = self.array[(head -% 1) % capacity].raw;
                    last.next = list.head;
                    list.tail.next = null;

                    // Return the migrated nodes + the original list as overflowed
                    list.head = first;
                    return error.Overflow;
                };
            }
        }

        fn pop(self: *Buffer) ?*Node {
            var head = self.head.load(.monotonic);
            const tail = self.tail.raw; // we're the only thread that can change this

            while (true) {
                // Quick sanity check and return null when not empty
                const size = tail -% head;
                assert(size <= capacity);
                if (size == 0) {
                    return null;
                }

                // Dequeue with an acquire barrier to ensure any writes done to the Node
                // only happen after we succesfully claim it from the array.
                head = self.head.cmpxchgWeak(
                    head,
                    head +% 1,
                    .acquire,
                    .monotonic,
                ) orelse return self.array[head % capacity].raw;
            }
        }

        const Stole = struct {
            node: *Node,
            pushed: bool,
        };

        fn consume(noalias self: *Buffer, noalias queue: *Queue) ?Stole {
            var consumer = queue.tryAcquireConsumer() catch return null;
            defer queue.releaseConsumer(consumer);

            const head = self.head.load(.monotonic);
            const tail = self.tail.raw; // we're the only thread that can change this

            const size = tail -% head;
            assert(size <= capacity);
            assert(size == 0); // we should only be consuming if our array is empty

            // Pop nodes from the queue and push them to our array.
            // Atomic stores to the array as steal() threads may be atomically reading from it.
            var pushed: Index = 0;
            while (pushed < capacity) : (pushed += 1) {
                const node = queue.popUsingConsumer(&consumer) orelse break;
                self.array[(tail +% pushed) % capacity].store(node, .unordered);
            }

            // We will be returning one node that we stole from the queue.
            // Get an extra, and if that's not possible, take one from our array.
            const node = queue.popUsingConsumer(&consumer) orelse blk: {
                if (pushed == 0) return null;
                pushed -= 1;
                break :blk self.array[(tail +% pushed) % capacity].raw;
            };

            // Update the array tail with the nodes we pushed to it.
            // Release barrier to synchronize with Acquire barrier in steal()'s to see the written array Nodes.
            if (pushed > 0) self.tail.store(tail +% pushed, .release);
            return Stole{
                .node = node,
                .pushed = pushed > 0,
            };
        }

        fn steal(noalias self: *Buffer, noalias buffer: *Buffer) ?Stole {
            const head = self.head.load(.monotonic);
            const tail = self.tail.raw; // we're the only thread that can change this

            const size = tail -% head;
            assert(size <= capacity);
            assert(size == 0); // we should only be stealing if our array is empty

            while (true) : (std.atomic.spinLoopHint()) {
                const buffer_head = buffer.head.load(.acquire);
                const buffer_tail = buffer.tail.load(.acquire);

                // Overly large size indicates the the tail was updated a lot after the head was loaded.
                // Reload both and try again.
                const buffer_size = buffer_tail -% buffer_head;
                if (buffer_size > capacity) {
                    continue;
                }

                // Try to steal half (divCeil) to amortize the cost of stealing from other threads.
                const steal_size = buffer_size - (buffer_size / 2);
                if (steal_size == 0) {
                    return null;
                }

                // Copy the nodes we will steal from the target's array to our own.
                // Atomically load from the target buffer array as it may be pushing and atomically storing to it.
                // Atomic store to our array as other steal() threads may be atomically loading from it as above.
                var i: Index = 0;
                while (i < steal_size) : (i += 1) {
                    const node = buffer.array[(buffer_head +% i) % capacity].load(.unordered);
                    self.array[(tail +% i) % capacity].store(node, .unordered);
                }

                // Try to commit the steal from the target buffer using:
                // - an Acquire barrier to ensure that we only interact with the stolen Nodes after the steal was committed.
                // - a Release barrier to ensure that the Nodes are copied above prior to the committing of the steal
                //   because if they're copied after the steal, the could be getting rewritten by the target's push().
                _ = buffer.head.cmpxchgStrong(
                    buffer_head,
                    buffer_head +% steal_size,
                    .acq_rel,
                    .monotonic,
                ) orelse {
                    // Pop one from the nodes we stole as we'll be returning it
                    const pushed = steal_size - 1;
                    const node = self.array[(tail +% pushed) % capacity].raw;

                    // Update the array tail with the nodes we pushed to it.
                    // Release barrier to synchronize with Acquire barrier in steal()'s to see the written array Nodes.
                    if (pushed > 0) self.tail.store(tail +% pushed, .release);
                    return Stole{
                        .node = node,
                        .pushed = pushed > 0,
                    };
                };
            }
        }
    };
};

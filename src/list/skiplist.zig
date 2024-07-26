const std = @import("std");
const builtin = @import("builtin");

const debug = std.debug;
const assert = debug.assert;
const mem = std.mem;
const math = std.math;

const Allocator = mem.Allocator;

pub const Config = struct {
    max_level: usize = 25,
    probability: f64 = 1.0 / std.math.e,

    allow_multiple_values_same_key: bool = false,
};

pub const Measure = enum {
    bytes,
    kbytes,
    mbytes,
    gbytes,
};

const kb = 1024;
const mb = kb * 1024;
const gb = mb * 1024;

pub fn SkipList(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        pub const Error = error{
            Frozen,
        };

        pub const Node = struct {
            next: []?*Element,
        };

        pub const Element = struct {
            node: *Node,
            key: K,
            value: V,
        };

        allocator: Allocator,
        mutex: std.Thread.Mutex = std.Thread.Mutex{},
        cfg: Config = .{},

        rand: std.Random,
        node: *Node,
        prev_nodes: []?*Node,
        prob_table: std.ArrayList(f64),
        len: i32 = 0,
        frozen: bool = false,

        bytes: u128 = 0,

        pub fn init(allocator: Allocator, cfg: Config) !Self {
            return try initWithLevel(allocator, cfg);
        }

        pub fn initWithLevel(allocator: Allocator, cfg: Config) !Self {
            var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
            var elements: []?*Element = try allocator.alloc(?*Element, cfg.max_level);
            for (0..cfg.max_level) |idx| {
                elements[idx] = null;
            }

            var cache: []?*Node = try allocator.alloc(?*Node, cfg.max_level);
            for (0..cfg.max_level) |idx| {
                cache[idx] = null;
            }

            const node = try allocator.create(Node);
            node.* = Node{
                .next = elements,
            };

            return Self{
                .node = node,
                .prev_nodes = cache,
                .allocator = allocator,
                .cfg = cfg,
                .rand = prng.random(),
                .prob_table = try probabilityTable(allocator, cfg.probability, cfg.max_level),
            };
        }

        pub fn size(self: *Self, comptime measure: Measure) u128 {
            return switch (measure) {
                inline .bytes => self.bytes,
                inline .kbytes => self.bytes / kb,
                inline .mbytes => self.bytes / mb,
                inline .gbytes => self.bytes / gb,
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.len = 0;
            self.frozen = true;

            for (self.node.next) |elem| {
                if (elem) |d| {
                    self.deinitElement(d);
                }
            }

            self.allocator.free(self.prev_nodes);
            self.prob_table.clearAndFree();
        }

        fn deinitElement(self: *Self, element: *Element) void {
            for (element.node.next) |elem| {
                if (elem) |d| {
                    self.deinitElement(d);
                    self.allocator.free(d.node.next);
                    self.allocator.destroy(d.node);
                    self.allocator.destroy(d);
                }
            }
        }

        pub fn isFrozen(self: *Self) bool {
            return self.frozen;
        }

        pub fn freeze(self: *Self) void {
            self.frozen = true;
        }

        pub fn front(self: *Self) *Element {
            return self.node.next[0];
        }

        pub fn insert(self: *Self, key: K, value: V) !*Element {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.frozen) return Error.Frozen;

            self.bytes += comptime (@sizeOf(K) + @sizeOf(V));

            return try self.add(key, value);
        }

        fn add(self: *Self, key: K, value: V) !*Element {
            var prevs = self.getPrevElementNodes(key);

            var element: ?*Element = null;

            if (self.cfg.allow_multiple_values_same_key == false) {
                element = prevs[0].?.next[0];
                if (element != null and element.?.key <= key) {
                    element.?.value = value;
                    return element.?;
                }
            }

            const level = self.randLevel();
            var elements: []?*Element = try self.allocator.alloc(?*Element, level);
            for (0..level) |idx| {
                elements[idx] = null;
            }

            const node = try self.allocator.create(Node);
            node.* = Node{
                .next = elements,
            };

            element = try self.allocator.create(Element);
            element.?.* = Element{
                .node = node,
                .key = key,
                .value = value,
            };

            for (0..element.?.node.next.len) |i| {
                element.?.node.next[i] = prevs[i].?.next[i];
                prevs[i].?.next[i] = element;
            }

            self.len += 1;
            return element.?;
        }

        pub fn has(self: *Self, key: K) bool {
            return self.get(key) != null;
        }

        pub fn get(self: *Self, key: K) ?V {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.len == 0) return null;

            var prev: *Node = self.node;
            var next: ?*Element = null;

            var i = self.cfg.max_level - 1;
            while (i >= 0) : (i -= 1) {
                next = prev.next[i];

                while (next != null and key > next.?.key) {
                    prev = next.?.node;
                    next = next.?.node.next[i];
                }

                if (i == 0) break;
            }

            if (next != null and next.?.key <= key) {
                return next.?.value;
            }

            return null;
        }

        pub fn remove(self: *Self, key: K) ?V {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.frozen) return null;

            var prevs = self.getPrevElementNodes(key);

            // found the element, remove it
            const element = prevs[0].?.next[0];
            if (element != null and element.?.key <= key) {
                for (element.?.node.next, 0..) |v, k| {
                    prevs[k].?.next[k] = v;
                }

                self.len -= 1;
                self.bytes -= comptime (@sizeOf(K) + @sizeOf(V));

                //try self.nextAddOnRemove(element.?);
                self.allocator.free(element.?.node.next);
                self.allocator.destroy(element.?.node);
                self.allocator.destroy(element.?);

                return element.?.value;
            }

            return null;
        }

        // fn nextAddOnRemove(self: *Self, element: *Element) !void {
        //     for (element.node.next) |elem| {
        //         if (elem) |d| {
        //             _ = try self.add(d.key, d.value);
        //             //std.debug.print("Re-Inserted - {}:{}\n", .{ d.value, d.key });

        //             try self.nextAddOnRemove(d);
        //         }
        //     }
        // }

        fn getPrevElementNodes(self: *Self, key: K) []?*Node {
            var prev: *Node = self.node;
            var next: ?*Element = null;

            var prevs = self.prev_nodes;

            var i = self.cfg.max_level - 1;
            while (i >= 0) : (i -= 1) {
                next = prev.next[i];

                while (next != null and key > next.?.key) {
                    prev = next.?.node;
                    next = next.?.node.next[i];
                }

                prevs[i] = prev;

                if (i == 0) break;
            }

            return prevs;
        }

        pub fn setProbability(self: *Self, newProbability: f64) void {
            if (self.frozen) return;

            self.probability = newProbability;
            self.prob_table = probabilityTable(self.allocator, self.probability, self.maxLevel);
        }

        pub fn forEach(self: *Self, callback: *const fn (K, V) void) void {
            if (self.len == 0) return;

            for (self.node.next) |elem| {
                if (elem) |d| {
                    forEachElement(d, callback);
                }
            }
        }

        fn forEachElement(element: *Element, callback: *const fn (K, V) void) void {
            callback(element.key, element.value);

            for (element.node.next) |elem| {
                if (elem) |d| {
                    forEachElement(d, callback);
                }
            }
        }

        fn randLevel(self: *Self) usize {
            const first = self.rand.float(f32);
            const d = @as(f64, @floatCast(1 << 63));
            const r = first / d;

            var level: usize = 1;
            while (true) {
                if (level < self.cfg.max_level and r < self.prob_table.items[level]) break;
                level += 1;
            }
            return level;
        }

        fn probabilityTable(allocator: Allocator, probability: f64, maxLevel: usize) !std.ArrayList(f64) {
            var table = std.ArrayList(f64).init(allocator);
            for (0..maxLevel) |i| {
                const f: f64 = @as(f64, @floatFromInt(i));
                const prob = math.pow(f64, probability, f);
                try table.append(prob);
            }
            return table;
        }
    };
}

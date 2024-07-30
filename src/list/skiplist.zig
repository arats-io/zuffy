const std = @import("std");
const builtin = @import("builtin");

const debug = std.debug;
const assert = debug.assert;
const mem = std.mem;
const math = std.math;

const Allocator = mem.Allocator;

pub const Config = struct {
    max_level: usize = 25,
    probability: f64 = 0.00001 / std.math.e,

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
        cache: []?*Node,
        probarr: std.ArrayList(f64),
        len: i32 = 0,
        frozen: bool = false,

        bytes: u128 = 0,

        pub fn init(allocator: Allocator, cfg: Config) !Self {
            return try initWithLevel(allocator, cfg);
        }

        pub fn initWithLevel(allocator: Allocator, cfg: Config) !Self {
            var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));

            var cache: []?*Node = try allocator.alloc(?*Node, cfg.max_level);
            for (0..cfg.max_level) |idx| {
                cache[idx] = null;
            }

            return Self{
                .node = try newNode(allocator, cfg.max_level),
                .cache = cache,
                .allocator = allocator,
                .cfg = cfg,
                .rand = prng.random(),
                .probarr = try probabArr(allocator, cfg.probability, cfg.max_level),
            };
        }

        pub fn contentSize(self: *Self, comptime measure: Measure) u128 {
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

            self.frozen = true;

            self.probarr.deinit();
            for (0..self.cache.len) |idx| {
                self.cache[idx] = null;
            }
            self.allocator.free(self.cache[0..self.cache.len]);

            self.deleteNode(self.node);

            for (0..self.node.next.len) |idx| {
                self.node.next[idx] = null;
            }
            self.allocator.free(self.node.next);
            self.allocator.destroy(self.node);

            self.len = 0;
        }

        fn deleteNode(self: *Self, node: *Node) void {
            for (0..node.next.len) |idx| {
                if (node.next[idx]) |e| {
                    node.next[idx] = null;
                    self.deleteNode(e.node);

                    self.allocator.destroy(e);
                    std.debug.print("Element destroyed\n", .{});
                }
            }

            for (0..node.next.len) |idx| {
                node.next[idx] = null;
            }
            self.allocator.free(node.next[0..node.next.len]);
            self.allocator.destroy(node);
            std.debug.print("Node destroyed\n", .{});
        }

        pub fn isFrozen(self: *Self) bool {
            return self.frozen;
        }

        pub fn freeze(self: *Self) void {
            self.frozen = true;
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

            element = try newElement(self.allocator, self.randLevel(), key, value);

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

                // const handler = struct {
                //     pub fn f(k: f128, v: usize) void {
                //         std.debug.print("{}:{} \n", .{ v, k });
                //     }
                // }.f;
                // std.debug.print("---------------------------------------------------- \n", .{});
                // self.forEachNode(element.?.node, handler);
                // std.debug.print("---------------------------------------------------- \n", .{});

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

            var prevs = self.cache;

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

        pub fn setProbability(self: *Self, newProbability: f64) !void {
            if (self.frozen) return;

            self.probability = newProbability;
            self.probarr = try probabArr(self.allocator, self.probability, self.maxLevel);
        }

        pub fn forEach(self: *Self, callback: *const fn (K, V) void) void {
            if (self.len == 0) return;

            self.forEachNode(self.node, callback);
        }

        fn forEachNode(self: *Self, node: *Node, callback: *const fn (K, V) void) void {
            if (self.len == 0) return;

            for (node.next) |elem| {
                if (elem) |d| {
                    self.forEachElement(d, callback);
                }
            }
        }

        fn forEachElement(self: *Self, element: *Element, callback: *const fn (K, V) void) void {
            callback(element.key, element.value);

            for (element.node.next) |elem| {
                if (elem) |e| {
                    self.forEachElement(e, callback);
                }
            }
        }

        fn randLevel(self: *Self) usize {
            const first = self.rand.float(f32);
            const d = @as(f64, @floatCast(1 << 63));
            const r = first / d;

            var level: usize = 1;
            while (true) {
                if (level < self.cfg.max_level and r < self.probarr.items[level]) break;
                level += 1;
            }
            return level;
        }

        fn probabArr(allocator: Allocator, probability: f64, maxLevel: usize) !std.ArrayList(f64) {
            var table = std.ArrayList(f64).init(allocator);
            errdefer table.deinit();

            for (0..maxLevel) |i| {
                const f: f64 = @as(f64, @floatFromInt(i));
                const prob = math.pow(f64, probability, f);
                try table.append(prob);
            }
            return table;
        }

        fn newNode(allocator: Allocator, level: usize) !*Node {
            var elements: []?*Element = try allocator.alloc(?*Element, level);
            for (0..level) |idx| {
                elements[idx] = null;
            }

            const node = try allocator.create(Node);
            node.* = Node{
                .next = elements,
            };

            return node;
        }

        fn newElement(allocator: Allocator, level: usize, key: K, value: V) !*Element {
            const element = try allocator.create(Element);
            element.* = Element{
                .node = try newNode(allocator, level),
                .key = key,
                .value = value,
            };
            return element;
        }
    };
}

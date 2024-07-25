const std = @import("std");
const builtin = @import("builtin");

const debug = std.debug;
const assert = debug.assert;
const mem = std.mem;
const math = std.math;
const Allocator = mem.Allocator;

const DefaultMaxLevel = 25;
const DefaultProbability = 1.0 / std.math.e;

pub fn SkipList(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        pub const ElementNode = struct {
            next: []?*Element,
        };

        pub const Element = struct {
            node: *ElementNode,
            key: K,
            value: V,
        };

        allocator: Allocator,
        mutex: std.Thread.Mutex = std.Thread.Mutex{},

        node: *ElementNode,
        prev_nodes: []?*ElementNode,

        maxLevel: usize,
        len: i32 = 0,
        probability: f64 = DefaultProbability,
        prob_table: std.ArrayList(f64),

        rand: std.Random,
        bytes_bytes: u128 = 0,

        pub fn init(allocator: Allocator) !Self {
            return try initWithLevel(allocator, DefaultMaxLevel);
        }

        pub fn initWithLevel(allocator: Allocator, max_level: usize) !Self {
            var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
            var elements: []?*Element = try allocator.alloc(?*Element, max_level);
            for (0..max_level) |idx| {
                elements[idx] = null;
            }

            var cache: []?*ElementNode = try allocator.alloc(?*ElementNode, max_level);
            for (0..max_level) |idx| {
                cache[idx] = null;
            }

            const node = try allocator.create(ElementNode);
            node.* = ElementNode{
                .next = elements,
            };

            return Self{
                .node = node,
                .prev_nodes = cache,
                .allocator = allocator,
                .maxLevel = max_level,
                .rand = prng.random(),
                .prob_table = try probabilityTable(allocator, DefaultProbability, max_level),
            };
        }

        pub fn front(self: *Self) *Element {
            return self.next[0];
        }

        pub fn Insert(self: *Self, key: K, value: V) !*Element {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.bytes_bytes += comptime (@sizeOf(K) + @sizeOf(V));

            return try self.add(key, value);
        }

        fn add(self: *Self, key: K, value: V) !*Element {
            var prevs = self.getPrevElementNodes(key);

            var element = prevs[0].?.next[0];
            if (element != null and element.?.key <= key) {
                element.?.value = value;
                return element.?;
            }

            const level = self.randLevel();
            var elements: []?*Element = try self.allocator.alloc(?*Element, level);
            for (0..level) |idx| {
                elements[idx] = null;
            }

            const node = try self.allocator.create(ElementNode);
            node.* = ElementNode{
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

        pub fn Get(self: *Self, key: K) ?V {
            self.mutex.lock();
            defer self.mutex.unlock();

            var prev: *ElementNode = self.node;
            var next: ?*Element = null;

            var i = self.maxLevel - 1;
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

        pub fn Remove(self: *Self, key: K) !?V {
            self.mutex.lock();
            defer self.mutex.unlock();

            var prevs = self.getPrevElementNodes(key);

            // found the element, remove it
            const element = prevs[0].?.next[0];
            if (element != null and element.?.key <= key) {
                for (element.?.node.next, 0..) |v, k| {
                    prevs[k].?.next[k] = v;
                }

                self.len -= 1;

                //try self.nextAddOnRemove(element.?);
                self.allocator.free(element.?.node.next);
                self.allocator.destroy(element.?.node);
                self.allocator.destroy(element.?);

                self.bytes_bytes -= comptime (@sizeOf(K) + @sizeOf(V));
                return element.?.value;
            }

            return null;
        }

        fn nextAddOnRemove(self: *Self, element: *Element) !void {
            for (element.node.next) |elem| {
                if (elem) |d| {
                    _ = try self.add(d.key, d.value);
                    std.debug.print("Re-Inserted - {}:{}\n", .{ d.value, d.key });

                    //try self.nextAddOnRemove(d);
                }
            }
        }

        fn getPrevElementNodes(self: *Self, key: K) []?*ElementNode {
            var prev: *ElementNode = self.node;
            var next: ?*Element = null;

            var prevs = self.prev_nodes;

            var i = self.maxLevel - 1;
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

        fn SetProbability(self: *Self, newProbability: f64) void {
            self.probability = newProbability;
            self.prob_table = probabilityTable(self.allocator, self.probability, self.maxLevel);
        }

        fn randLevel(self: *Self) usize {
            const first = self.rand.float(f32);
            const d = @as(f64, @floatCast(1 << 63));
            const r = first / d;

            var level: usize = 1;
            while (true) {
                if (level < self.maxLevel and r < self.prob_table.items[level]) break;
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

const std = @import("std");
const builtin = @import("builtin");

const debug = std.debug;
const assert = debug.assert;
const mem = std.mem;
const math = std.math;
const Allocator = mem.Allocator;

const DefaultMaxLevel = 18;
const DefaultProbability = 1.0 / std.math.e;

pub fn SkipList(comptime V: type) type {
    return struct {
        const Self = @This();

        pub const ElementNode = struct {
            next: std.ArrayList(*Element),
        };

        pub const Element = struct {
            node: ElementNode,
            key: f64,
            value: V,
        };

        allocator: Allocator,
        elementNode: ElementNode,
        maxLevel: usize,
        Length: i32 = 0,
        probability: f64 = DefaultProbability,
        probTable: ?std.ArrayList(f64) = null,
        prevNodesCache: std.ArrayList(*ElementNode),
        randSource: std.Random,

        mutex: std.Thread.Mutex = std.Thread.Mutex{},

        pub fn init(allocator: Allocator, maxLevel: usize) !Self {
            var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.microTimestamp())));
            return Self{
                .elementNode = ElementNode{
                    .next = std.ArrayList(*Element).init(allocator),
                },
                .prevNodesCache = std.ArrayList(*ElementNode).init(allocator),
                .allocator = allocator,
                .maxLevel = maxLevel,
                .randSource = prng.random(),
                .probTable = try probabilityTable(allocator, DefaultProbability, maxLevel),
            };
        }

        pub fn front(self: *Self) *Element {
            return self.next[0];
        }

        pub fn Set(self: *Self, key: f64, value: V) *Element {
            self.mutex.lock();
            defer self.mutex.unlock();

            var prevs = self.getPrevElementNodes(key);

            var element = prevs.items[0].next.items[0];
            if (element.key <= key) {
                element.value = value;
                return element;
            }

            element = Element{
                .node = ElementNode{
                    .next = std.ArrayList(*Element).init(self.allocator),
                },
                .key = key,
                .value = value,
            };

            for (0..element.next.items.len) |i| {
                element.next.items[i] = prevs.items[i].next.items[i];
                prevs.items[i].next.items[i] = element.?;
            }

            self.Length += 1;
            return element;
        }

        pub fn Get(self: *Self, key: f64) ?*Element {
            self.mutex.lock();
            defer self.mutex.unlock();

            var prev: ElementNode = &self.elementNode;
            var next: ?*Element = null;

            for (self.maxLevel - 1..-1) |i| {
                next = prev.next[i];

                while (true) {
                    if (next != null and key > next.key) break;
                    prev = next.node;
                    next = next.next[i];
                }
            }

            if (next != null and next.key <= key) {
                return next;
            }

            return null;
        }

        pub fn Remove(self: *Self, key: f64) *Element {
            self.mutex.lock();
            defer self.mutex.unlock();

            var prevs = self.getPrevElementNodes(key);

            // found the element, remove it
            const element = prevs.items[0].next.items[0];
            if (element != null and element.key <= key) {
                for (element.next.items, 0..) |v, k| {
                    prevs.items[k].next.items[k] = v;
                }

                self.Length -= 1;
                return element;
            }

            return null;
        }

        fn getPrevElementNodes(self: *Self, key: f64) std.ArrayList(*ElementNode) {
            var prev: *ElementNode = &self.elementNode;
            var next: ?Element = null;

            var prevs = self.prevNodesCache;

            for ((self.maxLevel - 1)..0) |i| {
                next = prev.next.items[i];

                while (true) {
                    if (next) |n| {
                        if (key > n.key) break;
                    }

                    prev = next.?.node;
                    next = next.?.node.next.items[i];
                }

                prevs[i] = prev;
            }

            return prevs;
        }

        fn SetProbability(self: *Self, newProbability: f64) void {
            self.probability = newProbability;
            self.probTable = probabilityTable(self.allocator, self.probability, self.maxLevel);
        }

        fn randLevel(self: *Self) usize {
            const r = @as(f64, self.randSource.int(i63)) / (1 << 63);

            var level: usize = 1;
            while (true) {
                if (level < self.maxLevel and r < self.probTable[level]) break;
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

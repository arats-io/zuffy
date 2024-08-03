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
    const cmper = comptime switch (@typeInfo(K)) {
        .Struct, .Union, .Enum => true,
        else => false,
    } and @hasDecl(K, "cmper");

    return struct {
        const Self = @This();

        pub const Error = error{
            Frozen,
        };

        pub const Node = struct {
            next: []?*Element,
        };

        pub const Element = struct {
            node: ?*Node,
            key: K,
            value: V,
        };

        allocator: Allocator,
        mutex: std.Thread.Mutex = std.Thread.Mutex{},
        cfg: Config = .{},

        rand: std.Random.Xoshiro256,
        node: ?*Node = null,
        cache: ?[]?*Node = null,
        probarr: std.ArrayList(f64),
        len: i32 = 0,
        frozen: bool = false,

        bytes: u128 = 0,

        pub fn init(allocator: Allocator, cfg: Config) !Self {
            return try create(allocator, cfg);
        }

        fn create(allocator: Allocator, cfg: Config) !Self {
            var cache: []?*Node = try allocator.alloc(?*Node, cfg.max_level);
            for (0..cfg.max_level) |idx| {
                cache[idx] = null;
            }

            var self = Self{
                .rand = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp()))),
                .cache = cache,
                .allocator = allocator,
                .cfg = cfg,
                .probarr = try probabArr(allocator, cfg.probability, cfg.max_level),
            };
            self.node = try self.newNode(cfg.max_level);

            return self;
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
            self.frozen = true;
            self.len = 0;

            self.probarr.clearAndFree();

            self.deleteNode(self.node.?);
            self.allocator.destroy(self.node.?);
            self.node = null;
            self.allocator.free(self.cache.?);
            self.cache = null;
        }

        fn deleteNode(self: *Self, node: *Node) void {
            for (0..node.next.len) |idx| {
                if (node.next[idx] == null) continue;

                const elem = node.next[idx].?;
                self.deleteNode(elem.node.?);
                self.allocator.destroy(elem.node.?);
                elem.node = null;

                self.allocator.destroy(elem);

                node.next[idx] = null;
            }

            self.allocator.free(node.next);
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

            defer {
                self.bytes += comptime (@sizeOf(K) + @sizeOf(V));
            }

            return try self.add(key, value);
        }

        fn add(self: *Self, key: K, value: V) !*Element {
            var prevs = self.getPrevElementNodes(key);

            var element: ?*Element = null;

            if (self.cfg.allow_multiple_values_same_key == false) {
                element = prevs[0].?.next[0];

                if (element != null and
                    switch (cmper) {
                    inline true => element.?.key.cmper().le(&key),
                    inline false => element.?.key <= key,
                }) {
                    element.?.value = value;
                    return element.?;
                }
            }

            element = try self.newElement(self.randLevel(), key, value);

            for (0..element.?.node.?.next.len) |i| {
                element.?.node.?.next[i] = prevs[i].?.next[i];
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

            var prev: *Node = self.node.?;
            var next: ?*Element = null;

            var i = self.cfg.max_level - 1;
            while (i >= 0) : (i -= 1) {
                next = prev.next[i];

                while (next != null and
                    switch (cmper) {
                    inline true => key.cmper().gt(&next.?.key),
                    inline false => key > next.?.key,
                }) {
                    prev = next.?.node.?;
                    next = next.?.node.?.next[i];
                }

                if (i == 0) break;
            }

            if (next != null and
                switch (cmper) {
                inline true => next.?.key.cmper().le(&key),
                inline false => next.?.key <= key,
            }) {
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
            const element: ?*Element = prevs[0].?.next[0];

            if (element) |elem| if (switch (cmper) {
                inline true => elem.key.cmper().le(&key),
                inline false => elem.key <= key,
            }) {
                for (elem.node.?.next, 0..) |v, k| {
                    prevs[k].?.next[k] = v;
                    elem.node.?.next[k] = null;
                }

                defer {
                    self.len -= 1;
                    self.bytes -= comptime (@sizeOf(K) + @sizeOf(V));
                }

                for (0..elem.node.?.next.len) |idx| {
                    elem.node.?.next[idx] = null;
                }

                defer {
                    self.allocator.free(elem.node.?.next);
                    self.allocator.destroy(elem.node.?);
                    self.allocator.destroy(elem);
                }

                return elem.value;
            };

            return null;
        }

        fn getPrevElementNodes(self: *Self, key: K) []?*Node {
            var prev: *Node = self.node.?;
            var next: ?*Element = null;

            var prevs = self.cache.?;

            var i = self.cfg.max_level - 1;
            while (i >= 0) : (i -= 1) {
                next = prev.next[i];

                while (next != null and
                    switch (cmper) {
                    inline true => key.cmper().gt(&next.?.key),
                    inline false => key > next.?.key,
                }) {
                    prev = next.?.node.?;
                    next = next.?.node.?.next[i];
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

            self.forEachNode(self.node.?, callback);
        }

        fn forEachNode(self: *Self, node: *Node, callback: *const fn (K, V) void) void {
            for (node.next) |element| {
                if (element) |elem| {
                    self.forEachNode(elem.node.?, callback);

                    callback(elem.key, elem.value);
                }
            }
        }

        fn randLevel(self: *Self) usize {
            self.rand.seed(@as(u64, @intCast(std.time.nanoTimestamp())));
            const random = self.rand.random();

            const f: f64 = @as(f64, @floatFromInt(random.int(u63)));
            const r = f / @as(f64, @floatFromInt(1 << 63));

            var level: usize = 1;
            while (level < self.cfg.max_level and r < self.probarr.items[level]) {
                level += 1;
            }
            return level;
        }

        fn probabArr(allocator: Allocator, probability: f64, maxLevel: usize) !std.ArrayList(f64) {
            var table = std.ArrayList(f64).init(allocator);
            errdefer table.deinit();

            for (1..maxLevel + 1) |i| {
                const f: f64 = @as(f64, @floatFromInt(i - 1));
                const prob = math.pow(f64, probability, f);
                try table.append(prob);
            }
            return table;
        }

        fn newNode(self: *Self, level: usize) !*Node {
            const node = try self.allocator.create(Node);
            node.*.next = try self.allocator.alloc(?*Element, level);
            for (0..level) |idx| {
                node.next[idx] = null;
            }

            return node;
        }

        fn newElement(self: *Self, level: usize, key: K, value: V) !*Element {
            const element = try self.allocator.create(Element);
            element.*.node = try self.newNode(level);
            element.*.key = key;
            element.*.value = value;

            return element;
        }
    };
}

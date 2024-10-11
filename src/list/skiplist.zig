const std = @import("std");
const builtin = @import("builtin");

const debug = std.debug;
const assert = debug.assert;
const mem = std.mem;
const math = std.math;

const Allocator = mem.Allocator;

pub const Config = struct {
    max_level: usize = 18,
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
        .@"struct", .@"union", .@"enum" => true,
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
            node: *Node,
            key: K,
            value: V,
        };

        allocator: *const Allocator,
        mutex: std.Thread.Mutex = std.Thread.Mutex{},
        cfg: Config = .{},

        rand: std.Random.Xoshiro256,
        node: *Node,
        cache: []?*Node,
        probarr: std.ArrayList(f64),
        len: i32 = 0,
        frozen: bool = false,

        bytes: u128 = 0,

        //to be removed
        // time: i128 = 0,
        // counter: usize = 0,

        pub fn init(allocator: *const Allocator, cfg: Config) !Self {
            return try create(allocator, cfg);
        }

        fn create(allocator: *const Allocator, cfg: Config) !Self {
            std.debug.assert(cfg.max_level > 1 and cfg.max_level <= 64);

            return Self{
                .allocator = allocator,
                .cfg = cfg,
                .node = try newNode(allocator, cfg.max_level),
                .cache = try allocator.alloc(?*Node, cfg.max_level),
                .rand = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.microTimestamp()))),
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
            self.frozen = true;
            self.len = 0;

            self.probarr.clearAndFree();

            self.deleteNode(self.node);
            self.allocator.destroy(self.node);
            self.allocator.free(self.cache);
        }

        fn deleteNode(self: *Self, node: *Node) void {
            for (0..node.next.len) |idx| {
                if (node.next[idx] == null) continue;

                const elem = node.next[idx].?;
                self.deleteNode(elem.node);
                self.allocator.destroy(elem.node);

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

        fn deepBitSizeOf(self: *Self, value: anytype) usize {
            var size: usize = 0;

            const T = @TypeOf(value);
            const info = @typeInfo(T);
            switch (info) {
                .float, .comptime_float => size += info.float.bits,
                .int, .comptime_int => size += info.int.bits,
                .bool => size += 8,
                .optional => {
                    if (value) |payload| {
                        size += self.deepBitSizeOf(payload);
                    }
                },

                .@"enum" => |enumInfo| {
                    if (enumInfo.is_exhaustive) {
                        size += self.deepBitSizeOf(@field(value, @tagName(value)));
                        return;
                    }

                    // Use @tagName only if value is one of known fields
                    @setEvalBranchQuota(3 * enumInfo.fields.len);
                    inline for (enumInfo.fields) |enumField| {
                        size += self.deepBitSizeOf(@field(value, enumField.value));
                    }
                },
                .@"union" => |uinfo| {
                    if (uinfo.tag_type) {
                        inline for (uinfo.fields) |u_field| {
                            size += self.deepBitSizeOf(@field(value, u_field.name));
                        }
                    }
                },
                .@"struct" => |sinfo| {
                    inline for (sinfo.fields) |f| {
                        size += self.deepBitSizeOf(@field(value, f.name));
                    }
                },
                .pointer => |ptr_info| switch (ptr_info.size) {
                    .One => switch (@typeInfo(ptr_info.child)) {
                        .Array, .Enum, .Union, .Struct => {
                            size += self.deepBitSizeOf(value.*);
                        },
                        else => @compileError("unable to calculate the size for '" ++ @typeName(T) ++ "'"),
                    },
                    .Many, .C => {
                        size += self.deepBitSizeOf(mem.span(value));
                    },
                    .Slice => {
                        for (value) |elem| {
                            size += self.deepBitSizeOf(elem);
                        }
                    },
                },
                .array, .vector => {
                    for (value) |elem| {
                        size += self.deepBitSizeOf(elem);
                    }
                },

                else => @compileError("unable to calculate the size for '" ++ @typeName(T) ++ "'"),
            }

            return size;
        }

        pub fn insert(self: *Self, key: K, value: V) !*Element {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.frozen) return Error.Frozen;

            self.len += 1;
            self.bytes += (self.deepBitSizeOf(key) / 8) + (self.deepBitSizeOf(value) / 8);

            // const startTime = std.time.nanoTimestamp();
            self.cacheRefresh(key);
            // self.counter += 1;
            // self.time += std.time.nanoTimestamp() - startTime;

            // if (self.counter > 0 and self.counter % 150000 == 0) {
            //     std.debug.print("Cache Refresh took {} nanosec \n", .{@divTrunc(self.time, self.counter)});
            //     self.counter = 0;
            //     self.time = 0;
            // }

            var element: ?*Element = null;

            if (self.cfg.allow_multiple_values_same_key == false) {
                element = self.cache[0].?.next[0];

                if (element != null and
                    switch (cmper) {
                    inline true => element.?.key.cmper().le(&key),
                    inline false => element.?.key <= key,
                }) {
                    element.?.value = value;
                    return element.?;
                }
            }

            element = try newElement(self.allocator, self.randLevel(), key, value);

            for (0..element.?.node.next.len) |i| {
                element.?.node.next[i] = self.cache[i].?.next[i];
                self.cache[i].?.next[i] = element;
            }

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

                while (next != null and
                    switch (cmper) {
                    inline true => key.cmper().gt(&next.?.key),
                    inline false => key > next.?.key,
                }) {
                    prev = next.?.node;
                    next = prev.next[i];
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

            self.cacheRefresh(key);

            // found the element, remove it
            const element: ?*Element = self.cache[0].?.next[0];

            if (element) |elem| if (switch (cmper) {
                inline true => elem.key.cmper().le(&key),
                inline false => elem.key <= key,
            }) {
                for (elem.node.next, 0..) |v, k| {
                    self.cache[k].?.next[k] = v;
                    elem.node.next[k] = null;
                }

                defer {
                    self.len -= 1;
                    self.bytes -= (self.deepBitSizeOf(key) / 8) + (self.deepBitSizeOf(elem.value) / 8);

                    self.allocator.free(elem.node.next);
                    self.allocator.destroy(elem.node);
                    self.allocator.destroy(elem);
                }

                return elem.value;
            };

            return null;
        }

        inline fn cacheRefresh(self: *Self, key: K) void {
            var prev: *Node = self.node;

            var i = self.cfg.max_level - 1;
            while (i >= 0) : (i -= 1) {
                var next = prev.next[i];

                while (next != null and
                    switch (cmper) {
                    inline true => key.cmper().gt(&next.?.key),
                    inline false => key > next.?.key,
                }) {
                    prev = next.?.node;
                    next = prev.next[i];
                }

                self.cache[i] = prev;
                if (i == 0) break;
            }
        }

        pub fn setProbability(self: *Self, newProbability: f64) !void {
            if (self.frozen) return;

            self.probability = newProbability;

            self.probarr.clearAndFree();
            self.probarr = try probabArr(self.allocator, self.probability, self.maxLevel);
        }

        pub fn forEach(self: *Self, callback: *const fn (K, V) void) void {
            if (self.len == 0) return;

            self.forEachNode(self.node, callback);
        }

        fn forEachNode(self: *Self, node: *Node, callback: *const fn (K, V) void) void {
            for (node.next) |element| {
                if (element) |elem| {
                    self.forEachNode(elem.node, callback);

                    callback(elem.key, elem.value);
                }
            }
        }

        pub fn forEachWithContext(self: *Self, comptime Context: type, ctx: Context, callback: *const fn (ctx: Context, K, V) void) void {
            if (self.len == 0) return;

            self.forEachNodeWithContext(self.node, Context, ctx, callback);
        }

        fn forEachNodeWithContext(self: *Self, node: *Node, comptime Context: type, ctx: Context, callback: *const fn (ctx: Context, K, V) void) void {
            for (node.next) |element| {
                if (element) |elem| {
                    self.forEachNodeWithContext(elem.node, Context, ctx, callback);

                    callback(ctx, elem.key, elem.value);
                }
            }
        }

        fn randLevel(self: *Self) usize {
            self.rand.seed(@as(u64, @intCast(std.time.microTimestamp())));
            const random = self.rand.random();

            const f: f64 = @as(f64, @floatFromInt(random.int(u63)));
            const r = f / @as(f64, @floatFromInt(1 << 63));

            var level: usize = 1;
            while (level < self.cfg.max_level and r < self.probarr.items[level]) {
                level += 1;
            }
            return level;
        }

        fn probabArr(allocator: *const Allocator, probability: f64, maxLevel: usize) !std.ArrayList(f64) {
            var table = try std.ArrayList(f64).initCapacity(@constCast(allocator).*, maxLevel);
            errdefer table.deinit();

            for (0..maxLevel) |i| {
                try table.insert(i, math.pow(f64, probability, @as(f64, @floatFromInt(i))));
            }
            return table;
        }

        fn newNode(allocator: *const Allocator, level: usize) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{
                .next = try allocator.alloc(?*Element, level),
            };
            for (0..level) |idx| {
                node.next[idx] = null;
            }

            return node;
        }

        fn newElement(allocator: *const Allocator, level: usize, key: K, value: V) !*Element {
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

const std = @import("std");
const builtin = @import("builtin");

const gigabitsPerGiB: f64 = 8.0 * 1024 * 1024 * 1024;

// MMin is the minimum Bloom filter bits count
const MMin = 2;
// KMin is the minimum number of keys
const KMin = 1;
// Uint64Bytes is the number of bytes in type uint64
const Uint64Bytes = 8;

pub fn Filter(comptime T: type) type {
    comptime {
        switch (T) {
            u32, u64, u128 => {},
            else => @compileError("can not apply for " ++ @typeName(T) ++ "; Supported: u32, u64, u128."),
        }
    }

    const FnvType = switch (T) {
        inline u32 => std.hash.Fnv1a_32.init(),
        inline u64 => std.hash.Fnv1a_64.init(),
        inline u128 => std.hash.Fnv1a_128.init(),
        else => unreachable,
    };

    return struct {
        const Self = @This();

        pub const Error = error{
            Incompatible,
            MinimumBitsRequired,
            KeysNotUnique,
        };

        mu: std.Thread.Mutex = std.Thread.Mutex{},
        allocator: std.mem.Allocator,
        bits: []T,
        keys: []T,
        nbits: usize,
        nelements: usize,

        // Filter with random keys
        //
        // nbits is the size of the Bloom filter, in bits, >= 2
        // nelements is the number of random keys, >= 1
        pub fn init(nbits: usize, nelements: usize, allocator: std.mem.Allocator) !Self {
            const keys = try newRandKeys(nelements, allocator);
            defer allocator.free(keys);

            return try initWithKeys(nbits, keys, allocator);
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.bits);
            self.allocator.free(self.keys);
        }

        // Create Bloom filter with random CSPRNG keys
        pub fn initOptimal(maxN: usize, p: f80, allocator: std.mem.Allocator) !Self {
            const nbits = optimalNBits(maxN, p);
            const nelements = optimalNElements(nbits, maxN);
            std.debug.print(
                "New optimal bloom filter :: requested max elements (n):{}, probability of collision (p):{} -> recommends -> bits (m): {} ({} GiB), number of keys (k): {}",
                .{
                    maxN,
                    p,
                    nbits,
                    @divTrunc(nbits, gigabitsPerGiB),
                    nelements,
                },
            );
            return try init(nbits, nelements, allocator);
        }

        pub fn size(self: *Self) usize {
            return self.nbits;
        }

        pub fn countKeys(self: *Self) usize {
            return self.keys.len;
        }

        // Add a hashable item, v, to the filter
        pub fn Add(self: *Self, v: *@TypeOf(FnvType)) !void {
            self.mu.lock();
            defer self.mu.unlock();

            const hashes: []T = try self.hash(v);
            defer self.allocator.free(hashes);

            for (hashes) |item| {
                const i: T = item % @as(T, @intCast(self.nbits));

                const left = @as(switch (T) {
                    inline u32 => u5,
                    inline u64 => u6,
                    inline u128 => u7,
                    else => unreachable,
                }, @intCast(i & switch (T) {
                    inline u32 => 0x1f,
                    inline u64 => 0x3f,
                    inline u128 => 0x7f,
                    else => unreachable,
                }));

                const pos: usize = @as(usize, @intCast(i >> switch (T) {
                    inline u32 => 5,
                    inline u64 => 6,
                    inline u128 => 7,
                    else => unreachable,
                }));
                self.bits[pos] |= @as(T, @intCast(1)) << left;
            }
            self.nelements += 1;
        }

        // Contains tests if f contains v
        // false: f definitely does not contain value v
        // true:  f maybe contains value v
        pub fn Contains(self: *Self, v: *@TypeOf(FnvType)) !bool {
            self.mu.lock();
            defer self.mu.unlock();

            var r: T = 1;

            const hashes: []T = try self.hash(v);
            defer self.allocator.free(hashes);

            for (hashes) |item| {
                const i = item % self.nbits;
                const left = @as(switch (T) {
                    inline u32 => u5,
                    inline u64 => u6,
                    inline u128 => u7,
                    else => unreachable,
                }, @intCast(i & switch (T) {
                    inline u32 => 0x1f,
                    inline u64 => 0x3f,
                    inline u128 => 0x7f,
                    else => unreachable,
                }));

                const pos: usize = @as(usize, @intCast(i >> switch (T) {
                    inline u32 => 5,
                    inline u64 => 6,
                    inline u128 => 7,
                    else => unreachable,
                }));
                r &= (self.bits[pos] >> left) & 1;
            }

            return uint64ToBool(r);
        }

        // Copy f to a new Bloom filter
        pub fn Copy(self: *Self) !Self {
            self.mu.lock();
            defer self.mu.unlock();

            var out = try self.compatible();
            std.mem.copyForwards(T, out.bits, self.bits);

            out.nelements = self.nelements;
            return out;
        }

        // UnionInPlace merges Bloom filter f2 into f
        pub fn UnionInPlace(self: *Self, f2: *Self) !Self {
            if (!self.IsCompatible(f2)) {
                return Error.Incompatible;
            }

            self.mu.lock();
            defer self.mu.unlock();

            for (f2.bits, 0..) |bitword, i| {
                self.bits[i] |= bitword;
            }
            return self;
        }

        // Union merges f2 and f2 into a new Filter out
        pub fn Union(self: *Self, f2: *Self) !Self {
            if (!self.IsCompatible(f2)) {
                return Error.Incompatible;
            }

            self.mu.lock();
            defer self.mu.unlock();

            var out = try self.compatible();

            for (f2.bits, 0..) |bitword, i| {
                out.bits[i] = self.bits[i] | bitword;
            }
            return out;
        }

        // IsCompatible is true if f and f2 can be Union()ed together
        pub fn IsCompatible(self: *Self, f2: *Self) bool {
            self.mu.lock();
            defer self.mu.unlock();

            f2.mu.lock();
            defer f2.mu.unlock();

            // 0 is true, non-0 is false
            var compat = self.nbits() ^ f2.nbits();
            compat |= self.countKeys() ^ f2.countKeys();
            compat |= noBranchCompareUint64s(self.keys, f2.keys);

            return uint64ToBool(compat ^ compat);
        }

        // optimalNElements calculates the optimal nelements value for creating a new Bloom filter
        // maxn is the maximum anticipated number of elements
        fn optimalNElements(m: usize, maxN: usize) usize {
            const v = std.math.ceil(m * std.math.ln2 / maxN);
            return @as(usize, @intCast(v));
        }

        // optimalNBits calculates the optimal nbits value for creating a new Bloom filter
        // p is the desired false positive probability
        // optimal = ceiling( - n * ln(p) / ln(2)**2 )
        fn optimalNBits(maxN: usize, p: f80) usize {
            const v = std.math.ceil(-maxN * std.math.log(f80, 10, p) / (std.math.ln2 ** 2));
            return @as(usize, @intCast(v));
        }

        // Hashable -> hashes
        fn hash(self: *Self, v: anytype) ![]T {
            const rawHash: T = v.final();

            const hashes = try self.allocator.alloc(T, self.keys.len);
            for (self.keys, 0..) |item, i| {
                hashes[i] = rawHash ^ item;
            }
            return hashes;
        }

        fn uint64ToBool(x: T) bool {
            return x != 0;
        }

        // returns 0 if equal, does not compare len(b0) with len(b1)
        fn noBranchCompareUint64s(b0: []T, b1: []T) T {
            var r: T = 0;
            for (0..b0.len) |i| {
                r |= b0[i] ^ b1[i];
            }
            return r;
        }

        fn newBits(nbits: usize, allocator: std.mem.Allocator) ![]T {
            if (nbits < MMin) {
                return Error.MinimumBitsRequired;
            }

            const t = comptime @typeInfo(T).int.bits;
            return try allocator.alloc(T, @as(usize, @intCast(@divTrunc(nbits + t - 1, t))));
        }

        fn newKeys(nelements: usize, allocator: std.mem.Allocator) ![]T {
            if (nelements < KMin) {
                return Error.MinimumBitsRequired;
            }
            return try allocator.alloc(T, nelements);
        }

        fn newKeysCopy(origKeys: []T, allocator: std.mem.Allocator) ![]T {
            if (!uniqueKeys(origKeys)) {
                return Error.KeysNotUnique;
            }
            const keys = try newKeys(origKeys.len, allocator);
            std.mem.copyForwards(T, keys, origKeys);

            return keys;
        }

        fn newWithKeysAndBits(nbits: usize, keys: []T, bits: []T, nelements: usize, allocator: std.mem.Allocator) !Self {
            const f = try initWithKeys(nbits, keys, allocator);
            std.mem.copyForwards(T, f.bits, bits);

            f.nelements = nelements;
            return f;
        }

        // true if all keys are unique
        fn uniqueKeys(keys: []T) bool {
            for (0..keys.len - 1) |j| {
                const elemj = keys[j];
                if (j == 0) continue;

                for (1..j) |i| {
                    const elemi = keys[i];
                    if (elemi == elemj) {
                        return false;
                    }
                }
            }
            return true;
        }

        // Creates a new Filter from user-supplied origKeys
        fn initWithKeys(nbits: usize, origKeys: []T, allocator: std.mem.Allocator) !Self {
            const bits = try newBits(nbits, allocator);
            const keys = try newKeysCopy(origKeys, allocator);

            return Self{
                .allocator = allocator,
                .nbits = nbits,
                .nelements = 0,
                .bits = bits,
                .keys = keys,
            };
        }

        fn compatible(self: *Self) !Self {
            return try initWithKeys(self.nbits, self.keys, self.allocator);
        }

        fn newRandKeys(nelements: usize, allocator: std.mem.Allocator) ![]T {
            var rand = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
            rand.seed(@as(u64, @intCast(std.time.nanoTimestamp())));

            const random = rand.random();

            const keys = try allocator.alloc(T, nelements);
            for (0..nelements) |i| {
                keys[i] = random.int(T);
            }

            return keys;
        }
    };
}

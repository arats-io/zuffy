const std = @import("std");
const builtin = @import("builtin");

const gigabitsPerGiB: f64 = 8.0 * 1024 * 1024 * 1024;

// MMin is the minimum Bloom filter bits count
const MMin = 2;
// KMin is the minimum number of keys
const KMin = 1;

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
            InvalidCheecksum,
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

        pub fn nBits(self: *Self) usize {
            return self.nbits;
        }
        pub fn nElements(self: *Self) usize {
            return self.nelements;
        }

        pub fn keysSize(self: *Self) usize {
            return self.keys.len;
        }
        pub fn bitsSize(self: *Self) usize {
            return self.bits.len;
        }

        // Add a hashable item, v, to the filter
        pub fn add(self: *Self, v: *@TypeOf(FnvType)) !void {
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
        pub fn contains(self: *Self, v: *@TypeOf(FnvType)) !bool {
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
        pub fn copy(self: *Self) !Self {
            self.mu.lock();
            defer self.mu.unlock();

            var out = try self.compatible();
            std.mem.copyForwards(T, out.bits, self.bits);

            out.nelements = self.nelements;
            return out;
        }

        // UnionInPlace merges Bloom filter f2 into f
        pub fn unionInPlace(self: *Self, f2: *Self) !Self {
            if (!self.isCompatible(f2)) {
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
        pub fn unionAsCopy(self: *Self, f2: *Self) !Self {
            if (!self.isCompatible(f2)) {
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
        pub fn isCompatible(self: *Self, f2: *Self) bool {
            self.mu.lock();
            defer self.mu.unlock();

            f2.mu.lock();
            defer f2.mu.unlock();

            // 0 is true, non-0 is false
            var compat = self.nbits() ^ f2.nbits();
            compat |= self.keysSize() ^ f2.keysSize();
            compat |= noBranchCompareUint64s(self.keys, f2.keys);

            return uint64ToBool(compat ^ compat);
        }

        // FalsePosititveProbability is the upper-bound probability of false positives
        //  (1 - exp(-k*(n+0.5)/(m-1))) ** k
        pub fn falsePosititveProbability(self: *Self) f64 {
            const k = @as(f64, @floatFromInt(self.keysSize()));
            const n = @as(f64, @floatFromInt(self.nElements()));
            const m = @as(f64, @floatFromInt(self.nBits()));
            return std.math.pow(f64, 1.0 - std.math.exp(-k) * @divExact(n + 0.5, m - 1.0), k);
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

        pub fn marchal(self: *Self) ![]u8 {
            self.mu.lock();
            defer self.mu.unlock();

            var bm = BinaryMarshaler.init(self, self.allocator);
            return try bm.bytes();
        }

        pub fn unmarchal(self: *Self, data: []const u8) !void {
            self.mu.lock();
            defer self.mu.unlock();

            var bm = BinaryUnmarshaler.init(self, self.allocator);
            return try bm.read(data);
        }

        pub fn eql(self: Self, other: Self) bool {
            if (!std.mem.eql(T, self.bits, other.bits)) return false;
            if (!std.mem.eql(T, self.keys, other.keys)) return false;

            if (self.nbits != other.nbits) return false;
            if (self.nelements != other.nelements) return false;

            return true;
        }

        const BinaryMarshaler = struct {
            allocator: std.mem.Allocator,
            filter: *Filter(T),

            pub fn init(filter: *Filter(T), allocator: std.mem.Allocator) BinaryMarshaler {
                return BinaryMarshaler{
                    .filter = filter,
                    .allocator = allocator,
                };
            }

            pub fn bytes(self: *BinaryMarshaler) ![]u8 {
                var out = std.ArrayList(u8).init(self.allocator);
                errdefer out.clearAndFree();

                var wr = out.writer();
                try wr.writeInt(usize, self.filter.nbits, .little);
                try wr.writeInt(usize, self.filter.nelements, .little);

                try wr.writeInt(usize, self.filter.bitsSize(), .little);
                for (self.filter.bits) |b| {
                    try wr.writeInt(T, b, .little);
                }

                try wr.writeInt(usize, self.filter.keysSize(), .little);
                for (self.filter.keys) |k| {
                    try wr.writeInt(T, k, .little);
                }

                var sha512 = std.crypto.hash.sha2.Sha512.init(.{});
                sha512.update(out.items);

                var sha512out: [64]u8 = undefined;
                sha512.final(sha512out[0..]);

                for (sha512out[0..]) |b| {
                    try wr.writeInt(u8, b, .little);
                }

                return out.toOwnedSlice();
            }
        };

        const BinaryUnmarshaler = struct {
            allocator: std.mem.Allocator,
            filter: *Filter(T),

            pub fn init(filter: *Filter(T), allocator: std.mem.Allocator) BinaryUnmarshaler {
                return BinaryUnmarshaler{
                    .filter = filter,
                    .allocator = allocator,
                };
            }

            pub fn read(self: *BinaryUnmarshaler, data: []const u8) !void {
                var stream = std.io.fixedBufferStream(data);
                var reader = stream.reader();

                const nbits = try reader.readInt(usize, .little);
                const nelements = try reader.readInt(usize, .little);

                const bits_size = try reader.readInt(usize, .little);
                var bits = try self.allocator.alloc(T, bits_size);
                errdefer self.allocator.free(bits);
                for (0..bits_size) |i| {
                    bits[i] = try reader.readInt(T, .little);
                }

                const keys_size = try reader.readInt(usize, .little);
                var keys = try self.allocator.alloc(T, keys_size);
                errdefer self.allocator.free(keys);
                for (0..keys_size) |i| {
                    keys[i] = try reader.readInt(T, .little);
                }

                var checksum: []u8 = try self.allocator.alloc(u8, 64);
                defer self.allocator.free(checksum);
                errdefer self.allocator.free(checksum);
                for (0..64) |i| {
                    checksum[i] = try reader.readInt(u8, .little);
                }

                var sha512 = std.crypto.hash.sha2.Sha512.init(.{});
                sha512.update(data[0 .. data.len - 64]);

                var sha512out: [64]u8 = undefined;
                sha512.final(sha512out[0..]);

                if (!std.mem.eql(u8, sha512out[0..], checksum[0..])) {
                    return Error.InvalidCheecksum;
                }

                self.filter.allocator.free(self.filter.keys);
                self.filter.allocator.free(self.filter.bits);

                self.filter.nbits = nbits;
                self.filter.nelements = nelements;

                self.filter.keys.ptr = keys.ptr;
                self.filter.keys.len = keys.len;

                self.filter.bits.ptr = bits.ptr;
                self.filter.bits.len = bits.len;
            }
        };
    };
}

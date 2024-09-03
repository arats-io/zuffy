const std = @import("std");
const builtin = @import("builtin");

const gigabitsPerGiB: f64 = 8.0 * 1024 * 1024 * 1024;

// MMin is the minimum Bloom filter bits count
const MMin = 2;
// KMin is the minimum number of keys
const KMin = 1;
// Uint64Bytes is the number of bytes in type uint64
const Uint64Bytes = 8;

const Self = @This();

pub const Error = error{
    Incompatible,
    MinimumBitsRequired,
    KeysNotUnique,
};

mu: std.Thread.Mutex = std.Thread.Mutex{},
allocator: std.mem.Allocator,
bits: []u64,
keys: []u64,
m: usize, // number of bits the "bits" field should recognize
n: usize, // number of inserted elements

// OptimalK calculates the optimal k value for creating a new Bloom filter
// maxn is the maximum anticipated number of elements
fn optimalK(m: usize, maxN: usize) usize {
    const v = std.math.ceil(m * std.math.ln2 / maxN);
    return @as(usize, @intCast(v));
}

// OptimalM calculates the optimal m value for creating a new Bloom filter
// p is the desired false positive probability
// optimal m = ceiling( - n * ln(p) / ln(2)**2 )
fn optimalM(maxN: usize, p: f64) usize {
    const v = std.math.ceil(-maxN * std.math.log(f64, 10, p) / (std.math.ln2 * std.math.ln2));
    return @as(usize, @intCast(v));
}

// Hashable -> hashes
fn hash(self: *Self, v: *std.hash.Fnv1a_64) ![]u64 {
    const rawHash: u64 = v.final();

    const hashes = try self.allocator.alloc(u64, self.keys.len);
    for (self.keys, 0..) |item, i| {
        hashes[i] = rawHash ^ item;
    }
    return hashes;
}

// M is the size of Bloom filter, in bits
pub fn M(self: *Self) usize {
    return self.m;
}

// K is the count of keys
pub fn K(self: *Self) usize {
    return self.keys.len;
}

// Add a hashable item, v, to the filter
pub fn Add(self: *Self, v: *std.hash.Fnv1a_64) !void {
    self.mu.lock();
    defer self.mu.unlock();

    const hashes = try self.hash(v);
    defer self.allocator.free(hashes);

    for (hashes) |item| {
        const i: u64 = item % @as(u64, @intCast(self.m));
        const left: u6 = @as(u6, @intCast(i & 0x3f));

        const pos: usize = @as(usize, @intCast(i >> 6));
        self.bits[pos] |= @as(u64, @intCast(1)) << left;
    }
    self.n += 1;
}

// Contains tests if f contains v
// false: f definitely does not contain value v
// true:  f maybe contains value v
pub fn Contains(self: *Self, v: *std.hash.Fnv1a_64) !bool {
    self.mu.lock();
    defer self.mu.unlock();

    var r: u64 = 1;

    const hashes = try self.hash(v);
    defer self.allocator.free(hashes);

    for (hashes) |item| {
        const i = item % self.m;
        const left: u6 = @as(u6, @intCast(i & 0x3f));

        const pos: usize = @as(usize, @intCast(i >> 6));
        r &= (self.bits[pos] >> left) & 1;
    }

    return uint64ToBool(r);
}

// Copy f to a new Bloom filter
pub fn Copy(self: *Self) !Self {
    self.mu.lock();
    defer self.mu.unlock();

    var out = try self.Compatible();
    std.mem.copyForwards(u64, out.bits, self.bits);

    out.n = self.n;
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

    var out = try self.Compatible();

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
    var compat = self.M() ^ f2.M();
    compat |= self.K() ^ f2.K();
    compat |= noBranchCompareUint64s(self.keys, f2.keys);

    return uint64ToBool(compat ^ compat);
}

fn uint64ToBool(x: u64) bool {
    return x != 0;
}

// returns 0 if equal, does not compare len(b0) with len(b1)
fn noBranchCompareUint64s(b0: []u64, b1: []u64) u64 {
    var r: u64 = 0;
    for (b0, 0..) |b0i, i| {
        r |= b0i ^ b1[i];
    }
    return r;
}

fn newBits(m: usize, allocator: std.mem.Allocator) ![]u64 {
    if (m < MMin) {
        return Error.MinimumBitsRequired;
    }

    return try allocator.alloc(u64, @as(usize, @intCast(@divTrunc(m + 63, 64))));
}

fn newKeysBlank(k: usize, allocator: std.mem.Allocator) ![]u64 {
    if (k < KMin) {
        return Error.MinimumBitsRequired;
    }
    return try allocator.alloc(u64, k);
}

fn newKeysCopy(origKeys: []u64, allocator: std.mem.Allocator) ![]u64 {
    if (!UniqueKeys(origKeys)) {
        return Error.KeysNotUnique;
    }
    const keys = try newKeysBlank(origKeys.len, allocator);
    std.mem.copyForwards(u64, keys, origKeys);

    return keys;
}

fn newWithKeysAndBits(m: u64, keys: []u64, bits: []u64, n: u64, allocator: std.mem.Allocator) !Self {
    const f = try NewWithKeys(m, keys, allocator);
    std.mem.copyForwards(u64, f.bits, bits);

    f.n = n;
    return f;
}

// UniqueKeys is true if all keys are unique
fn UniqueKeys(keys: []u64) bool {
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

// NewWithKeys creates a new Filter from user-supplied origKeys
fn NewWithKeys(m: usize, origKeys: []u64, allocator: std.mem.Allocator) !Self {
    const bits = try newBits(m, allocator);
    const keys = try newKeysCopy(origKeys, allocator);

    return Self{
        .allocator = allocator,
        .m = m,
        .n = 0,
        .bits = bits,
        .keys = keys,
    };
}

// NewCompatible Filter compatible with f
fn Compatible(self: *Self) !Self {
    return try NewWithKeys(self.m, self.keys, self.allocator);
}

// New Filter with CSPRNG keys
//
// m is the size of the Bloom filter, in bits, >= 2
//
// k is the number of random keys, >= 1
pub fn init(m: usize, k: usize, allocator: std.mem.Allocator) !Self {
    const keys = try newRandKeys(k, allocator);
    defer allocator.free(keys);

    return try NewWithKeys(m, keys, allocator);
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.bits);
    self.allocator.free(self.keys);
}

fn newRandKeys(k: usize, allocator: std.mem.Allocator) ![]u64 {
    var rand = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));

    rand.seed(@as(u64, @intCast(std.time.nanoTimestamp())));

    var keys = try allocator.alloc(u64, k);
    for (0..k) |i| {
        const v: u64 = rand.random().int(u64);

        keys[i] = v;
    }

    return keys;
}

// NewOptimal Bloom filter with random CSPRNG keys
pub fn initOptimal(maxN: usize, p: f64, allocator: std.mem.Allocator) !Self {
    const m = optimalM(maxN, p);
    const k = optimalK(m, maxN);
    std.debug.print(
        "New optimal bloom filter :: requested max elements (n):{}, probability of collision (p):{} -> recommends -> bits (m): {} ({} GiB), number of keys (k): {}",
        .{
            maxN,
            p,
            m,
            @divTrunc(m, gigabitsPerGiB),
            k,
        },
    );
    return try init(m, k, allocator);
}

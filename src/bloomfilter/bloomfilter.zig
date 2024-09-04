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
nbits: usize,
nelements: usize,

// New Filter with CSPRNG keys
//
// m is the size of the Bloom filter, in bits, >= 2
//
// k is the number of random keys, >= 1
pub fn init(nbits: usize, nelements: usize, allocator: std.mem.Allocator) !Self {
    const keys = try newRandKeys(nelements, allocator);
    defer allocator.free(keys);

    return try initWithKeys(nbits, keys, allocator);
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.bits);
    self.allocator.free(self.keys);
}

// NewOptimal Bloom filter with random CSPRNG keys
pub fn initOptimal(maxN: usize, p: f64, allocator: std.mem.Allocator) !Self {
    const nbits = optimalNBits(maxN, p);
    const k = optimalNElements(nbits, maxN);
    std.debug.print(
        "New optimal bloom filter :: requested max elements (n):{}, probability of collision (p):{} -> recommends -> bits (m): {} ({} GiB), number of keys (k): {}",
        .{
            maxN,
            p,
            nbits,
            @divTrunc(nbits, gigabitsPerGiB),
            k,
        },
    );
    return try init(nbits, k, allocator);
}

pub fn size(self: *Self) usize {
    return self.nbits;
}

pub fn countKeys(self: *Self) usize {
    return self.keys.len;
}

// Add a hashable item, v, to the filter
pub fn Add(self: *Self, v: *std.hash.Fnv1a_64) !void {
    self.mu.lock();
    defer self.mu.unlock();

    const hashes = try self.hash(v);
    defer self.allocator.free(hashes);

    for (hashes) |item| {
        const i: u64 = item % @as(u64, @intCast(self.nbits));
        const left: u6 = @as(u6, @intCast(i & 0x3f));

        const pos: usize = @as(usize, @intCast(i >> 6));
        self.bits[pos] |= @as(u64, @intCast(1)) << left;
    }
    self.nelements += 1;
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
        const i = item % self.nbits;
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

    var out = try self.compatible();
    std.mem.copyForwards(u64, out.bits, self.bits);

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
fn optimalNBits(maxN: usize, p: f64) usize {
    const v = std.math.ceil(-maxN * std.math.log(f64, 10, p) / (std.math.ln2 ** 2));
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

fn uint64ToBool(x: u64) bool {
    return x != 0;
}

// returns 0 if equal, does not compare len(b0) with len(b1)
fn noBranchCompareUint64s(b0: []u64, b1: []u64) u64 {
    var r: u64 = 0;
    for (0..b0.len) |i| {
        r |= b0[i] ^ b1[i];
    }
    return r;
}

fn newBits(nbits: usize, allocator: std.mem.Allocator) ![]u64 {
    if (nbits < MMin) {
        return Error.MinimumBitsRequired;
    }

    return try allocator.alloc(u64, @as(usize, @intCast(@divTrunc(nbits + 63, 64))));
}

fn newKeys(nelements: usize, allocator: std.mem.Allocator) ![]u64 {
    if (nelements < KMin) {
        return Error.MinimumBitsRequired;
    }
    return try allocator.alloc(u64, nelements);
}

fn newKeysCopy(origKeys: []u64, allocator: std.mem.Allocator) ![]u64 {
    if (!uniqueKeys(origKeys)) {
        return Error.KeysNotUnique;
    }
    const keys = try newKeys(origKeys.len, allocator);
    std.mem.copyForwards(u64, keys, origKeys);

    return keys;
}

fn newWithKeysAndBits(nbits: u64, keys: []u64, bits: []u64, nelements: u64, allocator: std.mem.Allocator) !Self {
    const f = try initWithKeys(nbits, keys, allocator);
    std.mem.copyForwards(u64, f.bits, bits);

    f.nelements = nelements;
    return f;
}

// UniqueKeys is true if all keys are unique
fn uniqueKeys(keys: []u64) bool {
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
fn initWithKeys(nbits: usize, origKeys: []u64, allocator: std.mem.Allocator) !Self {
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

fn newRandKeys(nelements: usize, allocator: std.mem.Allocator) ![]u64 {
    var rand = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
    rand.seed(@as(u64, @intCast(std.time.nanoTimestamp())));

    const random = rand.random();

    const keys = try allocator.alloc(u64, nelements);
    for (0..nelements) |i| {
        keys[i] = random.int(u64);
    }

    return keys;
}

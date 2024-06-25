const builtin = @import("builtin");
const std = @import("std");

const ints = @import("../../ints.zig");

pub const Crypto = struct {
    const Self = @This();

    pub const Decryptor = struct {
        keys: [3]u32,

        pub fn decrypt(self: *Decryptor, chiper: []const u8, writer: anytype) !void {
            for (chiper) |ch| {
                const v = ch ^ magicByte(&self.keys);
                updatekeys(&self.keys, v);
                try writer.writeByte(v);
            }
        }
    };

    pub const Encryptor = struct {
        keys: [3]u32,

        pub fn encrypt(self: *Encryptor, data: []const u8, writer: anytype) !void {
            for (data) |ch| {
                try writer.writeByte(ch ^ magicByte(&self.keys));
                updatekeys(&self.keys, ch);
            }
        }
    };

    keys: [3]u32,

    pub fn init(password: []const u8) Self {
        const self = Self{ .keys = [3]u32{ 0x12345678, 0x23456789, 0x34567890 } };
        for (password) |ch| {
            updatekeys(@constCast(&self.keys), ch);
        }
        return self;
    }

    pub fn encryptor(self: *Self) Encryptor {
        return Encryptor{ .keys = [3]u32{ self.keys[0], self.keys[1], self.keys[2] } };
    }

    pub fn decriptor(self: *Self) Decryptor {
        return Decryptor{ .keys = [3]u32{ self.keys[0], self.keys[1], self.keys[2] } };
    }
};

const Crc32IEEE = std.hash.crc.Crc(u32, .{
    .polynomial = 0xedb88320,
    .initial = 0xffffffff,
    .reflect_input = false,
    .reflect_output = false,
    .xor_output = 0x00000000,
});

fn updatekeys(keys: *[3]u32, byteValue: u8) void {
    keys.*[0] = crc32update(keys.*[0], byteValue);
    keys.*[1] += keys.*[0] & 0xff;
    keys.*[1] = keys.*[1] * 134775813 + 1;

    const t = keys.*[1] >> 24;
    keys.*[2] = crc32update(keys.*[2], @as(u8, @intCast(t)));
}

fn crc32update(pCrc32: u32, bval: u8) u32 {
    const t = ints.toBytes(u32, (pCrc32 ^ bval) & 0xff, .big);
    return Crc32IEEE.hash(&t) ^ (pCrc32 >> 8);
}

fn magicByte(keys: *[3]u32) u8 {
    const t = keys.*[2] | 2;
    const res = (t * (t ^ 1)) >> 8;
    return @as(u8, @intCast(res));
}

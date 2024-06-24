const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;

const ints = @import("../../ints.zig");
const Buffer = @import("../../bytes/buffer.zig").Buffer;

const eftypes = @import("extra_field_types.zig");

///   ZIP Archive structure
///      [local file header 1]
///      [encryption header 1]
///      [file data 1]
///      [data descriptor 1]
///      .
///      .
///      .
///      [local file header n]
///      [encryption header n]
///      [file data n]
///      [data descriptor n]
///      [archive decryption header]
///      [archive extra data record]
///      [central directory header 1]
///      .
///      .
///      .
///     [central directory header n]
///     [zip64 end of central directory record]
///     [zip64 end of central directory locator]
///     [end of central directory record]
pub const ZipArchive = struct {
    const Self = @This();

    local_file_entries: std.ArrayList(LocalFileEntry),
    archive_decryption_header: ?ArchiveDecryptionHeader,
    archive_extra_data_record: ?ArchiveExtraDataRecord,
    central_diectory_headers: std.ArrayList(CentralDirectoryHeader),
    digital_signature: ?DigitalSignature,
    zip64_eocd_record: ?Zip64EocdRecord,
    zip64_eocd_locator: ?Zip64EocdLocator,
    eocd_record: EocdRecord,
};
pub const DigitalSignature = struct {
    const SIGNATURE = 0x05054b50;

    signature: u32,
    size_of_data: u16,
    signature_data: ?Buffer,
};

pub const CentralDirectoryHeader = struct {
    const Self = @This();
    pub const SIGNATURE = 0x02014b50;

    signature: u32,
    version_made_by: u16,
    version_extract_file: u16,
    bit_flag: u16,
    compressed_method: u16,
    last_modification_time: u16,
    last_modification_date: u16,
    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    filename_len: u16,
    extra_field_len: u16,
    comment_len: u16,
    disk_file_start: u16,
    internal_attributes: u16,
    external_attributes: u32,
    offset_local_header: u32,
    filename: ?Buffer,
    extra_field: ?Buffer,
    comment: ?Buffer,

    pub fn bitFlagToBitSet(self: Self) std.StaticBitSet(@bitSizeOf(u16)) {
        return ints.toBitSet(u16, self.bit_flag);
    }

    pub fn decodeExtraFields(self: Self, handler: anytype) !void {
        if (self.extra_field) |buffer| {
            try eftypes.decodeExtraFields(buffer, handler);
        }
    }
};

pub const EocdRecord = struct {
    pub const SIGNATURE = 0x06054b50;

    signature: u32,
    num_disk: u16,
    num_disk_cd_start: u16,
    cd_records_total_on_disk: u16,
    cd_records_total: u16,
    cd_size: u32,
    offset_start: u32,
    comment_len: u16,
    comment: ?Buffer,
};

pub const Zip64EocdRecord = struct {
    pub const SIGNATURE = 0x06064b50;

    signature: u32,
    size: u64,
    version_made_by: u16,
    version_extract_file: u16,
    num_disk: u32,
    num_disk_cd_start: u32,
    cd_records_on_disk: u64,
    cd_records_total: u64,
    cd_size: u64,
    offset_start: u64,
    extenssion_v2: ?Zip64EocdRecordExtenssionV2,
    extenssion_data: ?Buffer,
};
pub const Zip64EocdRecordExtenssionV2 = struct {
    compression_method: u64,
    compressed_size: u64,
    original_size: u64,
    alg_id: u16,
    bit_len: u16,
    flags: u16,
    hash_id: u16,
    hash_length: u16,
    hash_data: ?Buffer,
};

pub const Zip64EocdLocator = struct {
    pub const SIGNATURE = 0x07064b50;
    signature: u32,
    num_disk_zip64_eocd_start: u32,
    offset_zip64_eocd_record: u64,
    num_disk: u32,
};

pub const LocalFileHeader = struct {
    const Self = @This();
    pub const SIGNATURE = 0x04034b50;

    signature: u32,
    version: u16,
    bit_flag: u16,
    compression_method: u16,
    last_modification_time: u16,
    last_modification_date: u16,
    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    filename_len: u16,
    extra_field_len: u16,
    filename: ?Buffer,
    extra_field: ?Buffer,

    pub fn bitFlagToBitSet(self: Self) std.StaticBitSet(@bitSizeOf(u16)) {
        return ints.toBitSet(u16, self.bit_flag);
    }

    pub fn decodeExtraFields(self: Self, handler: anytype) !void {
        if (self.extra_field) |buffer| {
            try eftypes.decodeExtraFields(buffer, handler);
        }
    }
};

pub const EncryptionHeader = struct {};

pub const DataDescriptor = struct {
    pub const SIGNATURE = 0x08074b50;

    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
};

pub const ArchiveExtraDataRecord = struct {
    pub const SIGNATURE = 0x08064b50;

    extra_field_len: u16,
    extra_field: Buffer,
};

pub const ArchiveDecryptionHeader = struct {
    iv_size: u16,
    iv_data: ?Buffer,
    size: u32,
    format: u16,
    alg_id: u16,
    bit_len: u16,
    flags: u16,
    erd_size: u16,
    erd_data: ?Buffer,
    reserved01: u32,
    reserved02: ?Buffer,
    v_size: u16,
    v_data: ?Buffer,
    v_crc32: u32,
};

pub const LocalFileEntry = struct {
    file_header: LocalFileHeader,
    encryption_header: ?[]const u8 = null,
    encryption_key: ?Buffer = null,
    content: ?Buffer = null,
    data_descriptor: ?DataDescriptor = null,

    @"$extra": struct {
        external_file: ?std.fs.File = null,
        external_bytes: ?Buffer = null,
        content_length: u64 = 0,
        content_startpos: u64 = 0,
        crypt_password: ?[]const u8 = null,
    },
};

pub fn extract(allocator: mem.Allocator, source: anytype) !ZipArchive {
    var parse_source = source;
    var eocd: ?EocdRecord = null;

    // parsing the end of central directory record, which is only one
    var pos = try parse_source.seekableStream().getEndPos() - 4;
    while (pos > 0) : (pos -= 1) {
        try parse_source.seekableStream().seekTo(pos);

        const signature = try parse_source.reader().readInt(u32, .little);
        if (signature != EocdRecord.SIGNATURE) {
            continue;
        }

        const num_disk = try parse_source.reader().readInt(u16, .little);
        const num_disk_cd_start = try parse_source.reader().readInt(u16, .little);
        const cd_records_total_on_disk = try parse_source.reader().readInt(u16, .little);
        const cd_records_total = try parse_source.reader().readInt(u16, .little);
        const cd_size = try parse_source.reader().readInt(u32, .little);
        const offset_start = try parse_source.reader().readInt(u32, .little);
        const comment_len = try parse_source.reader().readInt(u16, .little);

        const comment = if (comment_len > 0) cblk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            for (0..comment_len) |_| {
                const byte: u8 = try parse_source.reader().readByte();
                try tmp.writeByte(byte);
            }
            break :cblk tmp;
        } else null;

        eocd = EocdRecord{
            .signature = signature,
            .num_disk = num_disk,
            .num_disk_cd_start = num_disk_cd_start,
            .cd_records_total_on_disk = cd_records_total_on_disk,
            .cd_records_total = cd_records_total,
            .cd_size = cd_size,
            .offset_start = offset_start,
            .comment_len = comment_len,
            .comment = comment,
        };
        break;
    }
    if (eocd.?.signature != EocdRecord.SIGNATURE) return error.BadData;
    // end of parsing the end of central directory record

    // parsing the central directory header n
    var cdheaders = std.ArrayList(CentralDirectoryHeader).init(allocator);

    const start_pos = eocd.?.offset_start + eocd.?.num_disk_cd_start;
    try parse_source.seekableStream().seekTo(start_pos);
    const reader = parse_source.reader();

    for (0..eocd.?.cd_records_total) |idx| {
        _ = idx;
        const signature = try reader.readInt(u32, .little);
        const version_made_by = try reader.readInt(u16, .little);
        const version_extract_file = try reader.readInt(u16, .little);
        const bit_flag = try reader.readInt(u16, .little);
        const compressed_method = try reader.readInt(u16, .little);
        const last_modification_time = try reader.readInt(u16, .little);
        const last_modification_date = try reader.readInt(u16, .little);
        const crc32 = try reader.readInt(u32, .little);
        const compressed_size = try reader.readInt(u32, .little);
        const uncompressed_size = try reader.readInt(u32, .little);
        const filename_len = try reader.readInt(u16, .little);
        const extra_field_len = try reader.readInt(u16, .little);
        const comment_len = try reader.readInt(u16, .little);
        const disk_file_start = try reader.readInt(u16, .little);
        const internal_attributes = try reader.readInt(u16, .little);
        const external_attributes = try reader.readInt(u32, .little);
        const offset_local_header = try reader.readInt(u32, .little);

        const filename = if (filename_len > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            for (0..filename_len) |_| {
                const byte: u8 = try reader.readByte();
                try tmp.writeByte(byte);
            }
            break :blk tmp;
        } else null;

        const extra_field = if (extra_field_len > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            for (0..extra_field_len) |_| {
                const byte: u8 = try reader.readByte();
                try tmp.writeByte(byte);
            }
            break :blk tmp;
        } else null;

        const comment = if (comment_len > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            for (0..comment_len) |_| {
                const byte: u8 = try reader.readByte();
                try tmp.writeByte(byte);
            }
            break :blk tmp;
        } else null;

        if (signature != CentralDirectoryHeader.SIGNATURE) return error.BadData;

        const item = CentralDirectoryHeader{
            .signature = signature,
            .version_made_by = version_made_by,
            .version_extract_file = version_extract_file,
            .bit_flag = bit_flag,
            .compressed_method = compressed_method,
            .last_modification_time = last_modification_time,
            .last_modification_date = last_modification_date,
            .crc32 = crc32,
            .compressed_size = compressed_size,
            .uncompressed_size = uncompressed_size,
            .filename_len = filename_len,
            .extra_field_len = extra_field_len,
            .comment_len = comment_len,
            .disk_file_start = disk_file_start,
            .internal_attributes = internal_attributes,
            .external_attributes = external_attributes,
            .offset_local_header = offset_local_header,
            .filename = filename,
            .extra_field = extra_field,
            .comment = comment,
        };

        try cdheaders.append(item);
    }
    // ending of parsing the central directory header n

    // parsing digital signature
    const signature = try reader.readInt(u32, .little);
    if (signature != EocdRecord.SIGNATURE and signature != DigitalSignature.SIGNATURE) {
        return error.BadData;
    }

    const ds = if (signature == DigitalSignature.SIGNATURE) blkds: {
        const size_of_data = try reader.readInt(u16, .little);
        const signature_data = if (size_of_data > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            for (0..size_of_data) |_| {
                const byte: u8 = try reader.readByte();
                try tmp.writeByte(byte);
            }
            break :blk tmp;
        } else null;

        break :blkds DigitalSignature{
            .signature = signature,
            .size_of_data = size_of_data,
            .signature_data = signature_data,
        };
    } else null;
    // ending of parsing digital signature

    // parsing the zip64 end of central directory record & locator
    var zip64_eocd_record: ?Zip64EocdRecord = null;
    var zip64_eocd_locator: ?Zip64EocdLocator = null;
    if (eocd.?.num_disk == 0xffff) {
        zip64_eocd_record = Zip64EocdRecord{
            .signature = try reader.readInt(u32, .little),
            .size = try reader.readInt(u64, .little),
            .version_made_by = try reader.readInt(u16, .little),
            .version_extract_file = try reader.readInt(u16, .little),
            .num_disk = try reader.readInt(u32, .little),
            .num_disk_cd_start = try reader.readInt(u32, .little),
            .cd_records_on_disk = try reader.readInt(u64, .little),
            .cd_records_total = try reader.readInt(u64, .little),
            .cd_size = try reader.readInt(u64, .little),
            .offset_start = try reader.readInt(u64, .little),
            .extenssion_v2 = null,
            .extenssion_data = null,
        };
        // version 1
        if (zip64_eocd_record.?.version_made_by == 1) {
            // Size = SizeOfFixedFields + SizeOfVariableData - 12.
            const extensible_data_len = zip64_eocd_record.?.size - 56 - 12;
            zip64_eocd_record.?.extenssion_data = if (extensible_data_len > 0) blk: {
                var tmp = Buffer.initWithFactor(allocator, 5);
                for (0..extensible_data_len) |_| {
                    const byte: u8 = try reader.readByte();
                    try tmp.writeByte(byte);
                }
                break :blk tmp;
            } else null;
        }
        // version 2
        if (zip64_eocd_record.?.version_made_by == 2) {
            zip64_eocd_record.?.extenssion_v2 = Zip64EocdRecordExtenssionV2{
                .compression_method = try reader.readInt(u64, .little),
                .compressed_size = try reader.readInt(u64, .little),
                .original_size = try reader.readInt(u64, .little),
                .alg_id = try reader.readInt(u16, .little),
                .bit_len = try reader.readInt(u16, .little),
                .flags = try reader.readInt(u16, .little),
                .hash_id = try reader.readInt(u16, .little),
                .hash_length = try reader.readInt(u16, .little),
                .hash_data = null,
            };
            const size = zip64_eocd_record.?.extenssion_v2.?.hash_length;
            zip64_eocd_record.?.extenssion_v2.?.hash_data = if (size > 0) blk: {
                var tmp = Buffer.initWithFactor(allocator, 5);
                for (0..size) |_| {
                    const byte: u8 = try reader.readByte();
                    try tmp.writeByte(byte);
                }
                break :blk tmp;
            } else null;
        }

        if (zip64_eocd_record.?.signature != Zip64EocdRecord.SIGNATURE) return error.BadData;

        zip64_eocd_locator = Zip64EocdLocator{
            .signature = try reader.readInt(u32, .little),
            .num_disk_zip64_eocd_start = try reader.readInt(u32, .little),
            .offset_zip64_eocd_record = try reader.readInt(u64, .little),
            .num_disk = try reader.readInt(u32, .little),
        };
        if (zip64_eocd_locator.?.signature != Zip64EocdLocator.SIGNATURE) return error.BadData;
    }
    // end of parsing the zip64 end of central directory record & locator

    return ZipArchive{
        .local_file_entries = std.ArrayList(LocalFileEntry).init(allocator),
        .archive_decryption_header = null,
        .archive_extra_data_record = null,
        .central_diectory_headers = cdheaders,
        .digital_signature = ds,
        .zip64_eocd_record = zip64_eocd_record,
        .zip64_eocd_locator = zip64_eocd_locator,
        .eocd_record = eocd.?,
    };
}

pub fn readLocalFileEntry(allocator: mem.Allocator, cdheader: CentralDirectoryHeader, seekableStream: anytype, in_reader: anytype) !LocalFileEntry {
    try seekableStream.seekTo(cdheader.offset_local_header);

    const signature = try in_reader.readInt(u32, .little);
    const version = try in_reader.readInt(u16, .little);
    const bit_flag = try in_reader.readInt(u16, .little);
    const compression_method = try in_reader.readInt(u16, .little);
    const last_modification_time = try in_reader.readInt(u16, .little);
    const last_modification_date = try in_reader.readInt(u16, .little);
    const crc32 = try in_reader.readInt(u32, .little);
    const compressed_size = try in_reader.readInt(u32, .little);
    const uncompressed_size = try in_reader.readInt(u32, .little);
    const filename_len = try in_reader.readInt(u16, .little);
    const extra_field_len = try in_reader.readInt(u16, .little);

    if (signature != 0x04034b50)
        return error.BadHeader;

    const filename = if (filename_len > 0) blk: {
        var tmp = Buffer.initWithFactor(allocator, 5);
        errdefer tmp.deinit();

        for (0..filename_len) |_| {
            const byte: u8 = try in_reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    const extra_field = if (extra_field_len > 0) blk: {
        var tmp = Buffer.initWithFactor(allocator, 5);
        errdefer tmp.deinit();

        for (0..extra_field_len) |_| {
            const byte: u8 = try in_reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    const header = LocalFileHeader{
        .signature = signature,
        .version = version,
        .bit_flag = bit_flag,
        .compression_method = compression_method,
        .last_modification_time = last_modification_time,
        .last_modification_date = last_modification_date,
        .crc32 = crc32,
        .compressed_size = compressed_size,
        .uncompressed_size = uncompressed_size,
        .filename_len = filename_len,
        .extra_field_len = extra_field_len,
        .filename = filename,
        .extra_field = extra_field,
    };

    const content_size = if (header.compression_method == 0) header.uncompressed_size else header.compressed_size;
    //var content = Buffer.initWithFactor(allocator, 5);

    const start = try seekableStream.getPos();
    try in_reader.skipBytes(content_size, .{});
    //for (0..content_size) |_| {
    //    const byte: u8 = try in_reader.readByte();
    //    try content.writeByte(byte);
    //}

    const password = "";

    var fileentry = LocalFileEntry{
        .file_header = header,

        .@"$extra" = .{
            .content_length = content_size,
            .content_startpos = start,
            .crypt_password = password,
        },
    };

    const bitflag = header.bitFlagToBitSet();

    // Local file encryption header
    if (bitflag.isSet(0)) {
        fileentry.encryption_header = (try in_reader.readBoundedBytes(12)).constSlice();

        var encryption_key = Buffer.init(allocator);
        errdefer encryption_key.deinit();

        var crypto = Crypto.init(password);
        var decryptor = crypto.decriptor();
        try decryptor.decrypt(fileentry.encryption_header.?, encryption_key.writer());

        fileentry.encryption_key = encryption_key;
    }
    if (bitflag.isSet(6)) {
        std.debug.print("Strong encryption\n", .{});
    }
    if (bitflag.isSet(3)) {
        var CRC32: u32 = try in_reader.readInt(u32, .little);
        if (CRC32 == DataDescriptor.SIGNATURE) {
            CRC32 = try in_reader.readInt(u32, .little);
        }
        fileentry.data_descriptor = DataDescriptor{
            .crc32 = CRC32,
            .compressed_size = try in_reader.readInt(u32, .little),
            .uncompressed_size = try in_reader.readInt(u32, .little),
        };
    }

    return fileentry;
}

const Crypto = struct {
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

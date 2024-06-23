const std = @import("std");
const mem = std.mem;

const Buffer = @import("../../bytes/buffer.zig").Buffer;

const eftypes = @import("extra_field_types.zig");

// [local file header 1]
// [encryption header 1]
// [file data 1]
// [data descriptor 1]
// .
// .
// .
// [local file header n]
// [encryption header n]
// [file data n]
// [data descriptor n]
// [archive decryption header]
// [archive extra data record]
// [central directory header 1]
// .
// .
// .
// [central directory header n]
// [zip64 end of central directory record]
// [zip64 end of central directory locator]
// [end of central directory record]

pub const CompressionMethod = enum(u16) {
    NoCompression = 0,
    Shrunk = 1,
    ReducedUsingSompressionFactor1 = 2,
    ReducedUsingSompressionFactor2 = 3,
    ReducedUsingSompressionFactor3 = 4,
    ReducedUsingSompressionFactor4 = 5,
    Imploded = 6,
    ReservedTokenizingCompressionAlgorithm = 7,
    Deflated = 8,
    EnhancedDeflate64 = 9,
    PKWareDCLImploded = 10,
    Reserved01 = 11,
    BZIP2 = 12,
    Reserved02 = 13,
    LZMA = 14,
    Reserved03 = 15,
    IBMCMPSCCompression = 16,
    Reserved04 = 17,
    IBMTerse = 18,
    IBMLZ77Architecture = 19,
    Deprecated = 20,
    ZStandard = 93,
    MP3Compression = 94,
    XZCompression = 95,
    JPEG = 96,
    WavPack = 97,
    PPMd = 98,
    AExEncryption = 99,

    const Self = @This();
    pub fn from(v: u16) Self {
        return @enumFromInt(v);
    }

    pub fn toInt(self: Self) u16 {
        return @as(u16, @intFromEnum(self));
    }
};

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
        return toBitSet(self.bit_flag);
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
        return toBitSet(self.bit_flag);
    }

    pub fn decodeExtraFields(self: Self, handler: anytype) !void {
        if (self.extra_field) |buffer| {
            try eftypes.decodeExtraFields(buffer, handler);
        }
    }
};

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
    pub const SIGNATURE = 0x04034b50;

    file_header: LocalFileHeader,
    encryption_header: ?[]const u8,
    content: ?Buffer,
    data_descriptor: ?DataDescriptor,

    extra: struct {
        external_file: ?std.fs.File,
        external_bytes: ?[]const u8,
        content_length: u64,
        content_startpos: u64,
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

    var fileentry = LocalFileEntry{
        .file_header = header,
        .content = null,
        .encryption_header = null,
        .data_descriptor = null,

        .extra = .{
            .external_file = null,
            .external_bytes = null,
            .content_length = content_size,
            .content_startpos = start,
        },
    };

    const bitflag = cdheader.bitFlagToBitSet();

    // Archive decryption Encription Header
    if (bitflag.isSet(0)) {
        // should come here
        // [archive decryption header]
        // [archive extra data record]

        const password = "";
        _ = password;
        fileentry.encryption_header = (try in_reader.readBoundedBytes(12)).constSlice();
        const encrption_keys = [3]u32{ 305419896, 591751049, 878082192 };
        _ = encrption_keys;
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

fn toBitSet(bit_flag: u16) std.StaticBitSet(@bitSizeOf(u16)) {
    var bitset = std.StaticBitSet(@bitSizeOf(u16)).initEmpty();
    if (bit_flag == 0) return bitset;

    var bf = bit_flag;
    for (1..17) |idx| {
        const m = 16 - @as(u5, @intCast(idx));
        if (bf >> @as(u4, @intCast(m)) == 1) bitset.setValue(idx, true);

        bf >>= 1;

        if (bf == 0) break;
    }

    return bitset;
}

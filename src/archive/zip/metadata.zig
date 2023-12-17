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

pub const CentralDirectory = struct {
    headers: std.ArrayList(CentralDirectoryHeader),
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
    const SIGNATURE = 0x02014b50;

    signature: u32,
    version_made_by: u16,
    version: u16,
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
        return eftypes.decodeExtraFields(self.extra_field, handler);
    }
};

pub const EocdRecord = struct {
    const SIGNATURE = 0x06054b50;

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
    const SIGNATURE = 0x06064b50;

    signature: u32,
    size: u16,
    version_made_by: u16,
    version: u16,
    num_disk: u32,
    disk_cd_start: u32,
    cd_records_on_disk: u64,
    cd_records_total: u64,
    cd_size: u64,
    offset_start: u64,
    comment_len: u16,
    comment: ?Buffer,
};
pub const Zip64EocdLocator = struct {
    const SIGNATURE = 0x07064b50;
    signature: u32,
    disk_cd_start: u32,
    offset_start: u64,
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
        return eftypes.decodeExtraFields(self.extra_field, handler);
    }
};

pub const DataDescriptor = struct {
    const SIGNATURE = 0x08074b50;

    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
};

pub const ArchiveExtraDataRecord = struct {
    const SIGNATURE = 0x08064b50;

    extra_field_len: u16,
    extra_field: Buffer,
};

pub const LocalFileEntry = struct {
    const SIGNATURE = 0x04034b50;

    file_header: LocalFileHeader,
    encryption_header: ?[]const u8,
    content: Buffer,
    data_descriptor: ?DataDescriptor,
};

pub fn exract(allocator: mem.Allocator, source: anytype) !CentralDirectory {
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
        const version = try reader.readInt(u16, .little);
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
            .version = version,
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
            .size = try reader.readInt(u16, .little),
            .version_made_by = try reader.readInt(u16, .little),
            .version = try reader.readInt(u16, .little),
            .num_disk = try reader.readInt(u32, .little),
            .disk_cd_start = try reader.readInt(u32, .little),
            .cd_records_on_disk = try reader.readInt(u64, .little),
            .cd_records_total = try reader.readInt(u64, .little),
            .cd_size = try reader.readInt(u64, .little),
            .offset_start = try reader.readInt(u64, .little),
            .comment_len = try reader.readInt(u16, .little),
            .comment = null,
        };
        zip64_eocd_record.?.comment = if (zip64_eocd_record.?.comment_len > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            for (0..zip64_eocd_record.?.comment_len) |_| {
                const byte: u8 = try reader.readByte();
                try tmp.writeByte(byte);
            }
            break :blk tmp;
        } else null;
        if (zip64_eocd_record.?.signature != Zip64EocdRecord.SIGNATURE) return error.BadData;

        zip64_eocd_locator = Zip64EocdLocator{
            .signature = try reader.readInt(u32, .little),
            .disk_cd_start = try reader.readInt(u32, .little),
            .offset_start = try reader.readInt(u64, .little),
            .num_disk = try reader.readInt(u32, .little),
        };
        if (zip64_eocd_locator.?.signature != Zip64EocdLocator.SIGNATURE) return error.BadData;
    }
    // end of parsing the zip64 end of central directory record & locator

    return CentralDirectory{
        .headers = cdheaders,
        .digital_signature = ds,
        .zip64_eocd_record = zip64_eocd_record,
        .zip64_eocd_locator = zip64_eocd_locator,
        .eocd_record = eocd.?,
    };
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

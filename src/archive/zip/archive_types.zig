const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;

const ints = @import("../../ints.zig");
const types = @import("types.zig");
const eftypes = @import("extra_field_types.zig");

const Buffer = @import("../../bytes/buffer.zig").Buffer;

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
    archive_decryption_header: ?EncryptionHeader = null,
    archive_extra_data_record: ?ArchiveExtraDataRecord = null,
    central_diectory_headers: std.ArrayList(CentralDirectoryHeader),
    digital_signature: ?DigitalSignature = null,
    zip64_eocd_record: ?Zip64EocdRecord = null,
    zip64_eocd_locator: ?Zip64EocdLocator = null,
    eocd_record: ?EocdRecord = null,

    pub fn destroy(self: *Self, allocator: mem.Allocator) void {
        // local_file_entries
        for (self.local_file_entries.items) |entry| {
            if (entry.file_header.filename) |b| {
                @constCast(&b).deinit();
            }
            if (entry.file_header.extra_field) |b| {
                @constCast(&b).deinit();
            }
            if (entry.encryption_header.key) |b| {
                @constCast(&b).deinit();
            }
            if (entry.encryption_header.value) |_| {
                allocator.free(entry.encryption_header.value.?);
            }

            if (entry.content) |b| {
                @constCast(&b).deinit();
            }

            if (entry.@"$extra".external_file) |b| {
                b.close();
            }
            if (entry.@"$extra".external_bytes) |b| {
                @constCast(&b).deinit();
            }
        }
        self.local_file_entries.clearAndFree();

        // archive_decryption_header
        if (self.archive_decryption_header) |entry| {
            if (entry.value) |_| {
                allocator.free(entry.value.?);
            }
            if (entry.key) |b| {
                @constCast(&b).deinit();
            }
        }

        // archive_extra_data_record
        if (self.archive_extra_data_record) |entry| {
            if (entry.extra_field) |b| {
                @constCast(&b).deinit();
            }
        }

        // central_diectory_headers
        for (self.central_diectory_headers.items) |header| {
            if (header.filename) |b| {
                @constCast(&b).deinit();
            }
            if (header.extra_field) |b| {
                @constCast(&b).deinit();
            }
            if (header.comment) |b| {
                @constCast(&b).deinit();
            }
        }
        self.central_diectory_headers.clearAndFree();

        // digital_signature
        if (self.digital_signature) |ds| {
            if (ds.signature_data) |b| {
                @constCast(&b).deinit();
            }
        }

        // zip64_eocd_record
        if (self.zip64_eocd_record) |r| {
            if (r.extenssion_data) |b| {
                @constCast(&b).deinit();
            }
            if (r.extenssion_v2) |v2| {
                if (v2.hash_data) |b| {
                    @constCast(&b).deinit();
                }
            }
        }

        // eocd_record
        if (self.eocd_record) |r| {
            if (r.comment) |b| {
                @constCast(&b).deinit();
            }
        }
    }
};
pub const DigitalSignature = struct {
    pub const SIGNATURE = 0x05054b50;

    signature: u32,
    signature_data_legth: u16,
    signature_data: ?Buffer = null,
};

pub const CentralDirectoryHeader = struct {
    const Self = @This();
    pub const SIGNATURE = 0x02014b50;

    signature: u32,
    version_made_by: u16,
    version_extract_file: u16,
    flags: Flags,
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
    filename: ?Buffer = null,
    extra_field: ?Buffer = null,
    comment: ?Buffer = null,

    pub fn decodeExtraFields(self: Self, handler: anytype) !void {
        if (self.extra_field) |buffer| {
            try eftypes.decodeExtraFields(buffer, handler);
        }
    }
};

pub const Flags = packed struct(u16) {
    const pointers = @import("../../pointers.zig");
    pub const Self = @This();

    EncryptedFile: bool = false,
    CompressionOption01: bool = false,
    CompressionOption02: bool = false,
    DataDescriptor: bool = true,
    EnhancedDeflation: bool = false,
    CompressedPatchedData: bool = false,
    StrongEncryption: bool = false,
    _unused_07: bool = false,
    _unused_08: bool = false,
    _unused_09: bool = false,
    _unused_10: bool = false,
    LanguageEncoding: bool = false,
    _reserved_12: bool = false,
    MaskHeaderValues: bool = false,
    _reserved_14: bool = false,
    _reserved_15: bool = false,

    pub fn toStaticBitSet(self: Self) std.StaticBitSet(@bitSizeOf(u16)) {
        const v = pointers.fromOpaque(@constCast(&self), *u16);
        return ints.toBitSet(u16, v.*);
    }

    pub fn fromStaticBitSet(bitset: std.StaticBitSet(@bitSizeOf(u16))) u16 {
        return ints.fromBitSet(u16, bitset);
    }

    pub fn fromInt(value: u16) Self {
        return @bitCast(@as(u16, value));
    }

    pub fn toInt(self: Self) Self {
        const v = pointers.fromOpaque(@constCast(&self), *u16);
        return v.*;
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
    comment: ?Buffer = null,
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
    extenssion_v2: ?Zip64EocdRecordExtenssionV2 = null,
    extenssion_data: ?Buffer = null,
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
    hash_data: ?Buffer = null,
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
    flags: Flags,
    compression_method: u16,
    last_modification_time: u16,
    last_modification_date: u16,
    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
    filename_len: u16,
    extra_field_len: u16,
    filename: ?Buffer = null,
    extra_field: ?Buffer = null,

    pub fn decodeExtraFields(self: Self, handler: anytype) !void {
        if (self.extra_field) |buffer| {
            try eftypes.decodeExtraFields(buffer, handler);
        }
    }
};

pub const EncryptionHeader = struct {
    value: ?[]const u8 = null,
    key: ?Buffer = null,
    options: types.Encryption = .{},
};

pub const DataDescriptor = struct {
    pub const SIGNATURE = 0x08074b50;

    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
};

pub const ArchiveExtraDataRecord = struct {
    pub const SIGNATURE = 0x08064b50;

    signature: u32,
    extra_field_len: u16,
    extra_field: ?Buffer = null,
};

// pub const ArchiveDecryptionHeader = struct {
//     iv_size: u16,
//     iv_data: ?Buffer = null,
//     size: u32,
//     format: u16,
//     alg_id: u16,
//     bit_len: u16,
//     flags: u16,
//     erd_size: u16,
//     erd_data: ?Buffer = null,
//     reserved01: u32,
//     reserved02: ?Buffer = null,
//     v_size: u16,
//     v_data: ?Buffer = null,
//     v_crc32: u32,
// };

pub const LocalFileEntry = struct {
    file_header: LocalFileHeader,
    encryption_header: EncryptionHeader = .{},
    content: ?Buffer = null,
    data_descriptor: ?DataDescriptor = null,

    @"$extra": struct {
        external_file: ?std.fs.File = null,
        external_bytes: ?Buffer = null,
        content_length: u64 = 0,
        content_startpos: u64 = 0,
    },
};

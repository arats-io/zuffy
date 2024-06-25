const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;

const ints = @import("../../ints.zig");
const Buffer = @import("../../bytes/buffer.zig").Buffer;

const eftypes = @import("extra_field_types.zig");
const types = @import("types.zig");

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
    eocd_record: EocdRecord,
};
pub const DigitalSignature = struct {
    const SIGNATURE = 0x05054b50;

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
    filename: ?Buffer = null,
    extra_field: ?Buffer = null,
    comment: ?Buffer = null,

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
    bit_flag: u16,
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

    pub fn bitFlagToBitSet(self: Self) std.StaticBitSet(@bitSizeOf(u16)) {
        return ints.toBitSet(u16, self.bit_flag);
    }

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

fn extractEocdRecord(allocator: mem.Allocator, reader: anytype, signature: u32) !EocdRecord {
    const num_disk = try reader.readInt(u16, .little);
    const num_disk_cd_start = try reader.readInt(u16, .little);
    const cd_records_total_on_disk = try reader.readInt(u16, .little);
    const cd_records_total = try reader.readInt(u16, .little);
    const cd_size = try reader.readInt(u32, .little);
    const offset_start = try reader.readInt(u32, .little);
    const comment_len = try reader.readInt(u16, .little);

    const comment = if (comment_len > 0) cblk: {
        var tmp = Buffer.initWithFactor(allocator, 5);
        errdefer tmp.deinit();

        for (0..comment_len) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :cblk tmp;
    } else null;

    return EocdRecord{
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
}

fn extractZip64EocdRecord(allocator: mem.Allocator, reader: anytype, signature: u32) !Zip64EocdRecord {
    var zip64_eocd_record = Zip64EocdRecord{
        .signature = signature,
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
    if (zip64_eocd_record.version_made_by == 1) {
        // Size = SizeOfFixedFields + SizeOfVariableData - 12.
        const extensible_data_len = zip64_eocd_record.size - 56 - 12;
        zip64_eocd_record.extenssion_data = if (extensible_data_len > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            errdefer tmp.deinit();

            for (0..extensible_data_len) |_| {
                const byte: u8 = try reader.readByte();
                try tmp.writeByte(byte);
            }
            break :blk tmp;
        } else null;
    }
    // version 2
    if (zip64_eocd_record.version_made_by == 2) {
        zip64_eocd_record.extenssion_v2 = Zip64EocdRecordExtenssionV2{
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
        const size = zip64_eocd_record.extenssion_v2.?.hash_length;
        zip64_eocd_record.extenssion_v2.?.hash_data = if (size > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            errdefer tmp.deinit();

            for (0..size) |_| {
                const byte: u8 = try reader.readByte();
                try tmp.writeByte(byte);
            }
            break :blk tmp;
        } else null;
    }

    return zip64_eocd_record;
}

fn extractZip64EocdLocator(reader: anytype, signature: u32) !Zip64EocdLocator {
    return Zip64EocdLocator{
        .signature = signature,
        .num_disk_zip64_eocd_start = try reader.readInt(u32, .little),
        .offset_zip64_eocd_record = try reader.readInt(u64, .little),
        .num_disk = try reader.readInt(u32, .little),
    };
}

fn extractDigitalSignature(allocator: mem.Allocator, reader: anytype, signature: u32) !DigitalSignature {
    const signature_data_legth = try reader.readInt(u16, .little);
    const signature_data = if (signature_data_legth > 0) blk: {
        var tmp = Buffer.initWithFactor(allocator, 5);
        errdefer tmp.deinit();

        for (0..signature_data_legth) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    return DigitalSignature{
        .signature = signature,
        .signature_data_legth = signature_data_legth,
        .signature_data = signature_data,
    };
}

const ArchiveExtraData = struct {
    archive_decryption_header: EncryptionHeader,
    archive_extra_data_record: ArchiveExtraDataRecord,
};
fn extractArchiveExtraData(allocator: mem.Allocator, reader: anytype, signature: u32, read_options: types.ReadOptions) !ArchiveExtraData {
    // read the archive_decryption_header
    const raw_archive_decryption_header = (try reader.readBoundedBytes(12)).constSlice();
    var archive_decryption_header = EncryptionHeader{
        .options = read_options.encryption,
    };

    const cr = @import("crypto.zig");
    switch (read_options.encryption.method) {
        .password => {
            var decryption_key = Buffer.init(allocator);
            errdefer decryption_key.deinit();

            var crypto = cr.Crypto.init(archive_decryption_header.options.secret.?);
            var decryptor = crypto.decriptor();
            try decryptor.decrypt(raw_archive_decryption_header, decryption_key.writer());

            archive_decryption_header.value = raw_archive_decryption_header;
            archive_decryption_header.key = decryption_key;
        },
        .x509 => {
            //TODO: to be done
        },
        else => {},
    }
    // end readinf the archive_decryption_header

    // read the archive_extra_data_record
    const extra_field_len = try reader.readInt(u16, .little);

    const extra_field = if (extra_field_len > 0) cblk: {
        var tmp = Buffer.initWithFactor(allocator, 5);
        errdefer tmp.deinit();

        for (0..extra_field_len) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :cblk tmp;
    } else null;

    // end reading archive_extra_data_record

    return ArchiveExtraData{
        .archive_decryption_header = archive_decryption_header,
        .archive_extra_data_record = ArchiveExtraDataRecord{
            .signature = signature,
            .extra_field_len = extra_field_len,
            .extra_field = extra_field,
        },
    };
}

pub fn extract(allocator: mem.Allocator, source: anytype, read_options: types.ReadOptions) !ZipArchive {
    var parse_source = source;
    var reader = parse_source.reader();

    var eocd: ?EocdRecord = null;
    var zip64_eocd_record: ?Zip64EocdRecord = null;
    var zip64_eocd_locator: ?Zip64EocdLocator = null;
    var ds: ?DigitalSignature = null;
    var archive_decryption_header: ?EncryptionHeader = null;
    var archive_extra_data_record: ?ArchiveExtraDataRecord = null;

    errdefer {
        if (eocd) |item| {
            if (item.comment) |b| {
                @constCast(&b).deinit();
            }
        }
        if (zip64_eocd_record) |item| {
            if (item.extenssion_data) |b| {
                @constCast(&b).deinit();
            }

            if (item.extenssion_v2) |itemv2| {
                if (itemv2.hash_data) |b| {
                    @constCast(&b).deinit();
                }
            }
        }
        if (ds) |item| {
            if (item.signature_data) |b| {
                @constCast(&b).deinit();
            }
        }
        if (archive_decryption_header) |item| {
            if (item.value) |b| {
                allocator.free(b);
            }
            if (item.key) |b| {
                @constCast(&b).deinit();
            }
        }
        if (archive_extra_data_record) |item| {
            if (item.extra_field) |b| {
                @constCast(&b).deinit();
            }
        }
    }

    var pos = try parse_source.seekableStream().getEndPos() - 4;
    while (pos > 0) : (pos -= 1) {
        try parse_source.seekableStream().seekTo(pos);

        const signature = try reader.readInt(u32, .little);
        switch (signature) {
            EocdRecord.SIGNATURE => eocd = try extractEocdRecord(allocator, reader, signature),
            Zip64EocdRecord.SIGNATURE => zip64_eocd_record = try extractZip64EocdRecord(allocator, reader, signature),
            Zip64EocdLocator.SIGNATURE => zip64_eocd_locator = try extractZip64EocdLocator(reader, signature),
            DigitalSignature.SIGNATURE => ds = try extractDigitalSignature(allocator, reader, signature),
            ArchiveExtraDataRecord.SIGNATURE => {
                const current_pos = try parse_source.seekableStream().getPos();
                try parse_source.seekableStream().seekTo(current_pos - 16);

                const aed = try extractArchiveExtraData(allocator, reader, signature, read_options);
                archive_decryption_header = aed.archive_decryption_header;
                archive_extra_data_record = aed.archive_extra_data_record;
            },
            else => {},
        }
    }

    // parsing the central directory

    const start_pos = eocd.?.offset_start + eocd.?.num_disk_cd_start;
    try parse_source.seekableStream().seekTo(start_pos);

    var cd_content = Buffer.initWithFactor(allocator, 5);
    errdefer cd_content.deinit();
    defer cd_content.deinit();

    for (0..eocd.?.cd_size) |_| {
        const ch = try reader.readByte();
        try cd_content.writeByte(ch);
    }

    if (ds) |_| {
        const cr = @import("crypto.zig");
        const chash = cr.Crc32IEEE.hash(cd_content.bytes());

        std.debug.print("\n", .{});
        std.debug.print("Cntent DigitalSignature - {any}", .{ds.?.signature_data});
        std.debug.print("Content Hash - {any}\n", .{chash});
    }

    var fixed = std.io.fixedBufferStream(cd_content.bytes());
    const new_reader = fixed.reader();

    switch (read_options.encryption.method) {
        .password => {},
        .x509 => {
            //TODO: to be done
        },
        else => {},
    }

    var cdheaders = std.ArrayList(CentralDirectoryHeader).init(allocator);
    for (0..eocd.?.cd_records_total) |idx| {
        _ = idx;
        const signature = try new_reader.readInt(u32, .little);
        const version_made_by = try new_reader.readInt(u16, .little);
        const version_extract_file = try new_reader.readInt(u16, .little);
        const bit_flag = try new_reader.readInt(u16, .little);
        const compressed_method = try new_reader.readInt(u16, .little);
        const last_modification_time = try new_reader.readInt(u16, .little);
        const last_modification_date = try new_reader.readInt(u16, .little);
        const crc32 = try new_reader.readInt(u32, .little);
        const compressed_size = try new_reader.readInt(u32, .little);
        const uncompressed_size = try new_reader.readInt(u32, .little);
        const filename_len = try new_reader.readInt(u16, .little);
        const extra_field_len = try new_reader.readInt(u16, .little);
        const comment_len = try new_reader.readInt(u16, .little);
        const disk_file_start = try new_reader.readInt(u16, .little);
        const internal_attributes = try new_reader.readInt(u16, .little);
        const external_attributes = try new_reader.readInt(u32, .little);
        const offset_local_header = try new_reader.readInt(u32, .little);

        const filename = if (filename_len > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            for (0..filename_len) |_| {
                const byte: u8 = try new_reader.readByte();
                try tmp.writeByte(byte);
            }
            break :blk tmp;
        } else null;

        const extra_field = if (extra_field_len > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            for (0..extra_field_len) |_| {
                const byte: u8 = try new_reader.readByte();
                try tmp.writeByte(byte);
            }
            break :blk tmp;
        } else null;

        const comment = if (comment_len > 0) blk: {
            var tmp = Buffer.initWithFactor(allocator, 5);
            for (0..comment_len) |_| {
                const byte: u8 = try new_reader.readByte();
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
    // ending of parsing the central directory

    return ZipArchive{
        .local_file_entries = std.ArrayList(LocalFileEntry).init(allocator),
        .archive_decryption_header = archive_decryption_header,
        .archive_extra_data_record = archive_extra_data_record,
        .central_diectory_headers = cdheaders,
        .digital_signature = ds,
        .zip64_eocd_record = zip64_eocd_record,
        .zip64_eocd_locator = zip64_eocd_locator,
        .eocd_record = eocd.?,
    };
}

pub fn readLocalFileEntry(allocator: mem.Allocator, cdheader: CentralDirectoryHeader, seekableStream: anytype, in_reader: anytype, read_options: types.ReadOptions) !LocalFileEntry {
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
        .encryption_header = .{
            .options = read_options.encryption,
        },

        .@"$extra" = .{
            .content_length = content_size,
            .content_startpos = start,
        },
    };

    const bitflag = header.bitFlagToBitSet();

    if (bitflag.isSet(0) and bitflag.isSet(6)) {
        //TODO: to be done
    } else {
        // Local file encryption header
        if (bitflag.isSet(0)) {
            const raw_encryption_header = (try in_reader.readBoundedBytes(12)).constSlice();

            const cr = @import("crypto.zig");
            switch (read_options.encryption.method) {
                .password => {
                    var encryption_key = Buffer.init(allocator);
                    errdefer encryption_key.deinit();

                    var crypto = cr.Crypto.init(fileentry.encryption_header.options.secret.?);
                    var decryptor = crypto.decriptor();
                    try decryptor.decrypt(raw_encryption_header, encryption_key.writer());

                    fileentry.encryption_header.value = raw_encryption_header;
                    fileentry.encryption_header.key = encryption_key;
                },
                .x509 => {
                    //TODO: to be done
                },
                else => {},
            }
        }
        if (bitflag.isSet(6)) {}
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

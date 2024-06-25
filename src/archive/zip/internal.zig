const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;

const Buffer = @import("../../bytes/buffer.zig").Buffer;

const types = @import("types.zig");
const internaltypes = @import("internal_types.zig");

fn extractEocdRecord(allocator: mem.Allocator, reader: anytype, signature: u32) !internaltypes.EocdRecord {
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

    return internaltypes.EocdRecord{
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

fn extractZip64EocdRecord(allocator: mem.Allocator, reader: anytype, signature: u32) !internaltypes.Zip64EocdRecord {
    var zip64_eocd_record = internaltypes.Zip64EocdRecord{
        .signature = signature, // 4
        .size = try reader.readInt(u64, .little), // 8
        .version_made_by = try reader.readInt(u16, .little), // 2
        .version_extract_file = try reader.readInt(u16, .little), // 2
        .num_disk = try reader.readInt(u32, .little), // 4
        .num_disk_cd_start = try reader.readInt(u32, .little), // 4
        .cd_records_on_disk = try reader.readInt(u64, .little), // 8
        .cd_records_total = try reader.readInt(u64, .little), // 8
        .cd_size = try reader.readInt(u64, .little), // 8
        .offset_start = try reader.readInt(u64, .little), // 8
    };

    // version 2
    if (zip64_eocd_record.version_made_by == 2) {
        zip64_eocd_record.extenssion_v2 = internaltypes.Zip64EocdRecordExtenssionV2{
            .compression_method = try reader.readInt(u64, .little), // 8
            .compressed_size = try reader.readInt(u64, .little), // 8
            .original_size = try reader.readInt(u64, .little), // 8
            .alg_id = try reader.readInt(u16, .little), // 2
            .bit_len = try reader.readInt(u16, .little), // 2
            .flags = try reader.readInt(u16, .little), // 2
            .hash_id = try reader.readInt(u16, .little), // 2
            .hash_length = try reader.readInt(u16, .little), // 2
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

    const extensible_data_len = switch (zip64_eocd_record.version_made_by) {
        1 => zip64_eocd_record.size - 56 + 12, // Size = SizeOfFixedFields + SizeOfVariableData - 12.
        2 => zip64_eocd_record.size - 56 - 34 - zip64_eocd_record.extenssion_v2.?.hash_length + 12,
        else => 0,
    };

    zip64_eocd_record.extenssion_data = if (extensible_data_len > 0) blk: {
        var tmp = Buffer.initWithFactor(allocator, 5);
        errdefer tmp.deinit();

        for (0..extensible_data_len) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    return zip64_eocd_record;
}

fn extractZip64EocdLocator(reader: anytype, signature: u32) !internaltypes.Zip64EocdLocator {
    return internaltypes.Zip64EocdLocator{
        .signature = signature,
        .num_disk_zip64_eocd_start = try reader.readInt(u32, .little),
        .offset_zip64_eocd_record = try reader.readInt(u64, .little),
        .num_disk = try reader.readInt(u32, .little),
    };
}

fn extractDigitalSignature(allocator: mem.Allocator, reader: anytype, signature: u32) !internaltypes.DigitalSignature {
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

    return internaltypes.DigitalSignature{
        .signature = signature,
        .signature_data_legth = signature_data_legth,
        .signature_data = signature_data,
    };
}

const ArchiveExtraData = struct {
    archive_decryption_header: internaltypes.EncryptionHeader,
    archive_extra_data_record: internaltypes.ArchiveExtraDataRecord,
};
fn extractArchiveExtraData(allocator: mem.Allocator, reader: anytype, signature: u32, read_options: types.ReadOptions) !ArchiveExtraData {
    // read the archive_decryption_header
    const raw_archive_decryption_header = (try reader.readBoundedBytes(12)).constSlice();
    var archive_decryption_header = internaltypes.EncryptionHeader{
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
        .archive_extra_data_record = internaltypes.ArchiveExtraDataRecord{
            .signature = signature,
            .extra_field_len = extra_field_len,
            .extra_field = extra_field,
        },
    };
}

pub fn extract(allocator: mem.Allocator, source: anytype, read_options: types.ReadOptions) !internaltypes.ZipArchive {
    var parse_source = source;
    var reader = parse_source.reader();

    var archive = internaltypes.ZipArchive{
        .local_file_entries = std.ArrayList(internaltypes.LocalFileEntry).init(allocator),
        .central_diectory_headers = std.ArrayList(internaltypes.CentralDirectoryHeader).init(allocator),
    };
    errdefer archive.destroy(allocator);

    var pos = try parse_source.seekableStream().getEndPos() - 4;
    while (pos > 0) : (pos -= 1) {
        try parse_source.seekableStream().seekTo(pos);

        const signature = try reader.readInt(u32, .little);
        switch (signature) {
            internaltypes.EocdRecord.SIGNATURE => {
                archive.eocd_record = try extractEocdRecord(allocator, reader, signature);
            },
            internaltypes.Zip64EocdRecord.SIGNATURE => {
                archive.zip64_eocd_record = try extractZip64EocdRecord(allocator, reader, signature);
            },
            internaltypes.Zip64EocdLocator.SIGNATURE => {
                archive.zip64_eocd_locator = try extractZip64EocdLocator(reader, signature);
            },
            internaltypes.DigitalSignature.SIGNATURE => {
                archive.digital_signature = try extractDigitalSignature(allocator, reader, signature);
            },
            internaltypes.ArchiveExtraDataRecord.SIGNATURE => {
                const current_pos = try parse_source.seekableStream().getPos();
                try parse_source.seekableStream().seekTo(current_pos - 16);

                const aed = try extractArchiveExtraData(allocator, reader, signature, read_options);
                archive.archive_decryption_header = aed.archive_decryption_header;
                archive.archive_extra_data_record = aed.archive_extra_data_record;
            },
            else => {},
        }
    }

    // parsing the central directory

    const start_pos = archive.eocd_record.?.offset_start + archive.eocd_record.?.num_disk_cd_start;
    try parse_source.seekableStream().seekTo(start_pos);

    var cd_content = Buffer.initWithFactor(allocator, 5);
    errdefer cd_content.deinit();
    defer cd_content.deinit();

    for (0..archive.eocd_record.?.cd_size) |_| {
        const ch = try reader.readByte();
        try cd_content.writeByte(ch);
    }

    if (archive.digital_signature) |ds| {
        const cr = @import("crypto.zig");
        const chash = cr.Crc32IEEE.hash(cd_content.bytes());

        std.debug.print("\n", .{});
        std.debug.print("Cntent DigitalSignature - {any}", .{ds.signature_data});
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

    for (0..archive.eocd_record.?.cd_records_total) |idx| {
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

        if (signature != internaltypes.CentralDirectoryHeader.SIGNATURE) return error.BadData;

        const item = internaltypes.CentralDirectoryHeader{
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

        try archive.central_diectory_headers.append(item);
    }
    // ending of parsing the central directory

    return archive;
}

pub fn readLocalFileEntry(allocator: mem.Allocator, cdheader: internaltypes.CentralDirectoryHeader, seekableStream: anytype, in_reader: anytype, read_options: types.ReadOptions) !internaltypes.LocalFileEntry {
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

    const header = internaltypes.LocalFileHeader{
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

    var fileentry = internaltypes.LocalFileEntry{
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
        if (CRC32 == internaltypes.DataDescriptor.SIGNATURE) {
            CRC32 = try in_reader.readInt(u32, .little);
        }
        fileentry.data_descriptor = internaltypes.DataDescriptor{
            .crc32 = CRC32,
            .compressed_size = try in_reader.readInt(u32, .little),
            .uncompressed_size = try in_reader.readInt(u32, .little),
        };
    }

    return fileentry;
}

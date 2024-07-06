const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const io = std.io;

const Buffer = @import("../../bytes/buffer.zig");

const types = @import("types.zig");
const zarchive_types = @import("archive_types.zig");

fn parseEocdRecord(allocator: mem.Allocator, reader: anytype, signature: u32) !zarchive_types.EocdRecord {
    const num_disk = try reader.readInt(u16, .little);
    const num_disk_cd_start = try reader.readInt(u16, .little);
    const cd_records_total_on_disk = try reader.readInt(u16, .little);
    const cd_records_total = try reader.readInt(u16, .little);
    const cd_size = try reader.readInt(u32, .little);
    const offset_start = try reader.readInt(u32, .little);
    const comment_len = try reader.readInt(u16, .little);

    const comment = if (comment_len > 0) cblk: {
        var tmp = Buffer.init(allocator);
        errdefer tmp.deinit();

        for (0..comment_len) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :cblk tmp;
    } else null;

    return zarchive_types.EocdRecord{
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

fn parseZip64EocdRecord(allocator: mem.Allocator, reader: anytype, signature: u32) !zarchive_types.Zip64EocdRecord {
    var zip64_eocd_record = zarchive_types.Zip64EocdRecord{
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
        zip64_eocd_record.extenssion_v2 = zarchive_types.Zip64EocdRecordExtenssionV2{
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
            var tmp = Buffer.init(allocator);
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
        var tmp = Buffer.init(allocator);
        errdefer tmp.deinit();

        for (0..extensible_data_len) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    return zip64_eocd_record;
}

fn parseZip64EocdLocator(reader: anytype, signature: u32) !zarchive_types.Zip64EocdLocator {
    return zarchive_types.Zip64EocdLocator{
        .signature = signature,
        .num_disk_zip64_eocd_start = try reader.readInt(u32, .little),
        .offset_zip64_eocd_record = try reader.readInt(u64, .little),
        .num_disk = try reader.readInt(u32, .little),
    };
}

fn parseDigitalSignature(allocator: mem.Allocator, reader: anytype, signature: u32) !zarchive_types.DigitalSignature {
    const signature_data_legth = try reader.readInt(u16, .little);
    const signature_data = if (signature_data_legth > 0) blk: {
        var tmp = Buffer.init(allocator);
        errdefer tmp.deinit();

        for (0..signature_data_legth) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    return zarchive_types.DigitalSignature{
        .signature = signature,
        .signature_data_legth = signature_data_legth,
        .signature_data = signature_data,
    };
}

const ArchiveExtraData = struct {
    archive_decryption_header: zarchive_types.EncryptionHeader,
    archive_extra_data_record: zarchive_types.ArchiveExtraDataRecord,
};
fn parseArchiveExtraData(allocator: mem.Allocator, reader: anytype, signature: u32, read_options: types.ReadOptions) !ArchiveExtraData {
    // read the archive_decryption_header
    const raw_archive_decryption_header = (try reader.readBoundedBytes(12)).constSlice();
    var archive_decryption_header = zarchive_types.EncryptionHeader{
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
        var tmp = Buffer.init(allocator);
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
        .archive_extra_data_record = zarchive_types.ArchiveExtraDataRecord{
            .signature = signature,
            .extra_field_len = extra_field_len,
            .extra_field = extra_field,
        },
    };
}

fn parseCentralDirectoryHeader(allocator: mem.Allocator, reader: anytype, signature: u32) !zarchive_types.CentralDirectoryHeader {
    const version_made_by = try reader.readInt(u16, .little);
    const version_extract_file = try reader.readInt(u16, .little);
    const flags = try reader.readStruct(zarchive_types.Flags);
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
        var tmp = Buffer.init(allocator);
        errdefer tmp.deinit();

        for (0..filename_len) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    const extra_field = if (extra_field_len > 0) blk: {
        var tmp = Buffer.init(allocator);
        errdefer tmp.deinit();

        for (0..extra_field_len) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    const comment = if (comment_len > 0) blk: {
        var tmp = Buffer.init(allocator);
        errdefer tmp.deinit();

        for (0..comment_len) |_| {
            const byte: u8 = try reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    return zarchive_types.CentralDirectoryHeader{
        .signature = signature,
        .version_made_by = version_made_by,
        .version_extract_file = version_extract_file,
        .flags = flags,
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
}

pub fn parse(allocator: mem.Allocator, source: anytype, read_options: types.ReadOptions) !zarchive_types.ZipArchive {
    var parse_source = source;
    var reader = parse_source.reader();

    var archive = zarchive_types.ZipArchive{
        .local_file_entries = std.ArrayList(zarchive_types.LocalFileEntry).init(allocator),
        .central_diectory_headers = std.ArrayList(zarchive_types.CentralDirectoryHeader).init(allocator),
    };
    errdefer archive.destroy(allocator);

    var pos = try parse_source.seekableStream().getEndPos() - 4;
    while (pos > 0) : (pos -= 1) {
        try parse_source.seekableStream().seekTo(pos);

        const signature = try reader.readInt(u32, .little);
        switch (signature) {
            zarchive_types.EocdRecord.SIGNATURE => {
                archive.eocd_record = try parseEocdRecord(allocator, reader, signature);
            },
            zarchive_types.Zip64EocdRecord.SIGNATURE => {
                archive.zip64_eocd_record = try parseZip64EocdRecord(allocator, reader, signature);
            },
            zarchive_types.Zip64EocdLocator.SIGNATURE => {
                archive.zip64_eocd_locator = try parseZip64EocdLocator(reader, signature);
            },
            zarchive_types.DigitalSignature.SIGNATURE => {
                archive.digital_signature = try parseDigitalSignature(allocator, reader, signature);
            },
            zarchive_types.ArchiveExtraDataRecord.SIGNATURE => {
                const current_pos = try parse_source.seekableStream().getPos();
                try parse_source.seekableStream().seekTo(current_pos - 16);

                const aed = try parseArchiveExtraData(allocator, reader, signature, read_options);
                archive.archive_decryption_header = aed.archive_decryption_header;
                archive.archive_extra_data_record = aed.archive_extra_data_record;
            },
            else => {},
        }
    }

    // parsing the central directory
    const start_pos = archive.eocd_record.?.offset_start + archive.eocd_record.?.num_disk_cd_start;
    try parse_source.seekableStream().seekTo(start_pos);

    var cd_content = Buffer.init(allocator);
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

    for (0..archive.eocd_record.?.cd_records_total) |_| {
        const signature = try new_reader.readInt(u32, .little);
        switch (signature) {
            zarchive_types.CentralDirectoryHeader.SIGNATURE => {
                const cdh = try parseCentralDirectoryHeader(allocator, new_reader, signature);
                try archive.central_diectory_headers.append(cdh);
            },
            else => {},
        }
    }
    // ending of parsing the central directory

    return archive;
}

pub fn readLocalFileEntry(allocator: mem.Allocator, cdheader: zarchive_types.CentralDirectoryHeader, seekableStream: anytype, in_reader: anytype, read_options: types.ReadOptions) !zarchive_types.LocalFileEntry {
    try seekableStream.seekTo(cdheader.offset_local_header);

    const signature = try in_reader.readInt(u32, .little);
    const version = try in_reader.readInt(u16, .little);
    const flags = try in_reader.readStruct(zarchive_types.Flags);
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
        var tmp = Buffer.init(allocator);
        errdefer tmp.deinit();

        for (0..filename_len) |_| {
            const byte: u8 = try in_reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    const extra_field = if (extra_field_len > 0) blk: {
        var tmp = Buffer.init(allocator);
        errdefer tmp.deinit();

        for (0..extra_field_len) |_| {
            const byte: u8 = try in_reader.readByte();
            try tmp.writeByte(byte);
        }
        break :blk tmp;
    } else null;

    const header = zarchive_types.LocalFileHeader{
        .signature = signature,
        .version = version,
        .flags = flags,
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
    //var content = Buffer.init(allocator);

    const start = try seekableStream.getPos();
    try in_reader.skipBytes(content_size, .{});
    //for (0..content_size) |_| {
    //    const byte: u8 = try in_reader.readByte();
    //    try content.writeByte(byte);
    //}

    var fileentry = zarchive_types.LocalFileEntry{
        .file_header = header,
        .encryption_header = .{
            .options = read_options.encryption,
        },

        .@"$extra" = .{
            .content_length = content_size,
            .content_startpos = start,
        },
    };

    if (header.flags.EncryptedFile and header.flags.StrongEncryption) {
        //TODO: to be done
    } else {
        // Local file encryption header
        if (header.flags.EncryptedFile) {
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
        if (header.flags.StrongEncryption) {}
    }

    if (header.flags.DataDescriptor) {
        var CRC32: u32 = try in_reader.readInt(u32, .little);
        if (CRC32 == zarchive_types.DataDescriptor.SIGNATURE) {
            CRC32 = try in_reader.readInt(u32, .little);
        }
        fileentry.data_descriptor = zarchive_types.DataDescriptor{
            .crc32 = CRC32,
            .compressed_size = try in_reader.readInt(u32, .little),
            .uncompressed_size = try in_reader.readInt(u32, .little),
        };
    }

    return fileentry;
}

const Utf8Buffer = @import("../../bytes/utf8_buffer.zig");
const FlexibleBufferStream = @import("../../bytes/mod.zig").FlexibleBufferStream;

pub fn Archive(comptime ParseSource: type) type {
    return struct {
        const Self = @This();

        pub const Error = ParseSource.Error ||
            error{ WrongChecksum, Unsupported, NotArchiveEmptySource };

        allocator: mem.Allocator,
        source: ParseSource,
        archive: zarchive_types.ZipArchive,

        pub fn init(allocator: mem.Allocator, source: ParseSource) Self {
            return Self{
                .allocator = allocator,
                .source = source,
                .archive = empty(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.archive.destroy(self.allocator);
        }

        fn cleanAndReplaceZipArchive(self: *Self, arch: zarchive_types.ZipArchive) void {
            self.deinit();
            self.archive = arch;
        }

        fn empty(allocator: mem.Allocator) zarchive_types.ZipArchive {
            return zarchive_types.ZipArchive{
                .local_file_entries = std.ArrayList(zarchive_types.LocalFileEntry).init(allocator),
                .archive_decryption_header = null,
                .archive_extra_data_record = null,
                .central_diectory_headers = std.ArrayList(zarchive_types.CentralDirectoryHeader).init(allocator),
                .digital_signature = null,
                .zip64_eocd_record = null,
                .zip64_eocd_locator = null,
                .eocd_record = zarchive_types.EocdRecord{
                    .signature = zarchive_types.EocdRecord.SIGNATURE,
                    .num_disk = 0,
                    .num_disk_cd_start = 0,
                    .cd_records_total_on_disk = 0,
                    .cd_records_total = 0,
                    .cd_size = 0,
                    .offset_start = 0,
                    .comment_len = 0,
                    .comment = Buffer.init(allocator),
                },
            };
        }

        fn setComment(self: *Self, comment: []const u8) !void {
            var eocd = self.archive.?.eocd_record;
            eocd.comment_len = comment.len;
            try eocd.comment.?.writeAll(comment);
        }

        fn addEntry(self: *Self, filename: []const u8, content: []const u8, comment: []const u8, add_optons: types.AddOptions) !void {
            // create the CentralDirectoryHeader entry
            {
                var filename_content = Buffer.init(self.allocator);
                errdefer filename_content.deinit();
                try filename_content.writeAll(filename);

                var comment_content = Buffer.init(self.allocator);
                errdefer comment_content.deinit();
                try comment_content.writeAll(comment);

                const cdh = zarchive_types.CentralDirectoryHeader{
                    .signature = zarchive_types.CentralDirectoryHeader.SIGNATURE,
                    .version_made_by = add_optons.version_made_by,
                    .version_extract_file = add_optons.version_extract_file,
                    .bit_flag = 0,
                    .compressed_method = add_optons.compression_method,
                    .last_modification_time = 0,
                    .last_modification_date = 0,
                    .crc32 = 0,
                    .compressed_size = 0,
                    .uncompressed_size = 0,
                    .filename_len = 0,
                    .extra_field_len = 0,
                    .comment_len = 0,
                    .disk_file_start = 0,
                    .internal_attributes = 0,
                    .external_attributes = 0,
                    .offset_local_header = 0,
                    .filename = filename_content,
                    .extra_field = null,
                    .comment = comment_content,
                };
                self.archive.central_diectory_headers.append(cdh);
            }

            // create the LocalFileEntry entry
            {
                var filename_content = Buffer.init(self.allocator);
                errdefer filename_content.deinit();
                try filename_content.writeAll(filename);

                var entry_content = Buffer.init(self.allocator);
                errdefer entry_content.deinit();
                try entry_content.writeAll(content);

                const lfe = zarchive_types.LocalFileEntry{
                    .file_header = zarchive_types.LocalFileHeader{
                        .signature = zarchive_types.LocalFileHeader.SIGNATURE,
                        .version = 0,
                        .bit_flag = 0,
                        .compression_method = 0,
                        .last_modification_time = 0,
                        .last_modification_date = 0,
                        .crc32 = 0,
                        .compressed_size = 0,
                        .uncompressed_size = 0,
                        .filename_len = 0,
                        .extra_field_len = 0,
                        .filename = filename_content,
                        .extra_field = null,
                    },
                    .encryption_header = null,
                    .content = null,
                    .data_descriptor = null,

                    .@"$extra" = .{
                        .external_file = null,
                        .external_bytes = entry_content,
                        .content_length = 0,
                        .content_startpos = 0,
                    },
                };
                self.archive.local_file_entries.append(lfe);
            }
        }

        pub fn addFile(self: *Self, sourcefile_path: []const u8, archivefile_path: []const u8) !void {
            const source_file = try fs.Dir.openFile(sourcefile_path, .{});
            var file_closed = false;
            errdefer if (!file_closed) source_file.close();

            const stat = try source_file.stat();

            if (stat.kind == .directory)
                return error.IsDir;

            const source_code = try std.fs.cwd().readFileAlloc(self.allocator, sourcefile_path, stat.size);
            defer self.allocator.free(source_code);

            source_file.close();
            file_closed = true;

            try self.addEntry(archivefile_path, source_code);
        }

        pub fn saveAs(self: *Self, file_path: []const u8) !void {
            _ = self;

            const archive_file = try fs.createFileAbsolute(file_path, .{ .mode = .write_only });
            var file_closed = false;
            errdefer if (!file_closed) archive_file.close();

            const stat = try archive_file.stat();

            if (stat.kind == .directory)
                return error.IsDir;

            const writer = archive_file.writer();
            _ = writer;

            //TODO: go through data and save into a file

            archive_file.close();
            file_closed = true;
        }

        pub fn extractIntoDirectory(self: *Self, dir_path: []const u8) !void {
            // if the given directory doesn't exist, then create it
            var source_directory = try fs.cwd().openDir(dir_path, .{}) catch |err| switch (err) {
                fs.Dir.OpenError.FileNotFound => {
                    try fs.cwd().makeDir(dir_path);
                },
                else => err,
            };
            errdefer source_directory.close();

            const stat = try source_directory.stat();

            if (stat.kind != .directory)
                return error.isFile;

            const Collector = struct {
                const SelfCollector = @This();
                const GenericContentType = @import("../content_receiver.zig");

                pub const GenericContent = GenericContentType(*SelfCollector, receive);
                dir: fs.Dir,

                pub fn init(all: std.mem.Allocator, dir: fs.Dir) SelfCollector {
                    return SelfCollector{ .arr = std.ArrayList([]const u8).init(all), .dir = dir };
                }

                pub fn receive(collector: *SelfCollector, filename: []const u8, fileContent: []const u8) !void {
                    var f = try collector.dir.createFile(filename, .{});
                    errdefer {
                        f.close();
                        collector.dir.deleteFile(filename);
                    }
                    defer f.close();

                    try f.write(fileContent);
                }

                pub fn content(collector: *SelfCollector) GenericContent {
                    return .{ .context = collector };
                }
            };

            const collector = Collector.init(self.allocator);

            try self.read(collector.content().receiver());
        }

        pub fn deccompress(self: *Self, receiver: anytype) !void {
            var filters = std.ArrayList([]const u8).init(self.allocator);
            defer filters.deinit();
            errdefer filters.deinit();

            self.deccompressWithFilters(filters, receiver) catch |err| switch (err) {
                error.IsEmpty => return Error.NotArchiveEmptySource,
                else => return err,
            };
        }

        pub fn deccompressWithFilters(self: *Self, filters: std.ArrayList([]const u8), receiver: anytype) !void {
            if (self.archive.local_file_entries.items.len == 0) {
                self.cleanAndReplaceZipArchive(try parse(self.allocator, self.source, .{}));
            }

            for (self.archive.central_diectory_headers.items) |cdheader| {
                const entry_name = @constCast(&cdheader.filename.?).bytes();

                if (!matches(cdheader.filename.?, filters)) continue;

                var seekableStream = self.source.seekableStream();
                var reader = self.source.reader();
                const lfentry = try readLocalFileEntry(self.allocator, cdheader, seekableStream, reader, .{});

                const content_size = if (lfentry.file_header.compression_method == 0) lfentry.file_header.uncompressed_size else lfentry.file_header.compressed_size;

                // decide what to do with the ziped file content
                if (content_size > 0) {
                    const cm = types.CompressionMethod.from(lfentry.file_header.compression_method);

                    try seekableStream.seekTo(lfentry.@"$extra".content_startpos);

                    var content = Buffer.init(self.allocator);
                    defer content.deinit();
                    errdefer content.deinit();

                    for (0..lfentry.@"$extra".content_length) |_| {
                        const byte: u8 = try reader.readByte();
                        try content.writeByte(byte);
                    }

                    // decrypt the file content
                    switch (lfentry.encryption_header.options.method) {
                        .password => {
                            //TODO: to be done
                        },
                        .x509 => {
                            //TODO: to be done
                        },
                        else => {},
                    }

                    // decompress the file content
                    switch (cm) {
                        .NoCompression => {
                            try receiver.entryContent(entry_name, content.bytes());
                        },
                        .Deflated => {
                            var decoded_content = Buffer.init(self.allocator);
                            defer decoded_content.deinit();
                            errdefer decoded_content.deinit();

                            var in_stream = std.io.fixedBufferStream(content.bytes());
                            var deflator = std.compress.flate.decompressor(in_stream.reader());
                            try deflator.decompress(decoded_content.writer());

                            try receiver.entryContent(entry_name, decoded_content.bytes());
                        },

                        else => {
                            return error.InvalidCompression;
                        },
                    }
                }
            }
        }

        fn matches(filename: Buffer, filters: std.ArrayList([]const u8)) bool {
            if (filters.items.len == 0) {
                return true;
            }

            var b = Utf8Buffer.initWithBuffer(filename);
            defer b.deinit();

            for (filters.items) |item| {
                if (b.contains(item)) return true;
            }
            return false;
        }
    };
}

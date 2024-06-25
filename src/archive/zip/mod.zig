const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const io = std.io;

const internal_type = @import("internal_types.zig");
const internal = @import("internal.zig");

pub const extrafield = @import("extra_field.zig");
pub const types = @import("types.zig");

const Buffer = @import("../../bytes/buffer.zig").Buffer;
const Utf8Buffer = @import("../../bytes/utf8_buffer.zig").Utf8Buffer;
const FlexibleBufferStream = @import("../../bytes/mod.zig").FlexibleBufferStream;

pub fn fromBufferStream(allocator: mem.Allocator, stream: anytype) File(@TypeOf(stream)) {
    return File(@TypeOf(stream)).init(allocator, stream);
}

pub fn File(comptime ParseSource: type) type {
    return struct {
        const Self = @This();

        pub const Error = ParseSource.Error ||
            error{ WrongChecksum, Unsupported, NotArchiveEmptySource };

        allocator: mem.Allocator,
        source: ParseSource,
        archive: internal_type.ZipArchive,

        fn init(allocator: mem.Allocator, source: ParseSource) Self {
            return Self{
                .allocator = allocator,
                .source = source,
                .archive = empty(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.archive.destroy(self.allocator);
        }

        fn cleanAndReplaceZipArchive(self: *Self, arch: internal_type.ZipArchive) void {
            self.deinit();
            self.archive = arch;
        }

        fn empty(allocator: mem.Allocator) internal_type.ZipArchive {
            return internal_type.ZipArchive{
                .local_file_entries = std.ArrayList(internal_type.LocalFileEntry).init(allocator),
                .archive_decryption_header = null,
                .archive_extra_data_record = null,
                .central_diectory_headers = std.ArrayList(internal_type.CentralDirectoryHeader).init(allocator),
                .digital_signature = null,
                .zip64_eocd_record = null,
                .zip64_eocd_locator = null,
                .eocd_record = internal_type.EocdRecord{
                    .signature = internal_type.EocdRecord.SIGNATURE,
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

                const cdh = internal_type.CentralDirectoryHeader{
                    .signature = internal_type.CentralDirectoryHeader.SIGNATURE,
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

                const lfe = internal_type.LocalFileEntry{
                    .file_header = internal_type.LocalFileHeader{
                        .signature = internal_type.LocalFileHeader.SIGNATURE,
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
                self.cleanAndReplaceZipArchive(try internal.extract(self.allocator, self.source, .{}));
            }

            for (self.archive.central_diectory_headers.items) |cdheader| {
                const entry_name = @constCast(&cdheader.filename.?).bytes();

                if (!matches(cdheader.filename.?, filters)) continue;

                var seekableStream = self.source.seekableStream();
                var reader = self.source.reader();
                const lfentry = try internal.readLocalFileEntry(self.allocator, cdheader, seekableStream, reader, .{});

                const content_size = if (lfentry.file_header.compression_method == 0) lfentry.file_header.uncompressed_size else lfentry.file_header.compressed_size;

                // decide what to do with the ziped file content
                if (content_size > 0) {
                    const cm = types.CompressionMethod.from(lfentry.file_header.compression_method);

                    try seekableStream.seekTo(lfentry.@"$extra".content_startpos);

                    var content = Buffer.initWithFactor(self.allocator, 5);
                    defer content.deinit();
                    errdefer content.deinit();

                    for (0..lfentry.@"$extra".content_length) |_| {
                        const byte: u8 = try reader.readByte();
                        try content.writeByte(byte);
                    }

                    switch (cm) {
                        .NoCompression => {
                            try receiver.entryContent(entry_name, content.bytes());
                        },
                        .Deflated => {
                            var decoded_content = Buffer.initWithFactor(self.allocator, 5);
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

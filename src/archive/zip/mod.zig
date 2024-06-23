const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const io = std.io;

const metadata = @import("metadata.zig");
pub const extrafield = @import("extra_field.zig");

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
        archive: metadata.ZipArchive,

        fn init(allocator: mem.Allocator, source: ParseSource) Self {
            return Self{
                .allocator = allocator,
                .source = source,
                .archive = empty(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.cleanZipArchive();
        }

        fn cleanAndReplaceZipArchive(self: *Self, arch: metadata.ZipArchive) void {
            self.cleanZipArchive();
            self.archive = arch;
        }

        fn cleanZipArchive(self: *Self) void {
            // local_file_entries
            for (self.archive.local_file_entries.items) |entry| {
                if (entry.file_header.filename) |b| {
                    @constCast(&b).deinit();
                }
                if (entry.file_header.extra_field) |b| {
                    @constCast(&b).deinit();
                }
                if (entry.encryption_header) |_| {
                    self.allocator.free(entry.encryption_header.?);
                }
                @constCast(&entry.content).deinit();
            }
            self.archive.local_file_entries.clearAndFree();

            // archive_decryption_header
            if (self.archive.archive_decryption_header) |entry| {
                if (entry.iv_data) |b| {
                    @constCast(&b).deinit();
                }
                if (entry.erd_data) |b| {
                    @constCast(&b).deinit();
                }
                if (entry.reserved02) |b| {
                    @constCast(&b).deinit();
                }
                if (entry.v_data) |b| {
                    @constCast(&b).deinit();
                }
            }

            // archive_extra_data_record
            if (self.archive.archive_extra_data_record) |entry| {
                @constCast(&entry.extra_field).deinit();
            }

            // central_diectory_headers
            for (self.archive.central_diectory_headers.items) |header| {
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
            self.archive.central_diectory_headers.clearAndFree();

            // digital_signature
            if (self.archive.digital_signature) |ds| {
                if (ds.signature_data) |b| {
                    @constCast(&b).deinit();
                }
            }

            // zip64_eocd_record
            if (self.archive.zip64_eocd_record) |r| {
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
            if (self.archive.eocd_record.comment) |b| {
                @constCast(&b).deinit();
            }
        }

        fn empty(allocator: mem.Allocator) metadata.ZipArchive {
            return metadata.ZipArchive{
                .local_file_entries = std.ArrayList(metadata.LocalFileEntry).init(allocator),
                .archive_decryption_header = null,
                .archive_extra_data_record = null,
                .central_diectory_headers = std.ArrayList(metadata.CentralDirectoryHeader).init(allocator),
                .digital_signature = null,
                .zip64_eocd_record = null,
                .zip64_eocd_locator = null,
                .eocd_record = metadata.EocdRecord{
                    .signature = metadata.EocdRecord.SIGNATURE,
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

        fn addEntry(self: *Self, filename: []const u8, content: []const u8) !void {
            _ = self;
            _ = filename;
            _ = content;
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

            const archive_file = try fs.openFileAbsolute(file_path, .{ .mode = .write_only });
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

        pub fn read(self: *Self, receiver: anytype) !void {
            var filters = std.ArrayList([]const u8).init(self.allocator);
            defer filters.deinit();
            errdefer filters.deinit();

            self.readWithFilters(filters, receiver) catch |err| switch (err) {
                error.IsEmpty => return Error.NotArchiveEmptySource,
                else => return err,
            };
        }

        pub fn readWithFilters(self: *Self, filters: std.ArrayList([]const u8), receiver: anytype) !void {
            self.cleanAndReplaceZipArchive(try metadata.extract(self.allocator, self.source));

            for (self.archive.central_diectory_headers.items) |item| {
                const entry_name = @constCast(&item.filename.?).bytes();

                if (!matches(item.filename.?, filters)) continue;

                const lfheader = try metadata.readLocalFileEntry(self.allocator, item, self.source.seekableStream(), self.source.reader());

                const content_size = if (lfheader.file_header.compression_method == 0) lfheader.file_header.uncompressed_size else lfheader.file_header.compressed_size;

                // decide what to do with the ziped file content
                if (content_size > 0) {
                    const cm = metadata.CompressionMethod.from(lfheader.file_header.compression_method);
                    const bytes = @constCast(&lfheader).content.bytes();
                    switch (cm) {
                        .NoCompression => {
                            try receiver.entryContent(entry_name, bytes);
                        },
                        .Deflated => {
                            var in_stream = std.io.fixedBufferStream(bytes);

                            var deflator = std.compress.flate.decompressor(in_stream.reader());

                            var decoded_content = Buffer.initWithFactor(self.allocator, 5);
                            defer decoded_content.deinit();
                            errdefer decoded_content.deinit();

                            while (true) {
                                if (deflator.reader().readByte()) |byte| {
                                    try decoded_content.writeByte(byte);
                                } else |_| {
                                    break;
                                }
                            }
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

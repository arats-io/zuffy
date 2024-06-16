const std = @import("std");
const mem = std.mem;
const io = std.io;

pub const metadata = @import("metadata.zig");
pub const extrafield = @import("extra_field.zig");

const Buffer = @import("../../bytes/buffer.zig").Buffer;
const Utf8Buffer = @import("../../bytes/utf8_buffer.zig").Utf8Buffer;

pub fn fromBufferStream(allocator: mem.Allocator, stream: anytype) File(@TypeOf(stream)) {
    return File(@TypeOf(stream)).init(allocator, stream);
}

pub fn File(comptime ParseSource: type) type {
    return struct {
        const Self = @This();

        pub const Error = ParseSource.Error ||
            error{ WrongChecksum, Unsupported };

        allocator: mem.Allocator,
        source: ParseSource,
        central_directory: ?metadata.CentralDirectory = null,

        fn init(allocator: mem.Allocator, source: ParseSource) Self {
            return Self{
                .allocator = allocator,
                .source = source,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.central_directory) |cd| {
                if (cd.eocd_record.comment) |b| {
                    @constCast(&b).deinit();
                }
                if (cd.digital_signature) |ds| {
                    if (ds.signature_data) |b| {
                        @constCast(&b).deinit();
                    }
                }
                if (cd.zip64_eocd_record) |r| {
                    if (r.extenssion_data) |b| {
                        @constCast(&b).deinit();
                    }
                    if (r.extenssion_v2) |v2| {
                        if (v2.hash_data) |b| {
                            @constCast(&b).deinit();
                        }
                    }
                }
                for (cd.headers.items) |header| {
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
                cd.headers.deinit();
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

        pub fn read(self: *Self, provider: anytype) !void {
            var filters = std.ArrayList([]const u8).init(self.allocator);
            defer filters.deinit();

            try self.readWithFilters(filters, provider);
        }

        pub fn readWithFilters(self: *Self, filters: std.ArrayList([]const u8), receiver: anytype) !void {
            if (self.central_directory == null) {
                self.central_directory = try metadata.exract(self.allocator, self.source);
            }

            for (self.central_directory.?.headers.items) |item| {
                const entry_name = @constCast(&item.filename.?).bytes();

                if (!matches(item.filename.?, filters)) continue;

                try self.source.seekableStream().seekTo(item.offset_local_header);
                const in_reader = self.source.reader();

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
                    var tmp = Buffer.initWithFactor(self.allocator, 5);
                    for (0..filename_len) |_| {
                        const byte: u8 = try in_reader.readByte();
                        try tmp.writeByte(byte);
                    }
                    break :blk tmp;
                } else null;

                const extra_field = if (extra_field_len > 0) blk: {
                    var tmp = Buffer.initWithFactor(self.allocator, 5);
                    for (0..extra_field_len) |_| {
                        const byte: u8 = try in_reader.readByte();
                        try tmp.writeByte(byte);
                    }
                    break :blk tmp;
                } else null;

                defer {
                    if (filename) |b| {
                        @constCast(&b).deinit();
                    }
                    if (extra_field) |b| {
                        @constCast(&b).deinit();
                    }
                }

                const header = metadata.LocalFileHeader{
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

                var content = Buffer.initWithFactor(self.allocator, 5);
                defer content.deinit();

                for (0..content_size) |_| {
                    const byte: u8 = try in_reader.readByte();
                    try content.writeByte(byte);
                }

                var fileentry = metadata.LocalFileEntry{
                    .file_header = header,
                    .content = content,
                    .encryption_header = null,
                    .data_descriptor = null,
                };

                const bitflag = item.bitFlagToBitSet();

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
                    if (CRC32 == metadata.DataDescriptor.SIGNATURE) {
                        CRC32 = try in_reader.readInt(u32, .little);
                    }
                    fileentry.data_descriptor = metadata.DataDescriptor{
                        .crc32 = CRC32,
                        .compressed_size = try in_reader.readInt(u32, .little),
                        .uncompressed_size = try in_reader.readInt(u32, .little),
                    };
                }

                // decide what to do with the ziped file content
                if (content_size > 0) {
                    const cm = metadata.CompressionMethod.from(header.compression_method);
                    switch (cm) {
                        .NoCompression => {
                            try receiver.entryContent(entry_name, content.bytes());
                        },
                        .Deflated => {
                            var in_stream = std.io.fixedBufferStream(content.bytes());

                            var deflator = std.compress.flate.decompressor(in_stream.reader());

                            var decoded_content = Buffer.initWithFactor(self.allocator, 5);
                            defer decoded_content.deinit();

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
    };
}

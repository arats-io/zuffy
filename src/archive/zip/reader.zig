const std = @import("std");
const mem = std.mem;
const io = std.io;
const deflate = std.compress.deflate;

const Buffer = @import("../../bytes/buffer.zig").Buffer;
const Utf8Buffer = @import("../../bytes/utf8_buffer.zig").Utf8Buffer;

const CentralDirectory = struct {
    file_headers: std.ArrayList(CDFileHeader),
    digital_signature: ?DigitalSignature,
    zip64_eocd_record: ?Zip64EocdRecord,
    zip64_eocd_locator: ?Zip64EocdLocator,
    eocd_record: EocdRecord,
};
const DigitalSignature = struct {
    const SIGNATURE = 0x05054b50;

    signature: u32,
    size_of_data: u16,
    signature_data: ?Buffer,
};

const CDFileHeader = struct {
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
};

const EocdRecord = struct {
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

const Zip64EocdRecord = struct {
    const SIGNATURE = 0x07064b50;

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
const Zip64EocdLocator = struct {
    const SIGNATURE = 0x07064b50;
    signature: u32,
    disk_cd_start: u32,
    offset_start: u64,
    num_disk: u32,
};

const LocalFileEntry = struct {
    const SIGNATURE = 0x04034b50;

    file_header: LocalFileHeader,
    encryption_header: ?[]const u8,
    content: Buffer,
    data_descriptor: DataDescriptor,
};

const LocalFileHeader = struct {
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
};
const DataDescriptor = struct {
    crc32: u32,
    compressed_size: u32,
    uncompressed_size: u32,
};

const NO_COMPRESSION = 0;
const DEFLATE = 8;

pub fn Entries(allocator: mem.Allocator, source: anytype) !ReaderEntries(@TypeOf(source)) {
    return ReaderEntries(@TypeOf(source)).init(allocator, source);
}

pub fn ReaderEntries(comptime ParseSource: type) type {
    return struct {
        const Self = @This();

        pub const Error = ParseSource.Error ||
            deflate.Decompressor(ParseSource).Error ||
            error{ WrongChecksum, Unsupported };

        allocator: mem.Allocator,
        source: ParseSource,
        central_directory: CentralDirectory,

        fn init(allocator: mem.Allocator, source: ParseSource) !Self {
            var parse_source = source;
            var eocd: ?EocdRecord = null;

            var pos = try parse_source.seekableStream().getEndPos() - 4;
            while (pos > 0) : (pos -= 1) {
                try parse_source.seekableStream().seekTo(pos);

                const signature = try parse_source.reader().readIntLittle(u32);
                if (signature != EocdRecord.SIGNATURE) {
                    continue;
                }

                const num_disk = try parse_source.reader().readIntLittle(u16);
                const num_disk_cd_start = try parse_source.reader().readIntLittle(u16);
                const cd_records_total_on_disk = try parse_source.reader().readIntLittle(u16);
                const cd_records_total = try parse_source.reader().readIntLittle(u16);
                const cd_size = try parse_source.reader().readIntLittle(u32);
                const offset_start = try parse_source.reader().readIntLittle(u32);
                const comment_len = try parse_source.reader().readIntLittle(u16);

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

            var cdheaders = std.ArrayList(CDFileHeader).init(allocator);

            const start_pos = eocd.?.offset_start + eocd.?.num_disk_cd_start;
            try parse_source.seekableStream().seekTo(start_pos);
            const reader = parse_source.reader();

            for (0..eocd.?.cd_records_total) |idx| {
                _ = idx;
                const signature = try reader.readIntLittle(u32);
                const version_made_by = try reader.readIntLittle(u16);
                const version = try reader.readIntLittle(u16);
                const bit_flag = try reader.readIntLittle(u16);
                const compressed_method = try reader.readIntLittle(u16);
                const last_modification_time = try reader.readIntLittle(u16);
                const last_modification_date = try reader.readIntLittle(u16);
                const crc32 = try reader.readIntLittle(u32);
                const compressed_size = try reader.readIntLittle(u32);
                const uncompressed_size = try reader.readIntLittle(u32);
                const filename_len = try reader.readIntLittle(u16);
                const extra_field_len = try reader.readIntLittle(u16);
                const comment_len = try reader.readIntLittle(u16);
                const disk_file_start = try reader.readIntLittle(u16);
                const internal_attributes = try reader.readIntLittle(u16);
                const external_attributes = try reader.readIntLittle(u32);
                const offset_local_header = try reader.readIntLittle(u32);

                var filename = if (filename_len > 0) blk: {
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

                if (signature != CDFileHeader.SIGNATURE) return error.BadData;

                const item = CDFileHeader{
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

            const signature = try reader.readIntLittle(u32);

            if (signature != EocdRecord.SIGNATURE and signature != DigitalSignature.SIGNATURE) {
                return error.BadData;
            }

            const ds = if (signature == DigitalSignature.SIGNATURE) blkds: {
                const size_of_data = try reader.readIntLittle(u16);
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

            var zip64_eocd_record: ?Zip64EocdRecord = null;
            var zip64_eocd_locator: ?Zip64EocdLocator = null;
            if (eocd.?.num_disk == 0xffff) {
                zip64_eocd_record = Zip64EocdRecord{
                    .signature = try reader.readIntLittle(u32),
                    .size = try reader.readIntLittle(u16),
                    .version_made_by = try reader.readIntLittle(u16),
                    .version = try reader.readIntLittle(u16),
                    .num_disk = try reader.readIntLittle(u32),
                    .disk_cd_start = try reader.readIntLittle(u32),
                    .cd_records_on_disk = try reader.readIntLittle(u64),
                    .cd_records_total = try reader.readIntLittle(u64),
                    .cd_size = try reader.readIntLittle(u64),
                    .offset_start = try reader.readIntLittle(u64),
                    .comment_len = try reader.readIntLittle(u16),
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

                zip64_eocd_locator = Zip64EocdLocator{
                    .signature = try reader.readIntLittle(u32),
                    .disk_cd_start = try reader.readIntLittle(u32),
                    .offset_start = try reader.readIntLittle(u64),
                    .num_disk = try reader.readIntLittle(u32),
                };
            }

            return Self{
                .allocator = allocator,
                .source = source,
                .central_directory = CentralDirectory{
                    .file_headers = cdheaders,
                    .digital_signature = ds,
                    .zip64_eocd_record = zip64_eocd_record,
                    .zip64_eocd_locator = zip64_eocd_locator,
                    .eocd_record = eocd.?,
                },
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.central_directory.eocd_record.comment) |b| {
                @constCast(&b).deinit();
            }
            if (self.central_directory.digital_signature) |ds| {
                if (ds.signature_data) |b| {
                    @constCast(&b).deinit();
                }
            }
            if (self.central_directory.zip64_eocd_record) |r| {
                if (r.comment) |b| {
                    @constCast(&b).deinit();
                }
            }
            for (self.central_directory.file_headers.items) |header| {
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
            self.central_directory.file_headers.deinit();
        }

        fn matches(filename: Buffer, filters: std.ArrayList([]const u8)) bool {
            if (filters.items.len == 0) {
                return true;
            }

            var b = Utf8Buffer.initWithBuffer(filename);
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
            for (self.central_directory.file_headers.items) |item| {
                const entry_name = @constCast(&item.filename.?).bytes();

                if (!matches(item.filename.?, filters)) continue;

                try self.source.seekableStream().seekTo(item.offset_local_header);
                const in_reader = self.source.reader();

                const signature = try in_reader.readIntLittle(u32);
                const version = try in_reader.readIntLittle(u16);
                const bit_flag = try in_reader.readIntLittle(u16);
                const compression_method = try in_reader.readIntLittle(u16);
                const last_modification_time = try in_reader.readIntLittle(u16);
                const last_modification_date = try in_reader.readIntLittle(u16);
                const crc32 = try in_reader.readIntLittle(u32);
                const compressed_size = try in_reader.readIntLittle(u32);
                const uncompressed_size = try in_reader.readIntLittle(u32);
                const filename_len = try in_reader.readIntLittle(u16);
                const extra_field_len = try in_reader.readIntLittle(u16);

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

                var content = Buffer.initWithFactor(self.allocator, 5);
                defer content.deinit();

                for (0..content_size) |_| {
                    const byte: u8 = try in_reader.readByte();
                    try content.writeByte(byte);
                }
                // const encryption_header = try in_reader.readBoundedBytes(12);

                const data_descriptor = DataDescriptor{
                    .crc32 = try in_reader.readIntLittle(u32),
                    .compressed_size = try in_reader.readIntLittle(u32),
                    .uncompressed_size = try in_reader.readIntLittle(u32),
                };
                _ = data_descriptor;

                if (content_size > 0) {
                    switch (header.compression_method) {
                        NO_COMPRESSION => {
                            try receiver.entryContent(entry_name, content.bytes());
                        },
                        DEFLATE => {
                            var in_stream = std.io.fixedBufferStream(content.bytes());

                            var deflator = try deflate.decompressor(self.allocator, in_stream.reader(), null);
                            defer deflator.deinit();

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

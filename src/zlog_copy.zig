const std = @import("std");

const time = @import("time/mod.zig");

const Utf8Buffer = @import("bytes/mod.zig").Utf8Buffer;
const CircularLifoList = @import("list/mod.zig").circular.CircularLifoList;

const Time = time.Time;
const Local = time.zoneinfo.Local;
const Measure = time.Measure;

const local = Local.Get();
const default_caller_marshal_fn = struct {
    fn handler(src: std.builtin.SourceLocation) []const u8 {
        var buf: [10 * 1024]u8 = undefined;
        const data = std.fmt.bufPrint(&buf, "{s}:{}", .{ src.file, src.line }) catch "";
        return data[0..];
    }
}.handler;

pub const TimeFormating = enum(u4) {
    timestamp = 0,
    pattern = 1,
};

pub const Format = enum(u4) {
    text = 0,
    json = 1,
};

pub const Level = enum(u4) {
    trace = 0x0,
    debug = 0x1,
    info = 0x2,
    warn = 0x3,
    @"error" = 0x4,
    fatal = 0x5,
    disabled = 0xF,

    pub fn String(self: Level) []const u8 {
        return @tagName(self);
    }
    pub fn ParseString(val: []const u8) Level {
        if (std.meta.stringToEnum(Level, val)) |tag| {
            return tag;
        }
        return .disabled;
    }
};

/// Logger configuration configuration
pub const Config = struct {
    /// log level, possible values (Trace | Debug | Info | Warn | Error | Fatal | Disabled)
    level: Level = .info,
    /// field name for the log level
    level_field_name: []const u8 = "level",

    /// format for writing logs, possible values (json | simple)
    format: Format = Format.json,

    /// buffer pool related configuration options
    buffer_pool: struct {
        /// flag enabling/disabling the buffer pool
        /// if enabled, the buffer pool will be used to store the log records
        /// if disabled, the log records will be written directly to the writer
        /// this is useful for performance reasons, as it avoids the overhead of creating and destroying buffers
        enabled: bool = false,
        /// buffer pool size
        size: u32 = 5,
    } = .{
        .enabled = false,
        .size = 5,
    },

    /// time related configuration options
    /// flag enabling/disabling the time  for each log record
    time_enabled: bool = false,
    /// field name for the time
    time_field_name: []const u8 = "time",
    /// time measumerent, possible values (seconds | millis | micros, nanos)
    time_measure: Measure = Measure.seconds,
    /// time formating, possible values (timestamp | pattern)
    time_formating: TimeFormating = TimeFormating.timestamp,
    /// petttern of time representation, applicable when .time_formating is sen on .pattern
    time_pattern: []const u8 = "DD/MM/YYYY'T'HH:mm:ss",

    /// field name for the message
    message_field_name: []const u8 = "msg",
    /// field name for the error
    error_field_name: []const u8 = "error",

    /// scope name for the error
    scope_field_name: []const u8 = "scope",

    /// flag enabling/disabling the error tracing reporting in the log
    stacktrace_enabled: bool = false,
    /// field name for the error stacktrace
    stacktrace_field_name: []const u8 = "stacktrace",

    /// caller related configuration options
    /// flag enabling/disabling the caller reporting in the log
    caller_enabled: bool = false,
    /// field name for the caller source
    caller_field_name: []const u8 = "caller",
    /// handler processing the source object data
    caller_marshal_fn: *const fn (std.builtin.SourceLocation) []const u8 = default_caller_marshal_fn,

    /// handler writing the data
    writer: std.fs.File = std.fs.File.stdout(),

    escape_enabled: bool = false,
    /// escaping source set of characters
    src_escape_characters: []const u8 = "\"",
    /// escaping destination set of characters
    dst_escape_characters: []const u8 = "\\\"",

    /// stringify options
    stingifyOptions: std.json.Stringify.Options = .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
        .emit_strings_as_arrays = false,
        .escape_unicode = true,
        .emit_nonportable_numbers_as_strings = false,
    },
};

pub fn Field(comptime T: type, key: []const u8, value: T) struct { key: []const u8, value: T } {
    return .{
        .key = key,
        .value = value,
    };
}
pub fn Source(value: std.builtin.SourceLocation) struct { src_value: std.builtin.SourceLocation } {
    return .{
        .src_value = value,
    };
}

const Self = @This();

allocator: std.mem.Allocator,
config: Config,
fields: Utf8Buffer,
scopes: ?Utf8Buffer = null,
buffer_pool: CircularLifoList(Utf8Buffer),

pub fn init(allocator: std.mem.Allocator, comptime config: Config) Self {
    return .{
        .allocator = allocator,
        .config = config,
        .fields = Utf8Buffer.init(allocator),
        .buffer_pool = if (config.buffer_pool.enabled)
            CircularLifoList(Utf8Buffer).init(allocator, config.buffer_pool.size, .{ .mode = .dynamic })
        else
            CircularLifoList(Utf8Buffer).initWithMaxCapacity(allocator, 0, 0, .{ .mode = .dynamic }),
    };
}

pub fn deinit(self: *const Self) void {
    @constCast(&self.buffer_pool).deinit();
    @constCast(self).fields.deinit();
    if (self.scopes) |s| {
        @constCast(&s).deinit();
    }
}

pub fn scope(self: *const Self, comptime value: @Type(.enum_literal)) !Self {
    var scopes = Utf8Buffer.init(self.allocator);
    errdefer scopes.deinit();

    try injectKeyAndValue(false, &scopes, self.config, self.config.scope_field_name, value);

    return Self{
        .allocator = self.allocator,
        .config = self.config,
        .buffer_pool = self.buffer_pool,
        .fields = try @constCast(self).fields.clone(),
        .scopes = scopes,
    };
}

pub fn with(self: *const Self, comptime args: anytype) !void {
    inline for (0..args.len) |i| {
        const arg_type = @TypeOf(args[i]);

        if (@hasField(arg_type, "key") and @hasField(arg_type, "value")) {
            try injectKeyAndValue(false, &self.fields, self.config, args[i].key, args[i].value);
        }
    }
}

pub fn trace(self: *const Self, message: []const u8, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.trace)) return;

    try self.send(Level.trace, message, null, args);
}
pub fn debug(self: *const Self, message: []const u8, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.debug)) return;

    try self.send(Level.debug, message, null, args);
}
pub fn info(self: *const Self, message: []const u8, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.info)) return;

    try self.send(Level.info, message, null, args);
}
pub fn warn(self: *const Self, message: []const u8, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.warn)) return;

    try self.send(Level.warn, message, null, args);
}
pub fn @"error"(self: *const Self, message: []const u8, err: ?anyerror, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.@"error")) return;

    try self.send(Level.@"error", message, err, args);
}
pub fn fatal(self: *const Self, message: []const u8, err: anyerror, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.fatal)) return;

    try self.send(Level.fatal, message, err, args);

    @panic("fatal");
}

fn getBuffer(self: *const Self) Utf8Buffer {
    return if (self.buffer_pool.isEmpty()) Utf8Buffer.init(self.allocator) else @constCast(&self.buffer_pool).pop().?;
}

inline fn send(self: *const Self, comptime op: Level, message: []const u8, err_value: ?anyerror, args: anytype) !void {
    var buffer = self.getBuffer();
    errdefer {
        if (self.config.buffer_pool.enabled) {
            buffer.clear();
            _ = @constCast(&self.buffer_pool).push(buffer);
        } else {
            buffer.deinit();
        }
    }
    defer {
        if (self.config.buffer_pool.enabled) {
            buffer.clear();
            _ = @constCast(&self.buffer_pool).push(buffer);
        } else {
            buffer.deinit();
        }
    }
    try process(self.allocator, &buffer, self.scopes, self.fields, self.config, op, message, err_value, args);

    _ = try self.config.writer.write(buffer.bytes());
}

fn process(
    allocator: std.mem.Allocator,
    buffer: *Utf8Buffer,
    scope_fields: ?Utf8Buffer,
    fields: Utf8Buffer,
    config: Config,
    comptime op: Level,
    message: []const u8,
    err_value: ?anyerror,
    args: anytype,
) !void {
    var adapter = buffer.writer().adaptToNewApi();
    const w = &adapter.new_interface;

    // begin of record
    _ = try w.write(switch (config.format) {
        inline .text => "",
        inline .json => "{ ",
    });

    // add the timstamp
    if (config.time_enabled) {
        const t = Time.new(config.time_measure);

        switch (config.time_formating) {
            inline .timestamp => {
                try injectKeyAndValue(true, buffer, config, config.time_field_name, t.value);
            },
            inline .pattern => {
                var buf: [1024]u8 = undefined;
                const len = try t.formatfInto(allocator, config.time_pattern, &buf);
                try injectKeyAndValue(true, buffer, config, config.time_field_name, buf[0..len]);
            },
        }
    }

    // append the level
    try injectKeyAndValue(!config.time_enabled, buffer, config, config.level_field_name, op.String());

    // append the scope if present
    if (scope_fields) |scope_field| {
        try buffer.append(@constCast(&scope_field).bytes());
    }

    // append the message
    try injectKeyAndValue(false, buffer, config, config.message_field_name, message);

    // append the static logger fields
    try buffer.append(@constCast(&fields).bytes());

    // append the error
    if (err_value) |value| {
        try injectKeyAndValue(false, buffer, config, config.error_field_name, @errorName(value));

        if (config.stacktrace_enabled) {
            if (@errorReturnTrace()) |st| {
                const debug_info = std.debug.getSelfDebugInfo() catch |err| {
                    w.print("Unable to dump stack trace: Unable to open debug info: {s}\n", .{
                        @errorName(err),
                    }) catch {};
                    return;
                };

                const tty_config = std.io.tty.detectConfig(std.fs.File.stderr());
                try std.debug.writeStackTrace(st.*, w, debug_info, tty_config);
            }
        }
    }

    // append the all other fields
    inline for (0..args.len) |i| {
        const arg_type = @TypeOf(args[i]);
        if (@hasField(arg_type, "src_value")) {
            if (config.caller_enabled) {
                const data = config.caller_marshal_fn(args[i].src_value);
                try injectKeyAndValue(false, buffer, config, config.caller_field_name, data);
            }
        }

        if (@hasField(arg_type, "key") and @hasField(arg_type, "value")) {
            try injectKeyAndValue(false, buffer, config, args[i].key, args[i].value);
        }
    }

    // append the end of record
    _ = try w.write(switch (config.format) {
        inline .text => "\n",
        inline .json => " }\n",
    });
}

fn injectKeyAndValue(first: bool, buffer: *const Utf8Buffer, config: Config, key: []const u8, value: anytype) !void {
    var data: *Utf8Buffer = @constCast(buffer);

    var adapter = data.writer().adaptToNewApi();
    const w = &adapter.new_interface;
    var write_stream: std.json.Stringify = .{
        .writer = w,
        .options = config.stingifyOptions,
    };

    switch (config.format) {
        .text => {
            try w.print("{s}{s}=", .{ if (first) "" else ", ", key });

            if (config.escape_enabled) {
                const startPos = data.rawLength();

                const T = @TypeOf(value);
                switch (@typeInfo(T)) {
                    .@"union", .@"struct", .array, .vector, .float, .comptime_float, .int, .comptime_int, .null, .optional => {
                        try w.print("\u{0022}", .{});
                        try write_stream.write(value);
                        try w.print("\u{0022}", .{});
                    },
                    else => {
                        try write_stream.write(value);
                    },
                }

                _ = try data.replaceAllBoundary(
                    startPos + 1,
                    1,
                    config.src_escape_characters,
                    config.dst_escape_characters,
                );
            } else {
                try write_stream.write(value);
            }
        },
        .json => {
            try w.print("{s}\u{0022}{s}\u{0022}: ", .{ if (first) "" else ", ", key });
            try write_stream.write(value);
        },
    }
}

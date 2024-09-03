const std = @import("std");

const pool = @import("pool/mod.zig");
const time = @import("time/mod.zig");

const GenericPool = pool.Generic;
const Utf8Buffer = @import("bytes/mod.zig").Utf8Buffer;

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
    writer: std.fs.File = std.io.getStdOut(),

    /// escaping flag
    escape_enabled: bool = false,
    /// escaping source set of characters
    src_escape_characters: []const u8 = "\"",
    /// escaping destination set of characters
    dst_escape_characters: []const u8 = "\\\"",

    emit_null_optional_fields: bool = false,

    /// stringify options
    stingify: struct { escape_enabled: bool, level1: std.json.StringifyOptions, levelX: std.json.StringifyOptions } = .{
        .escape_enabled = false,
        .level1 = .{
            .whitespace = .minified,
            .emit_null_optional_fields = false,
            .emit_strings_as_arrays = false,
            .escape_unicode = true,
            .emit_nonportable_numbers_as_strings = false,
        },
        .levelX = .{
            .whitespace = .minified,
            .emit_null_optional_fields = false,
            .emit_strings_as_arrays = false,
            .escape_unicode = true,
            .emit_nonportable_numbers_as_strings = false,
        },
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
buffer_pool: ?*const GenericPool(Utf8Buffer) = null,
fields: Utf8Buffer,
scope: ?Utf8Buffer = null,

pub fn init(allocator: std.mem.Allocator, comptime config: Config) Self {
    return .{
        .allocator = allocator,
        .config = config,
        .fields = Utf8Buffer.init(allocator),
    };
}

pub fn deinit(self: *const Self) void {
    @constCast(self).fields.deinit();
    if (self.scope) |s| {
        @constCast(&s).deinit();
    }
}

pub fn initWithPool(allocator: std.mem.Allocator, buffer_pool: *const GenericPool(Utf8Buffer), comptime config: Config) Self {
    return .{
        .allocator = allocator,
        .config = config,
        .buffer_pool = buffer_pool,
        .fields = Utf8Buffer.init(allocator),
    };
}

pub fn Scope(self: *const Self, comptime value: @Type(.enum_literal)) !Self {
    var scope = Utf8Buffer.init(self.allocator);
    errdefer scope.deinit();

    try injectKeyAndValue(false, &scope, self.config, self.config.scope_field_name, value);

    return Self{
        .allocator = self.allocator,
        .config = self.config,
        .buffer_pool = self.buffer_pool,
        .fields = try @constCast(self).fields.clone(),
        .scope = scope,
    };
}

pub fn With(self: *const Self, comptime args: anytype) !void {
    inline for (0..args.len) |i| {
        const arg_type = @TypeOf(args[i]);

        if (@hasField(arg_type, "key") and @hasField(arg_type, "value")) {
            try injectKeyAndValue(false, &self.fields, self.config, args[i].key, args[i].value);
        }
    }
}

pub fn Trace(self: *const Self, message: []const u8, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.trace)) return;

    try self.send(Level.trace, message, null, args);
}
pub fn Debug(self: *const Self, message: []const u8, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.debug)) return;

    try self.send(Level.debug, message, null, args);
}
pub fn Info(self: *const Self, message: []const u8, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.info)) return;

    try self.send(Level.info, message, null, args);
}
pub fn Warn(self: *const Self, message: []const u8, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.warn)) return;

    try self.send(Level.warn, message, null, args);
}
pub fn Error(self: *const Self, message: []const u8, err: ?anyerror, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.@"error")) return;

    try self.send(Level.@"error", message, err, args);
}
pub fn Fatal(self: *const Self, message: []const u8, err: anyerror, args: anytype) !void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.fatal)) return;

    try self.send(Level.fatal, message, err, args);

    @panic("fatal");
}

inline fn send(self: *const Self, comptime op: Level, message: []const u8, err_value: ?anyerror, args: anytype) !void {
    var buffer = if (self.buffer_pool) |p| p.pop() else Utf8Buffer.init(self.allocator);
    errdefer {
        buffer.deinit();
        if (self.buffer_pool) |p| {
            p.push(&buffer) catch |e| {
                std.debug.print("Error - {any}", .{e});
            };
        }
    }
    defer {
        buffer.deinit();
        if (self.buffer_pool) |p| {
            p.push(&buffer) catch |e| {
                std.debug.print("Error - {any}", .{e});
            };
        }
    }
    try process(self.allocator, &buffer, self.scope, self.fields, self.config, op, message, err_value, args);

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
    if (scope_fields) |scope| {
        try buffer.append(@constCast(&scope).bytes());
    }

    // append the message
    try injectKeyAndValue(false, buffer, config, config.message_field_name, message);

    // append the static logger fields
    try buffer.append(@constCast(&fields).bytes());

    // append the error
    if (err_value) |value| {
        try injectKeyAndValue(false, buffer, config, config.error_field_name, @errorName(value));

        if (config.stacktrace_enabled) {
            if (@errorReturnTrace()) |stacktrace| {
                const debug_info: ?*std.debug.SelfInfo = std.debug.getSelfDebugInfo() catch res: {
                    break :res null;
                };
                if (debug_info) |di| {
                    var buff = std.ArrayList(u8).init(allocator);
                    errdefer buff.deinit();
                    defer buff.deinit();

                    try std.debug.writeStackTrace(stacktrace.*, buff.writer(), allocator, di, .no_color);

                    if (buff.items.len > 0) {
                        try injectKeyAndValue(false, buffer, config, config.stacktrace_field_name, buff.items);
                    }
                }
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
    _ = try buffer.write(switch (config.format) {
        inline .text => "\n",
        inline .json => "}\n",
    });
}

fn injectKeyAndValue(first: bool, buffer: *const Utf8Buffer, config: Config, key: []const u8, value: anytype) !void {
    var data: *Utf8Buffer = @constCast(buffer);

    const T = @TypeOf(value);
    const ty = @typeInfo(T);
    switch (ty) {
        .error_union => {
            if (value) |payload| {
                return try injectKeyAndValue(first, buffer, config, key, payload);
            } else |err| {
                return try injectKeyAndValue(first, buffer, config, key, err);
            }
        },
        .type => {
            return try injectKeyAndValue(first, buffer, config, key, @typeName(value));
        },
        .enum_literal => {
            return try injectKeyAndValue(first, buffer, config, key, @tagName(value));
        },
        .void => {
            return try injectKeyAndValue(first, buffer, config, key, "void");
        },
        .optional => {
            if (value) |payload| {
                return try injectKeyAndValue(first, buffer, config, key, payload);
            } else {
                return try injectKeyAndValue(first, buffer, config, key, null);
            }
        },
        else => {},
    }

    switch (config.format) {
        .text => {
            const header = if (first) "" else " ";
            switch (ty) {
                .@"enum" => try data.print("{s}{s}=\u{0022}{s}\u{0022}", .{ header, key, @typeName(value) }),
                .bool => try data.print("{s}{s}=\u{0022}{s}\u{0022}", .{ header, key, if (value) "true" else "false" }),
                .pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => {
                        if (config.escape_enabled) {
                            try data.print("{s}{s}=\u{0022}", .{ header, key });
                            const cPos = data.rawLength();
                            try data.print("{s}", .{value});
                            _ = try data.replaceAllFromPos(
                                cPos,
                                config.src_escape_characters,
                                config.dst_escape_characters,
                            );
                            _ = try data.write("\u{0022}");
                        } else {
                            try data.print("{s}{s}=\u{0022}{s}\u{0022}", .{ header, key, value });
                        }
                    },
                },
                .comptime_int, .int, .comptime_float, .float => try data.print("{s}{s}={any}", .{ header, key, value }),
                .error_set => try data.print("{s}{s}=\u{0022}{s}\u{0022}", .{ header, config.error_field_name, @errorName(value) }),
                .null => if (config.emit_null_optional_fields) try data.print("{s}{s}=null", .{ header, key }),
                .@"struct", .@"union" => {
                    if (config.stingify.escape_enabled) {
                        try data.print("{s}{s}=\u{0022}", .{ header, key });
                    } else {
                        try data.print("{s}{s}=", .{ header, key });
                    }

                    const cPos = data.rawLength();
                    try std.json.stringifyMaxDepth(value, config.stingify.level1, data.writer(), std.math.maxInt(u16));

                    if (config.stingify.escape_enabled) {
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                    }

                    if (config.stingify.escape_enabled) {
                        try data.print("\u{0022}", .{});
                    }
                },
                .array, .vector => {
                    try data.print("{s}{s}=[", .{ header, key });

                    for (value, 0..) |elem, i| {
                        try injectValue(i == 0, buffer, config, elem);
                    }

                    try data.print("]", .{});
                },
                else => try data.print("{s}{s}=\u{0022}{any}\u{0022}", .{ header, key, value }),
            }
        },
        .json => {
            const header = if (first) "{" else ", ";
            switch (ty) {
                .@"enum" => try data.print("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ header, key, @typeName(value) }),
                .bool => try data.print("{s}\u{0022}{s}\u{0022}: {s}", .{ header, key, if (value) "true" else "false" }),
                .pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => {
                        if (config.escape_enabled) {
                            try data.print("{s}\u{0022}{s}\u{0022}: \u{0022}", .{ header, key });
                            const cPos = data.rawLength();
                            try data.print("{s}", .{value});
                            _ = try data.replaceAllFromPos(
                                cPos,
                                config.src_escape_characters,
                                config.dst_escape_characters,
                            );
                            _ = try data.write("\u{0022}");
                        } else {
                            try data.print("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ header, key, value });
                        }
                    },
                },
                .comptime_int, .int, .comptime_float, .float => try data.print("{s}\u{0022}{s}\u{0022}:{any}", .{ header, key, value }),
                .error_set => try data.print("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ header, key, @errorName(value) }),
                .null => if (config.emit_null_optional_fields) try data.print("{s}\u{0022}{s}\u{0022}:null", .{ header, key }),
                .@"struct", .@"union" => {
                    try data.print("{s}\u{0022}{s}\u{0022}:", .{ header, key });

                    try std.json.stringifyMaxDepth(value, config.stingify.level1, data.writer(), std.math.maxInt(u16));
                },
                .array, .vector => {
                    try data.print("{s}\u{0022}{s}\u{0022}: [", .{ header, key });

                    for (value, 0..) |elem, i| {
                        try injectValue(i == 0, buffer, config, elem);
                    }

                    try data.print("]", .{});
                },
                else => try data.print("{s}\u{0022}{s}\u{0022}: \u{0022}{any}\u{0022}", .{ header, key, value }),
            }
        },
    }
}

fn injectValue(first: bool, buffer: *const Utf8Buffer, config: Config, value: anytype) !void {
    var data: *Utf8Buffer = @constCast(buffer);

    const T = @TypeOf(value);
    const ty = @typeInfo(T);

    switch (ty) {
        .optional => {
            if (value) |payload| {
                return injectValue(first, buffer, config, payload);
            } else {
                return injectValue(first, buffer, config, null);
            }
        },
        else => {},
    }

    switch (config.format) {
        inline .text => {
            const header = if (first) "" else ", ";
            switch (ty) {
                .@"enum" => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, @typeName(value) }),
                .bool => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, if (value) "true" else "false" }),
                .pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => {
                        if (config.escape_enabled) {
                            try data.print("{s}\u{0022}", .{header});

                            const cPos = data.rawLength();
                            try data.print("{s}", .{value});
                            _ = try data.replaceAllFromPos(
                                cPos,
                                config.src_escape_characters,
                                config.dst_escape_characters,
                            );
                            _ = try data.write("\u{0022}");
                        } else {
                            try data.print("{s}\u{0022}{s}\u{0022}", .{ header, value });
                        }
                    },
                },
                .comptime_int, .int, .comptime_float, .float => try data.print("{s}{any}", .{ header, value }),
                .error_set => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, @errorName(value) }),
                .null => if (config.emit_null_optional_fields) try data.print("{s}null", .{header}),
                .@"struct", .@"union" => {
                    if (config.stingify.escape_enabled) {
                        try data.print("{s}\u{0022}", .{header});
                    } else {
                        try data.print("{s}", .{header});
                    }

                    const cPos = data.rawLength();
                    try std.json.stringifyMaxDepth(value, config.stingify.levelX, data.writer(), std.math.maxInt(u16));

                    if (config.stingify.escape_enabled) {
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                    }

                    if (config.stingify.escape_enabled) {
                        try data.print("\u{0022}", .{});
                    }
                },
                .array, .vector => {
                    try data.print("{s} [", .{header});

                    for (value, 0..) |elem, i| {
                        try injectValue(i == 0, buffer, config, elem);
                    }

                    try data.print("]", .{});
                },
                else => try data.print("{s}\u{0022}{any}\u{0022}", .{ header, value }),
            }
        },
        inline .json => {
            const header = if (first) "" else ", ";
            switch (ty) {
                .@"enum" => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, @typeName(value) }),
                .bool => try data.print("{s}{s}", .{ header, if (value) "true" else "false" }),
                .pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => {
                        if (config.escape_enabled) {
                            try data.print("{s}\u{0022}", .{header});

                            const cPos = data.rawLength();
                            try data.print("{s}", .{value});
                            _ = try data.replaceAllFromPos(
                                cPos,
                                config.src_escape_characters,
                                config.dst_escape_characters,
                            );
                            _ = try data.write("\u{0022}");
                        } else {
                            try data.print("{s}\u{0022}{s}\u{0022}", .{ header, value });
                        }
                    },
                },
                .comptime_int, .int, .comptime_float, .float => try data.print("{s}{any}", .{ header, value }),
                .error_set => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, @errorName(value) }),
                .null => if (config.emit_null_optional_fields) try data.print("{s}null", .{header}),
                .@"struct", .@"union" => {
                    try data.print("{s}", .{header});

                    try std.json.stringifyMaxDepth(value, config.stingify.levelX, data.writer(), std.math.maxInt(u16));
                },
                .array, .vector => {
                    try data.print("{s} [", .{header});

                    for (value, 0..) |elem, i| {
                        try injectValue(i == 0, buffer, config, elem);
                    }

                    try data.print("]", .{});
                },
                else => try data.print("{s}\u{0022}{any}\u{0022}", .{ header, value }),
            }
        },
    }
}

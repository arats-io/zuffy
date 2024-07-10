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
    stacktrace_ebabled: bool = false,
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

    escape_enabled: bool = false,
    src_escape_characters: []const u8 = "\"",
    dst_escape_characters: []const u8 = "\\\"",
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

pub fn Scope(self: *const Self, comptime value: @Type(.EnumLiteral)) !Self {
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
}

fn send(self: *const Self, comptime op: Level, message: []const u8, err_value: ?anyerror, args: anytype) !void {
    var buffer = if (self.buffer_pool) |p| p.pop() else Utf8Buffer.init(self.allocator);
    errdefer {
        buffer.deinit();
        if (self.buffer_pool) |p| {
            p.push(&buffer) catch |err| {
                std.debug.print("Error - {any}", .{err});
            };
        }
    }
    defer {
        buffer.deinit();
        if (self.buffer_pool) |p| {
            p.push(&buffer) catch |err| {
                std.debug.print("Error - {any}", .{err});
            };
        }
    }

    // add the timstamp
    const opts = self.config;
    if (opts.time_enabled) {
        const t = Time.new(opts.time_measure);

        switch (opts.time_formating) {
            inline .timestamp => {
                try injectKeyAndValue(true, &buffer, self.config, opts.time_field_name, t.value);
            },
            inline .pattern => {
                var buf: [1024]u8 = undefined;
                const len = try t.formatfInto(self.allocator, opts.time_pattern, &buf);
                try injectKeyAndValue(true, &buffer, self.config, opts.time_field_name, buf[0..len]);
            },
        }
    }

    // append the level
    try injectKeyAndValue(!opts.time_enabled, &buffer, self.config, opts.level_field_name, op.String());

    // append the scope if present
    if (self.scope) |scope| {
        try buffer.append(@constCast(&scope).bytes());
    }

    // append the message
    try injectKeyAndValue(false, &buffer, opts, opts.message_field_name, message);

    // append the static logger fields
    try buffer.append(@constCast(&self.fields).bytes());

    // append the error
    if (err_value) |value| {
        try injectKeyAndValue(false, &buffer, self.config, self.config.error_field_name, @errorName(value));

        if (self.config.stacktrace_ebabled) {
            if (@errorReturnTrace()) |stacktrace| {
                const debug_info: ?*std.debug.DebugInfo = std.debug.getSelfDebugInfo() catch res: {
                    break :res null;
                };
                if (debug_info) |di| {
                    var buff = std.ArrayList(u8).init(self.allocator);
                    errdefer buff.deinit();
                    defer buff.deinit();

                    try std.debug.writeStackTrace(stacktrace.*, buff.writer(), self.allocator, di, .no_color);

                    if (buff.items.len > 0) {
                        try injectKeyAndValue(false, &buffer, self.config, self.config.stacktrace_field_name, buff.items);
                    }
                }
            }
        }
    }

    // append the all other fields
    inline for (0..args.len) |i| {
        const arg_type = @TypeOf(args[i]);
        if (@hasField(arg_type, "src_value")) {
            if (self.config.caller_enabled) {
                const data = self.config.caller_marshal_fn(args[i].src_value);
                try injectKeyAndValue(false, &buffer, self.config, self.config.caller_field_name, data);
            }
        }

        if (@hasField(arg_type, "key") and @hasField(arg_type, "value")) {
            try injectKeyAndValue(false, &buffer, self.config, args[i].key, args[i].value);
        }
    }

    // append the end of record
    _ = try buffer.write(switch (self.config.format) {
        inline .text => "\n",
        inline .json => "}\n",
    });

    // send data
    _ = try self.config.writer.write(buffer.bytes());

    if (op == .fatal) {
        @panic("fatal");
    }
}

fn injectKeyAndValue(first: bool, buffer: *const Utf8Buffer, config: Config, key: []const u8, value: anytype) !void {
    var data: *Utf8Buffer = @constCast(buffer);

    const T = @TypeOf(value);
    const ty = @typeInfo(T);
    switch (ty) {
        .ErrorUnion => {
            if (value) |payload| {
                return try injectKeyAndValue(first, buffer, config, key, payload);
            } else |err| {
                return try injectKeyAndValue(first, buffer, config, key, err);
            }
        },
        .Type => {
            return try injectKeyAndValue(first, buffer, config, key, @typeName(value));
        },
        .EnumLiteral => {
            return try injectKeyAndValue(first, buffer, config, key, @tagName(value));
        },
        .Void => {
            return try injectKeyAndValue(first, buffer, config, key, "void");
        },
        .Optional => {
            if (value) |payload| {
                return try injectKeyAndValue(first, buffer, config, key, payload);
            } else {
                return try injectKeyAndValue(first, buffer, config, key, null);
            }
        },
        .Fn => {},
        else => {},
    }

    switch (config.format) {
        inline .text => {
            const header = if (first) "" else " ";
            switch (ty) {
                .Enum => try data.print("{s}{s}=\u{0022}{s}\u{0022}", .{ header, key, @typeName(value) }),
                .Bool => try data.print("{s}{s}=\u{0022}{s}\u{0022}", .{ header, key, if (value) "true" else "false" }),
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => {
                        try data.print("{s}{s}=\u{0022}", .{ header, key });
                        const cPos = data.length();
                        try data.print("{s}", .{value});
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                        _ = try data.write("\u{0022}");
                    },
                },
                .ComptimeInt, .Int, .ComptimeFloat, .Float => try data.print("{s}{s}={any}", .{ header, key, value }),
                .ErrorSet => try data.print("{s}{s}=\u{0022}{s}\u{0022}", .{ header, config.error_field_name, @errorName(value) }),
                .Null => try data.print("{s}{s}=null", .{ header, key }),
                .Struct, .Union => {
                    if (config.escape_enabled) {
                        try data.print("{s}{s}=\u{0022}", .{ header, key });
                    } else {
                        try data.print("{s}{s}=", .{ header, key });
                    }

                    const cPos = data.length();
                    try std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16));

                    if (config.escape_enabled) {
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                    }

                    if (config.escape_enabled) {
                        try data.print("\u{0022}", .{});
                    }
                },
                .Array, .Vector => {
                    try data.print("{s}{s}=[", .{ header, key });

                    for (value, 0..) |elem, i| {
                        try injectValue(i == 0, buffer, config, elem);
                    }

                    try data.print("]", .{});
                },
                else => try data.print("{s}{s}=\u{0022}{any}\u{0022}", .{ header, key, value }),
            }
        },
        inline .json => {
            const header = if (first) "{" else ", ";
            switch (ty) {
                .Enum => try data.print("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ header, key, @typeName(value) }),
                .Bool => try data.print("{s}\u{0022}{s}\u{0022}: {s}", .{ header, key, if (value) "true" else "false" }),
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => {
                        try data.print("{s}\u{0022}{s}\u{0022}: \u{0022}", .{ header, key });
                        const cPos = data.length();
                        try data.print("{s}", .{value});
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                        _ = try data.write("\u{0022}");
                    },
                },
                .ComptimeInt, .Int, .ComptimeFloat, .Float => try data.print("{s}\u{0022}{s}\u{0022}:{any}", .{ header, key, value }),
                .ErrorSet => try data.print("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ header, key, @errorName(value) }),
                .Null => try data.print("{s}\u{0022}{s}\u{0022}:null", .{ header, key }),
                .Struct, .Union => {
                    try data.print("{s}\u{0022}{s}\u{0022}:", .{ header, key });

                    const cPos = data.length();
                    try std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16));

                    if (config.escape_enabled) {
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                    }
                },
                .Array, .Vector => {
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
    switch (config.format) {
        inline .text => {
            const header = if (first) "" else ", ";
            switch (ty) {
                .Enum => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, @typeName(value) }),
                .Bool => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, if (value) "true" else "false" }),
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => {
                        try data.print("{s}\u{0022}", .{header});

                        const cPos = data.length();
                        try data.print("{s}", .{value});
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                        _ = try data.write("\u{0022}");
                    },
                },
                .ComptimeInt, .Int, .ComptimeFloat, .Float => try data.print("{s}{any}", .{ header, value }),
                .ErrorSet => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, @errorName(value) }),
                .Null => try data.print("{s}null", .{header}),
                .Struct, .Union => {
                    if (config.escape_enabled) {
                        try data.print("{s}\u{0022}", .{header});
                    } else {
                        try data.print("{s}", .{header});
                    }

                    const cPos = data.length();
                    try std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16));

                    if (config.escape_enabled) {
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                    }

                    if (config.escape_enabled) {
                        try data.print("\u{0022}", .{});
                    }
                },
                .Array, .Vector => {
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
                .Enum => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, @typeName(value) }),
                .Bool => try data.print("{s}{s}", .{ header, if (value) "true" else "false" }),
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => {
                        try data.print("{s}\u{0022}", .{header});

                        const cPos = data.length();
                        try data.print("{s}", .{value});
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                        _ = try data.write("\u{0022}");
                    },
                },
                .ComptimeInt, .Int, .ComptimeFloat, .Float => try data.print("{s}{any}", .{ header, value }),
                .ErrorSet => try data.print("{s}\u{0022}{s}\u{0022}", .{ header, @errorName(value) }),
                .Null => try data.print("{s}null", .{header}),
                .Struct, .Union => {
                    try data.print("{s}", .{header});

                    const cPos = data.length();
                    try std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16));

                    if (config.escape_enabled) {
                        _ = try data.replaceAllFromPos(
                            cPos,
                            config.src_escape_characters,
                            config.dst_escape_characters,
                        );
                    }
                },
                .Array, .Vector => {
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

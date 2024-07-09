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

pub const InternalFailure = enum {
    nothing,
    panic,
    print,
};

pub const TimeFormating = enum(u4) {
    timestamp = 0,
    pattern = 1,
};

pub const Format = enum(u4) {
    text = 0,
    json = 1,
};

pub const Level = enum(u4) {
    Trace = 0x0,
    Debug = 0x1,
    Info = 0x2,
    Warn = 0x3,
    Error = 0x4,
    Fatal = 0x5,
    Disabled = 0xF,

    pub fn String(self: Level) []const u8 {
        return switch (self) {
            .Trace => "trace",
            .Debug => "debug",
            .Info => "info",
            .Warn => "warn",
            .Error => "error",
            .Fatal => "fatal",
            .Disabled => "disabled",
        };
    }
    pub fn ParseString(val: []const u8) Level {
        var buffer: [8]u8 = undefined;
        const lVal = std.ascii.lowerString(&buffer, val);

        if (std.mem.eql(u8, "trace", lVal)) return .Trace;
        if (std.mem.eql(u8, "debug", lVal)) return .Debug;
        if (std.mem.eql(u8, "info", lVal)) return .Info;
        if (std.mem.eql(u8, "warn", lVal)) return .Warn;
        if (std.mem.eql(u8, "error", lVal)) return .Error;
        if (std.mem.eql(u8, "fatal", lVal)) return .Fatal;
        if (std.mem.eql(u8, "disabled", lVal)) return .Disabled;
        return .Disabled;
    }
};

/// Logger configuration configuration
pub const Config = struct {
    /// log level, possible values (Trace | Debug | Info | Warn | Error | Fatal | Disabled)
    level: Level = Level.Info,
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

    /// flag enabling/disabling the error tracing reporting in the log
    stacktrace_ebabled: bool = false,
    /// field name for the error stacktrace
    stacktrace_field_name: []const u8 = "stacktrace",

    /// indicator what to do in case is there is a error occuring inside of logger, possible values as doing (nothing | panic | print)
    internal_failure: InternalFailure = InternalFailure.panic,

    /// caller related configuration options
    /// flag enabling/disabling the caller reporting in the log
    caller_enabled: bool = false,
    /// field name for the caller source
    caller_field_name: []const u8 = "caller",
    /// handler processing the source object data
    caller_marshal_fn: *const fn (std.builtin.SourceLocation) []const u8 = default_caller_marshal_fn,

    /// handler writing the data
    writer: std.fs.File = std.io.getStdOut(),

    /// struct marchalling to string options
    struct_union: StructUnionOptions = StructUnionOptions{},
};

/// struct marchalling to string options
pub const StructUnionOptions = struct {
    // flag enabling/disabling the escapping for marchalled structs
    // searching for \" and replacing with \\\" as per default values
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
buffer_pool: ?*const GenericPool(Utf8Buffer),
fields: Utf8Buffer,

pub fn init(allocator: std.mem.Allocator, config: Config) Self {
    return .{
        .allocator = allocator,
        .config = config,
        .buffer_pool = null,
        .fields = Utf8Buffer.init(allocator),
    };
}

pub fn deinit(self: *const Self) void {
    @constCast(self).fields.deinit();
}

pub fn initWithPool(allocator: std.mem.Allocator, buffer_pool: *const GenericPool(Utf8Buffer), config: Config) Self {
    return .{
        .allocator = allocator,
        .config = config,
        .buffer_pool = buffer_pool,
        .fields = Utf8Buffer.init(allocator),
    };
}

pub fn With(self: *const Self, name: []const u8, value: anytype) void {
    attribute(false, &self.fields, self.config, name, value);
}

pub fn Trace(self: *const Self, message: []const u8, args: anytype) void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.Trace)) return;

    self.send(Level.Trace, message, null, args);
}
pub fn Debug(self: *const Self, message: []const u8, args: anytype) void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.Debug)) return;

    self.send(Level.Debug, message, null, args);
}
pub fn Info(self: *const Self, message: []const u8, args: anytype) void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.Info)) return;

    self.send(Level.Info, message, null, args);
}
pub fn Warn(self: *const Self, message: []const u8, args: anytype) void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.Warn)) return;

    self.send(Level.Warn, message, null, args);
}
pub fn Error(self: *const Self, message: []const u8, err: ?anyerror, args: anytype) void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.Error)) return;

    self.send(Level.Error, message, err, args);
}
pub fn Fatal(self: *const Self, message: []const u8, err: anyerror, args: anytype) void {
    if (@intFromEnum(self.config.level) > @intFromEnum(Level.Fatal)) return;

    self.send(Level.Fatal, message, err, args);
}

inline fn send(self: *const Self, comptime op: Level, message: []const u8, err_value: ?anyerror, args: anytype) void {
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
                attribute(true, &buffer, self.config, opts.time_field_name, t.value);
            },
            inline .pattern => {
                var buf: [1024]u8 = undefined;
                const len = t.formatfInto(self.allocator, opts.time_pattern, &buf) catch |err| blk: {
                    failureFn(opts.internal_failure, "Failed to include data to the log buffer; {any}", .{err});
                    break :blk 0;
                };
                attribute(true, &buffer, self.config, opts.time_field_name, buf[0..len]);
            },
        }
    }

    // append the level
    attribute(!opts.time_enabled, &buffer, self.config, opts.level_field_name, op.String());

    // append the message
    attribute(false, &buffer, opts, opts.message_field_name, message);

    // append the static logger fields
    buffer.append(@constCast(&self.fields).bytes()) catch |err| {
        failureFn(opts.internal_failure, "Failed to store static fields; {any}", .{err});
    };

    // append the error
    if (err_value) |value| {
        attribute(false, &buffer, self.config, self.config.error_field_name, @errorName(value));

        if (self.config.stacktrace_ebabled) {
            if (@errorReturnTrace()) |stacktrace| {
                const debug_info: ?*std.debug.DebugInfo = std.debug.getSelfDebugInfo() catch res: {
                    break :res null;
                };
                if (debug_info) |di| {
                    var buff = Utf8Buffer.init(self.allocator);
                    errdefer buff.deinit();
                    defer buff.deinit();

                    std.debug.writeStackTrace(stacktrace.*, buff.writer(), self.allocator, di, .no_color) catch |err| {
                        failureFn(self.config.internal_failure, "Failed to include stacktrace to the log buffer; {any}", .{err});
                    };

                    if (buff.length() > 0) {
                        attribute(false, &buffer, self.config, self.config.stacktrace_field_name, buff.bytes());
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
                attribute(false, &buffer, self.config, self.config.caller_field_name, data);
            }
        }

        if (@hasField(arg_type, "key") and @hasField(arg_type, "value")) {
            attribute(false, &buffer, self.config, args[i].key, args[i].value);
        }
    }

    // append the end of record
    switch (self.config.format) {
        inline .text => {
            buffer.append("\n") catch |err| {
                failureFn(opts.internal_failure, "Failed to include data to the log buffer; {any}", .{err});
            };
        },
        inline .json => {
            buffer.append("}\n") catch |err| {
                failureFn(opts.internal_failure, "Failed to include data to the log buffer; {any}", .{err});
            };
        },
    }

    // send data
    _ = self.config.writer.write(buffer.bytes()) catch |err| {
        failureFn(self.config.internal_failure, "Failed to include data to the log buffer; {any}", .{err});
    };

    if (op == .Fatal) {
        @panic("fatal");
    }
}

fn attribute(first: bool, buffer: *const Utf8Buffer, config: Config, key: []const u8, value: anytype) void {
    var data: *Utf8Buffer = @constCast(buffer);

    const T = @TypeOf(value);
    const ty = @typeInfo(T);
    switch (ty) {
        .ErrorUnion => {
            if (value) |payload| {
                return attribute(first, buffer, config, key, payload);
            } else |err| {
                return attribute(first, buffer, config, key, err);
            }
        },
        .Type => {
            return attribute(first, buffer, config, key, @typeName(value));
        },
        .EnumLiteral => {
            const buf = [_]u8{'.'} ++ @tagName(value);
            return attribute(first, buffer, config, key, buf);
        },
        .Void => {
            return attribute(first, buffer, config, key, "void");
        },
        .Optional => {
            if (value) |payload| {
                return attribute(first, buffer, config, key, payload);
            } else {
                return attribute(first, buffer, config, key, null);
            }
        },
        .Fn => {},
        else => {},
    }

    switch (config.format) {
        inline .text => {
            const header = if (first) "" else " ";
            switch (ty) {
                .Enum => data.appendf("{s}{s}=\u{0022}{s}\u{0022}", .{ header, key, @typeName(value) }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{s}; {any}", .{ key, @typeName(value), err });
                },
                .Bool => data.appendf("{s}{s}=\u{0022}{s}\u{0022}", .{ header, key, if (value) "true" else "false" }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                },
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice => data.appendf("{s}{s}=\u{0022}{s}\u{0022}", .{ header, key, value }) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}:{s}; {any}", .{ key, value, err });
                    },
                    else => {},
                },
                .ComptimeInt, .Int, .ComptimeFloat, .Float => data.appendf("{s}{s}={any}", .{ header, key, value }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                },
                .ErrorSet => data.appendf("{s}{s}=\u{0022}{s}\u{0022}", .{ header, config.error_field_name, @errorName(value) }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{s}; {any}", .{ config.error_field_name, value, err });
                },
                .Null => data.appendf("{s}{s}=null", .{ header, key }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:null; {any}", .{ key, err });
                },
                .Struct, .Union => {
                    if (config.struct_union.escape_enabled) {
                        data.appendf("{s}{s}=\u{0022}", .{ header, key }) catch |err| {
                            failureFn(config.internal_failure, "Failed to consider struct attribute {s}; {any}", .{ key, err });
                        };
                    } else {
                        data.appendf("{s}{s}=", .{ header, key }) catch |err| {
                            failureFn(config.internal_failure, "Failed to consider struct attribute {s}; {any}", .{ key, err });
                        };
                    }

                    const cPos = data.length();
                    std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16)) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                    };

                    if (config.struct_union.escape_enabled) {
                        _ = data.replaceAllFromPos(
                            cPos,
                            config.struct_union.src_escape_characters,
                            config.struct_union.dst_escape_characters,
                        ) catch |err| {
                            failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                        };
                    }

                    if (config.struct_union.escape_enabled) {
                        data.appendf("\u{0022}", .{}) catch |err| {
                            failureFn(config.internal_failure, "Failed to consider struct attribute {s}; {any}", .{ key, err });
                        };
                    }
                },
                .Array, .Vector => {
                    data.appendf("{s}{s}=[", .{ header, key }) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ key, err });
                    };

                    for (value, 0..) |elem, i| {
                        attributeSingle(i == 0, buffer, config, elem);
                    }

                    data.appendf("]", .{}) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ key, err });
                    };
                },
                else => data.appendf("{s}{s}=\u{0022}{any}\u{0022}", .{ header, key, value }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                },
            }
        },
        inline .json => {
            const header = if (first) "{" else ", ";
            switch (ty) {
                .Enum => data.appendf("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ header, key, @typeName(value) }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{s}; {any}", .{ key, @typeName(value), err });
                },
                .Bool => data.appendf("{s}\u{0022}{s}\u{0022}: {s}", .{ header, key, if (value) "true" else "false" }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                },
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => data.appendf("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ header, key, value }) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}:{s}; {any}", .{ key, value, err });
                    },
                },
                .ComptimeInt, .Int, .ComptimeFloat, .Float => data.appendf("{s}\u{0022}{s}\u{0022}:{any}", .{ header, key, value }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                },
                .ErrorSet => data.appendf("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ header, key, @errorName(value) }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                },
                .Null => data.appendf("{s}\u{0022}{s}\u{0022}:null", .{ header, key }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:null; {any}", .{ key, err });
                },
                .Struct, .Union => {
                    data.appendf("{s}\u{0022}{s}\u{0022}:", .{ header, key }) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ key, err });
                    };

                    std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16)) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                    };
                },
                .Array, .Vector => {
                    data.appendf("{s}\u{0022}{s}\u{0022}: [", .{ header, key }) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ key, err });
                    };

                    for (value, 0..) |elem, i| {
                        attributeSingle(i == 0, buffer, config, elem);
                    }

                    data.appendf("]", .{}) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ key, err });
                    };
                },
                else => data.appendf("{s}\u{0022}{s}\u{0022}: \u{0022}{any}\u{0022}", .{ header, key, value }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}:{any}; {any}", .{ key, value, err });
                },
            }
        },
    }
}

fn attributeSingle(first: bool, buffer: *const Utf8Buffer, config: Config, value: anytype) void {
    var data: *Utf8Buffer = @constCast(buffer);

    const T = @TypeOf(value);
    const ty = @typeInfo(T);
    switch (config.format) {
        inline .text => {
            const header = if (first) "" else ", ";
            switch (ty) {
                .Enum => data.appendf("{s}\u{0022}{s}\u{0022}", .{ header, @typeName(value) }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ @typeName(value), err });
                },
                .Bool => data.appendf("{s}\u{0022}{s}\u{0022}", .{ header, if (value) "true" else "false" }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                },
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice => data.appendf("{s}\u{0022}{s}\u{0022}", .{ header, value }) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ value, err });
                    },
                    else => {},
                },
                .ComptimeInt, .Int, .ComptimeFloat, .Float => data.appendf("{s}{any}", .{ header, value }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                },
                .ErrorSet => data.appendf("{s}\u{0022}{s}\u{0022}", .{ header, @errorName(value) }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ value, err });
                },
                .Null => data.appendf("{s}null", .{header}) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute null; {any}", .{err});
                },
                .Struct, .Union => {
                    if (config.struct_union.escape_enabled) {
                        data.appendf("{s}\u{0022}", .{header}) catch |err| {
                            failureFn(config.internal_failure, "Failed to consider struct attribute; {any}", .{err});
                        };
                    } else {
                        data.appendf("{s}", .{header}) catch |err| {
                            failureFn(config.internal_failure, "Failed to consider struct attribute; {any}", .{err});
                        };
                    }

                    const cPos = data.length();
                    std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16)) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                    };

                    if (config.struct_union.escape_enabled) {
                        _ = data.replaceAllFromPos(
                            cPos,
                            config.struct_union.src_escape_characters,
                            config.struct_union.dst_escape_characters,
                        ) catch |err| {
                            failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                        };
                    }

                    if (config.struct_union.escape_enabled) {
                        data.appendf("\u{0022}", .{}) catch |err| {
                            failureFn(config.internal_failure, "Failed to consider struct attribute; {any}", .{err});
                        };
                    }
                },
                .Array, .Vector => {
                    data.appendf("{s} [", .{header}) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute; {any}", .{err});
                    };

                    for (value, 0..) |elem, i| {
                        attributeSingle(i == 0, buffer, config, elem);
                    }

                    data.appendf("]", .{}) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute; {any}", .{err});
                    };
                },
                else => data.appendf("{s}\u{0022}{any}\u{0022}", .{ header, value }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                },
            }
        },
        inline .json => {
            const header = if (first) "" else ", ";
            switch (ty) {
                .Enum => data.appendf("{s}\u{0022}{s}\u{0022}", .{ header, @typeName(value) }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ @typeName(value), err });
                },
                .Bool => data.appendf("{s}{s}", .{ header, if (value) "true" else "false" }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                },
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .Slice, .Many, .One, .C => data.appendf("{s}\u{0022}{s}\u{0022}", .{ header, value }) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {s}; {any}", .{ value, err });
                    },
                },
                .ComptimeInt, .Int, .ComptimeFloat, .Float => data.appendf("{s}{any}", .{ header, value }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                },
                .ErrorSet => data.appendf("{s}\u{0022}{s}\u{0022}", .{ header, @errorName(value) }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                },
                .Null => data.appendf("{s}null", .{header}) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute null; {any}", .{err});
                },
                .Struct, .Union => {
                    data.appendf("{s}", .{header}) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute; {any}", .{err});
                    };

                    std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16)) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                    };
                },
                .Array, .Vector => {
                    data.appendf("{s} [", .{header}) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute; {any}", .{err});
                    };

                    for (value, 0..) |elem, i| {
                        attributeSingle(i == 0, buffer, config, elem);
                    }

                    data.appendf("]", .{}) catch |err| {
                        failureFn(config.internal_failure, "Failed to consider attribute; {any}", .{err});
                    };
                },
                else => data.appendf("{s}\u{0022}{any}\u{0022}", .{ header, value }) catch |err| {
                    failureFn(config.internal_failure, "Failed to consider attribute {any}; {any}", .{ value, err });
                },
            }
        },
    }
}

fn failureFn(on: InternalFailure, comptime format: []const u8, args: anytype) void {
    switch (on) {
        inline .panic => std.debug.panic(format, args),
        inline .print => std.debug.print(format, args),
        else => undefined,
    }
}

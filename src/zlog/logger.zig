const std = @import("std");

const GenericPool = @import("../pool/mod.zig").Generic;
const Utf8Buffer = @import("../bytes/mod.zig").Utf8Buffer;

const Time = @import("../time/mod.zig").Time;
const Local = @import("../time/mod.zig").zoneinfo.Local;
const Measure = @import("../time/mod.zig").Measure;

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

/// Logger configuration options
pub const Options = struct {
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
    message_field_name: []const u8 = "message",
    /// field name for the error
    error_field_name: []const u8 = "error",

    /// flag enabling/disabling the error tracing reporting in the log
    stacktrace_ebabled: bool = false,
    /// field name for the error stacktrace
    stacktrace_field_name: []const u8 = "stacktrace",

    /// indicator what to do in case is there is a error occuring inside of logger, possible values as doing (nothing | panic | print)
    internal_failure: InternalFailure = InternalFailure.nothing,

    /// caller related configuration options
    /// flag enabling/disabling the caller reporting in the log
    caller_enabled: bool = false,
    /// field name for the caller source
    caller_field_name: []const u8 = "caller",
    /// handler processing the source object data
    caller_marshal_fn: *const fn (std.builtin.SourceLocation) []const u8 = default_caller_marshal_fn,

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

pub const Logger = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffer_pool: ?*const GenericPool(Utf8Buffer),
    options: Options,
    static_fields: Utf8Buffer,

    pub fn init(allocator: std.mem.Allocator, options: Options) !Self {
        return .{
            .allocator = allocator,
            .buffer_pool = null,
            .options = options,
            .static_fields = Utf8Buffer.init(allocator),
        };
    }

    pub fn deinit(self: *const Self) void {
        @constCast(self).static_fields.deinit();
    }

    pub fn initWithPool(allocator: std.mem.Allocator, buffer_pool: *const GenericPool(Utf8Buffer), options: Options) !Self {
        return .{
            .allocator = allocator,
            .buffer_pool = buffer_pool,
            .options = options,
            .static_fields = Utf8Buffer.init(allocator),
        };
    }

    pub fn With(self: *const Self, name: []const u8, value: anytype) void {
        attribute(false, &self.static_fields, self.options, name, value);
    }

    pub fn Trace(self: *const Self, message: []const u8, args: anytype) void {
        if (@intFromEnum(self.options.level) > @intFromEnum(Level.Trace)) return;

        self.send(Level.Trace, message, null, args);
    }
    pub fn Debug(self: *const Self, message: []const u8, args: anytype) void {
        if (@intFromEnum(self.options.level) > @intFromEnum(Level.Debug)) return;

        self.send(Level.Debug, message, null, args);
    }
    pub fn Info(self: *const Self, message: []const u8, args: anytype) void {
        if (@intFromEnum(self.options.level) > @intFromEnum(Level.Info)) return;

        self.send(Level.Info, message, null, args);
    }
    pub fn Warn(self: *const Self, message: []const u8, args: anytype) void {
        if (@intFromEnum(self.options.level) > @intFromEnum(Level.Warn)) return;

        self.send(Level.Warn, message, null, args);
    }
    pub fn Error(self: *const Self, message: []const u8, err: anyerror, args: anytype) void {
        if (@intFromEnum(self.options.level) > @intFromEnum(Level.Error)) return;

        self.send(Level.Error, message, err, args);
    }
    pub fn Fatal(self: *const Self, message: []const u8, err: anyerror, args: anytype) void {
        if (@intFromEnum(self.options.level) > @intFromEnum(Level.Fatal)) return;

        self.send(Level.Fatal, message, err, args);
    }

    inline fn send(self: *const Self, comptime op: Level, message: []const u8, err_value: ?anyerror, args: anytype) void {
        var buffer = if (self.buffer_pool) |p| p.pop() else Utf8Buffer.initWithFactor(self.allocator, 10);
        errdefer {
            if (self.buffer_pool) |p| {
                buffer.clear();
                p.push(&buffer) catch |err| {
                    std.debug.print("Error - {any}", .{err});
                };
            } else {
                buffer.deinit();
            }
        }
        defer {
            if (self.buffer_pool) |p| {
                buffer.clear();
                p.push(&buffer) catch |err| {
                    std.debug.print("Error - {any}", .{err});
                };
            } else {
                buffer.deinit();
            }
        }

        // add the timstamp
        const opts = self.options;
        if (opts.time_enabled) {
            const t = Time.new(opts.time_measure);

            switch (opts.time_formating) {
                .timestamp => {
                    attribute(true, &buffer, self.options, opts.time_field_name, t.value);
                },
                .pattern => {
                    var buf: [1024]u8 = undefined;
                    const len = t.formatfInto(self.allocator, opts.time_pattern, &buf) catch |err| blk: {
                        failureFn(opts.internal_failure, "Failed to include data to the log buffer; {}", .{err});
                        break :blk 0;
                    };
                    attribute(true, &buffer, self.options, opts.time_field_name, buf[0..len]);
                },
            }
        }

        // append the level
        attribute(!opts.time_enabled, &buffer, self.options, opts.level_field_name, op.String());

        // append the message
        attribute(false, &buffer, opts, opts.message_field_name, message);

        // append the static logger fields
        buffer.append(@constCast(&self.static_fields).bytes()) catch |err| {
            failureFn(opts.internal_failure, "Failed to store static fields; {}", .{err});
        };

        // append the error
        if (err_value) |value| {
            attribute(false, &buffer, self.options, self.options.error_field_name, @errorName(value));

            if (self.options.stacktrace_ebabled) {
                if (@errorReturnTrace()) |stacktrace| {
                    const debug_info: ?*std.debug.DebugInfo = std.debug.getSelfDebugInfo() catch res: {
                        break :res null;
                    };
                    if (debug_info) |di| {
                        var buff = Utf8Buffer.init(self.allocator);
                        errdefer buff.deinit();
                        defer buff.deinit();

                        std.debug.writeStackTrace(stacktrace.*, buff.writer(), self.allocator, di, .no_color) catch |err| {
                            failureFn(self.options.internal_failure, "Failed to include stacktrace to the log buffer; {}", .{err});
                        };

                        if (buff.length() > 0) {
                            attribute(false, &buffer, self.options, self.options.stacktrace_field_name, buff.bytes());
                        }
                    }
                }
            }
        }

        // append the all other fields
        inline for (0..args.len) |i| {
            const arg_type = @TypeOf(args[i]);
            if (@hasField(arg_type, "src_value")) {
                if (self.options.caller_enabled) {
                    const data = self.options.caller_marshal_fn(args[i].src_value);
                    attribute(false, &buffer, self.options, self.options.caller_field_name, data);
                }
            }

            if (@hasField(arg_type, "key") and @hasField(arg_type, "value")) {
                attribute(false, &buffer, self.options, args[i].key, args[i].value);
            }
        }

        // append the end of record
        switch (self.options.format) {
            inline .text => {
                buffer.append("\n") catch |err| {
                    failureFn(opts.internal_failure, "Failed to include data to the log buffer; {}", .{err});
                };
            },
            inline .json => {
                buffer.append("}\n") catch |err| {
                    failureFn(opts.internal_failure, "Failed to include data to the log buffer; {}", .{err});
                };
            },
        }

        // send data
        _ = std.io.getStdOut().writer().write(buffer.bytes()) catch |err| {
            failureFn(self.options.internal_failure, "Failed to include data to the log buffer; {}", .{err});
        };

        if (op == .Fatal) {
            @panic("fatal");
        }
    }

    fn failureFn(on: InternalFailure, comptime format: []const u8, args: anytype) void {
        switch (on) {
            inline .panic => std.debug.panic(format, args),
            inline .print => std.debug.print(format, args),
            else => {},
        }
    }

    fn attribute(first: bool, staticfields: *const Utf8Buffer, options: Options, key: []const u8, value: anytype) void {
        var data = @constCast(staticfields);
        const T = @TypeOf(value);
        const ty = @typeInfo(T);

        switch (ty) {
            .ErrorUnion => {
                if (value) |payload| {
                    return attribute(first, staticfields, options, key, payload);
                } else |err| {
                    return attribute(first, staticfields, options, key, err);
                }
            },
            .Type => {
                return attribute(first, staticfields, options, key, @typeName(value));
            },
            .EnumLiteral => {
                const buffer = [_]u8{'.'} ++ @tagName(value);
                return attribute(first, staticfields, options, key, buffer);
            },
            .Void => {
                return attribute(first, staticfields, options, key, "void");
            },
            .Optional => {
                if (value) |payload| {
                    return attribute(first, staticfields, options, key, payload);
                } else {
                    return attribute(first, staticfields, options, key, null);
                }
            },
            .Fn => {},
            else => {},
        }

        switch (options.format) {
            inline .text => {
                switch (ty) {
                    .Enum => data.appendf(" {s}=\u{0022}{s}\u{0022}", .{ key, @typeName(value) }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, @typeName(value), err });
                    },
                    .Bool => data.appendf(" {s}=\u{0022}{s}\u{0022}", .{ key, if (value) "true" else "false" }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                    },
                    .Pointer => |ptr_info| switch (ptr_info.size) {
                        .Slice => data.appendf(" {s}=\u{0022}{s}\u{0022}", .{ key, value }) catch |err| {
                            failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                        },
                        else => {},
                    },
                    .ComptimeInt, .Int, .ComptimeFloat, .Float => data.appendf(" {s}={}", .{ key, value }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                    },
                    .ErrorSet => data.appendf(" {s}=\u{0022}{s}\u{0022}", .{ options.error_field_name, @errorName(value) }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ options.error_field_name, value, err });
                    },
                    .Null => data.appendf(" {s}=null", .{key}) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:null; {}", .{ key, err });
                    },
                    .Struct, .Union => {
                        if (options.struct_union.escape_enabled) {
                            data.appendf(" {s}=\u{0022}", .{key}) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider struct json  attribute {s}; {}", .{ key, err });
                            };
                        } else {
                            data.appendf(" {s}=", .{key}) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider struct json  attribute {s}; {}", .{ key, err });
                            };
                        }

                        const cPos = data.length();
                        std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16)) catch |err| {
                            failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                        };

                        if (options.struct_union.escape_enabled) {
                            _ = data.replaceAllFromPos(
                                cPos,
                                options.struct_union.src_escape_characters,
                                options.struct_union.dst_escape_characters,
                            ) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                            };
                        }

                        if (options.struct_union.escape_enabled) {
                            data.appendf("\u{0022}", .{}) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider struct json attribute {s}; {}", .{ key, err });
                            };
                        }
                    },
                    else => data.appendf(" {s}=\u{0022}{}\u{0022}", .{ key, value }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                    },
                }
            },
            inline .json => {
                const comma = if (first) "{" else ", ";
                switch (ty) {
                    .Enum => data.appendf("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ comma, key, @typeName(value) }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, @typeName(value), err });
                    },
                    .Bool => data.appendf("{s}\u{0022}{s}\u{0022}: {s}", .{ comma, key, if (value) "true" else "false" }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                    },
                    .Pointer => |ptr_info| switch (ptr_info.size) {
                        .Slice, .Many, .One, .C => data.appendf("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ comma, key, value }) catch |err| {
                            failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                        },
                    },
                    .ComptimeInt, .Int, .ComptimeFloat, .Float => data.appendf("{s} \u{0022}{s}\u{0022}:{}", .{ comma, key, value }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                    },
                    .ErrorSet => data.appendf("{s}\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ comma, key, @errorName(value) }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                    },
                    .Null => data.appendf("{s}\u{0022}{s}\u{0022}:null", .{ comma, key }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:null; {}", .{ key, err });
                    },
                    .Struct, .Union => {
                        data.appendf("{s}\u{0022}{s}\u{0022}:", .{ comma, key }) catch |err| {
                            failureFn(options.internal_failure, "Failed to consider attribute {s}; {}", .{ key, err });
                        };

                        std.json.stringifyMaxDepth(value, .{}, data.writer(), std.math.maxInt(u16)) catch |err| {
                            failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                        };
                    },
                    else => data.appendf("{s}\u{0022}{s}\u{0022}: \u{0022}{}\u{0022}", .{ comma, key, value }) catch |err| {
                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                    },
                }
            },
        }
    }
};

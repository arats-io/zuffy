const std = @import("std");

const Buffer = @import("../bytes/mod.zig").Buffer;
const Utf8Buffer = @import("../bytes/mod.zig").Utf8Buffer;

const Time = @import("../time/mod.zig").Time;
const Local = @import("../time/mod.zig").zoneinfo.Local;
const Measure = @import("../time/mod.zig").Measure;

const TimeFormating = @import("common.zig").TimeFormating;
const Format = @import("common.zig").Format;
const Level = @import("common.zig").Level;
const InternalFailure = @import("common.zig").InternalFailure;

const default_caller_marshal_fn = struct {
    fn handler(src: std.builtin.SourceLocation) []const u8 {
        var buf: [10 * 1024]u8 = undefined;
        const data = std.fmt.bufPrint(&buf, "{s}:{}", .{ src.file, src.line }) catch "";
        return data[0..];
    }
}.handler;

const _ = Local.Get();

pub const Options = struct {
    level: Level = Level.Info,
    level_field_name: []const u8 = "level",

    format: Format = Format.simple,

    time_enabled: bool = false,
    time_field_name: []const u8 = "time",
    time_measure: Measure = Measure.seconds,
    time_formating: TimeFormating = TimeFormating.timestamp,
    time_pattern: []const u8 = "DD/MM/YYYY'T'HH:mm:ss",

    message_field_name: []const u8 = "message",
    error_field_name: []const u8 = "error",

    internal_failure: InternalFailure = InternalFailure.nothing,

    caller_enabled: bool = false,
    caller_field_name: []const u8 = "caller",
    caller_marshal_fn: *const fn (std.builtin.SourceLocation) []const u8 = default_caller_marshal_fn,
};

pub const Logger = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    options: Options,

    pub fn init(allocator: std.mem.Allocator, options: Options) Self {
        return Self{
            .allocator = allocator,
            .options = options,
        };
    }

    inline fn entry(self: Self, comptime op: Level) Entry {
        return Entry.init(
            self.allocator,
            if (@intFromEnum(self.options.level) > @intFromEnum(op)) null else self.options,
            op,
        );
    }

    pub fn Trace(self: Self) Entry {
        return self.entry(Level.Trace);
    }
    pub fn Debug(self: Self) Entry {
        return self.entry(Level.Debug);
    }
    pub fn Info(self: Self) Entry {
        return self.entry(Level.Info);
    }
    pub fn Warn(self: Self) Entry {
        return self.entry(Level.Warn);
    }
    pub fn Error(self: Self) Entry {
        return self.entry(Level.Error);
    }
    pub fn Fatal(self: Self) Entry {
        return self.entry(Level.Fatal);
    }
    pub fn Disabled(self: Self) Entry {
        return self.entry(Level.Disabled);
    }
};

const Elem = struct {
    key_ptr: usize,
    key_size: usize,
    value_ptr: usize,
    value_size: usize,
};

pub const Entry = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    options: ?Options = null,
    opLevel: Level = .Disabled,

    elems: std.ArrayList(Elem),

    fn init(
        allocator: std.mem.Allocator,
        options: ?Options,
        opLevel: Level,
    ) Self {
        return Self{
            .allocator = allocator,
            .options = options,
            .opLevel = opLevel,
            .elems = std.ArrayList(Elem).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.elems.deinit();

        while (self.elems.popOrNull()) |elem| {
            const key_ptr = elem.key_ptr;
            const key_size = elem.key_size;
            const value_ptr = elem.value_ptr;
            const value_size = elem.value_size;

            var key_buffer = @as([*]const u8, @ptrFromInt(key_ptr))[0..key_size];
            self.allocator.free(key_buffer);
            var value_buffer = @as([*]const u8, @ptrFromInt(value_ptr))[0..value_size];
            self.allocator.free(value_buffer);
        }
    }

    pub fn Attr(self: *Self, key: []const u8, comptime V: type, value: V) *Self {
        if (self.options) |options| {
            var strValue = Utf8Buffer.init(self.allocator);
            defer strValue.deinit();
            errdefer strValue.deinit();

            switch (@TypeOf(value)) {
                []const u8 => strValue.appendf("{s}", .{value}) catch |err| {
                    failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                },
                else => strValue.appendf("{}", .{value}) catch |err| {
                    failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                },
            }

            if (strValue.contains(" ")) {
                switch (options.format) {
                    .simple => {
                        strValue.insertAt("\u{0022}", 0) catch |err| {
                            failureFn(options.internal_failure, "Failed to insert and unicode code \u{0022}; {}", .{err});
                        };
                        strValue.append("\u{0022}") catch |err| {
                            failureFn(options.internal_failure, "Failed to insert and unicode code \u{0022}; {}", .{err});
                        };
                    },
                    .json => {},
                }
            }

            var strKey = Utf8Buffer.init(self.allocator);
            defer strKey.deinit();
            errdefer strKey.deinit();

            _ = strKey.append(key) catch |err| {
                failureFn(options.internal_failure, "Failed to write the key into the buffer; {}", .{err});
            };

            var key_buffer = strKey.bytesWithAllocator(self.allocator) catch |err| blk: {
                failureFn(options.internal_failure, "Failed to write the key into the buffer; {}", .{err});
                break :blk &.{};
            };
            errdefer self.allocator.free(key_buffer);

            var value_buffer = strValue.bytesWithAllocator(self.allocator) catch |err| blk: {
                failureFn(options.internal_failure, "Failed to write the key into the buffer; {}", .{err});
                break :blk &.{};
            };
            errdefer self.allocator.free(value_buffer);

            const elem = Elem{
                .key_ptr = @intFromPtr(key_buffer.ptr),
                .key_size = key_buffer.len,
                .value_ptr = @intFromPtr(value_buffer.ptr),
                .value_size = value_buffer.len,
            };
            self.elems.append(elem) catch |err| {
                failureFn(options.internal_failure, "Attribute could not be included into the list; {}", .{err});
            };
        }

        return self;
    }

    pub fn Error(self: *Self, value: anyerror) *Self {
        if (self.options) |options| {
            _ = self.Attr(options.error_field_name, []const u8, @errorName(value));
        }
        return self;
    }

    pub fn Source(self: *Self, src: std.builtin.SourceLocation) *Self {
        if (self.options) |options| {
            if (options.caller_enabled) {
                const data = options.caller_marshal_fn(src);
                return self.Attr(options.caller_field_name[0..], []const u8, data);
            }
        }

        return self;
    }

    pub fn MsgWriter(self: *Self, message: []const u8, writer: anytype) !void {
        defer self.deinit();
        errdefer self.deinit();

        if (self.options) |options| {
            switch (options.format) {
                inline .simple => try self.simpleMsg(message, writer),
                inline .json => try self.jsonMsg(message, writer),
            }
        }
    }

    pub fn Msg(self: *Self, message: []const u8) !void {
        try self.MsgStdOut(message);
    }

    pub fn MsgStdOut(self: *Self, message: []const u8) !void {
        try self.MsgWriter(message, std.io.getStdOut().writer());
    }

    pub fn MsgStdErr(self: *Self, message: []const u8) !void {
        try self.MsgWriter(message, std.io.getStdErr().writer());
    }

    pub fn MsgStdIn(self: *Self, message: []const u8) !void {
        try self.MsgWriter(message, std.io.getStdIn().writer());
    }

    fn jsonMsg(self: *Self, message: []const u8, writer: anytype) !void {
        if (self.options) |options| {
            var str = Utf8Buffer.init(self.allocator);
            defer str.deinit();
            errdefer str.deinit();

            try str.append("{");

            if (options.time_enabled) {
                const t = Time.new(options.time_measure);

                switch (options.time_formating) {
                    .timestamp => {
                        try str.appendf("\u{0022}{s}\u{0022}:{}, ", .{ options.time_field_name, t.value });
                    },
                    .pattern => {
                        var buffer: [1024]u8 = undefined;
                        const len = try t.format(self.allocator, options.time_pattern, &buffer);
                        try str.appendf("\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}, ", .{ options.time_field_name, buffer[0..len] });
                    },
                }
            }
            try str.appendf("\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ options.level_field_name, self.opLevel.String() });
            if (message.len > 0) {
                try str.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ options.message_field_name, message });
            }

            while (self.elems.popOrNull()) |elem| {
                const key_ptr = elem.key_ptr;
                const key_size = elem.key_size;
                const value_ptr = elem.value_ptr;
                const value_size = elem.value_size;

                var key_buffer = @as([*]const u8, @ptrFromInt(key_ptr))[0..key_size];
                defer self.allocator.free(key_buffer);
                var value_buffer = @as([*]const u8, @ptrFromInt(value_ptr))[0..value_size];
                defer self.allocator.free(value_buffer);

                try str.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ key_buffer, value_buffer });
            }

            try str.append("}\n");

            _ = try writer.write(str.bytes());

            if (self.opLevel == .Fatal) {
                @panic("logger on fatal");
            }
        }
    }

    fn simpleMsg(self: *Self, message: []const u8, writer: anytype) !void {
        if (self.options) |options| {
            var str = Utf8Buffer.init(self.allocator);
            defer str.deinit();
            errdefer str.deinit();

            if (options.time_enabled) {
                const t = Time.new(options.time_measure);
                switch (options.time_formating) {
                    .timestamp => {
                        try str.appendf("{}, ", .{t.value});
                    },
                    .pattern => {
                        var buffer: [512]u8 = undefined;
                        const len = try t.format(self.allocator, options.time_pattern, &buffer);
                        try str.appendf("{s} ", .{buffer[0..len]});
                    },
                }
            }

            try str.appendf("{s}", .{self.opLevel.String().ptr[0..4]});
            if (message.len > 0) {
                try str.appendf(" {s}", .{message});
            }
            try str.append(" ");

            while (self.elems.popOrNull()) |elem| {
                const key_ptr = elem.key_ptr;
                const key_size = elem.key_size;
                const value_ptr = elem.value_ptr;
                const value_size = elem.value_size;

                var key_buffer = @as([*]const u8, @ptrFromInt(key_ptr))[0..key_size];
                defer self.allocator.free(key_buffer);
                var value_buffer = @as([*]const u8, @ptrFromInt(value_ptr))[0..value_size];
                defer self.allocator.free(value_buffer);

                try str.appendf("{s}={s} ", .{ key_buffer, value_buffer });
            }

            try str.removeEnd(1);
            try str.append("\n");

            _ = try writer.write(str.bytes());

            if (self.opLevel == .Fatal) {
                @panic("logger on fatal");
            }
        }
    }

    pub fn SendWriter(self: *Self, writer: anytype) void {
        self.MsgWriter("", writer);
    }

    pub fn Send(self: *Self) void {
        self.Msg("");
    }

    pub fn SendStdOut(self: *Self) void {
        self.MsgStdOut("");
    }

    pub fn SendStdErr(self: *Self) void {
        self.MsgStdErr("");
    }

    pub fn SendStdIn(self: *Self) void {
        self.MsgStdIn("");
    }

    fn failureFn(on: InternalFailure, comptime format: []const u8, args: anytype) void {
        switch (on) {
            inline .panic => std.debug.panic(format, args),
            inline .print => std.debug.print(format, args),
            else => {},
        }
    }
};

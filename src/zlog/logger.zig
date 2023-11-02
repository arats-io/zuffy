const std = @import("std");

const StringBuilder = @import("../bytes/mod.zig").StringBuilder;

const Time = @import("../time/mod.zig").Time;
const Measure = @import("../time/mod.zig").Measure;

const Format = @import("common.zig").Format;
const Level = @import("common.zig").Level;
const InternalFailure = @import("common.zig").InternalFailure;

pub const LoggerBuilder = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    log_level: Level,
    log_format: Format,
    time_measure: Measure,
    time_enabled: bool,
    time_pattern: []const u8,
    internal_failure: InternalFailure,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .log_level = Level.Info,
            .log_format = Format.simple,
            .time_measure = Measure.seconds,
            .time_enabled = false,
            .time_pattern = "DD/MM/YYYY'T'HH:mm:ss",
            .internal_failure = InternalFailure.nothing,
        };
    }

    pub fn Timestamp(self: Self) Self {
        return Self{
            .allocator = self.allocator,
            .log_level = self.log_level,
            .log_format = self.log_format,
            .time_measure = self.time_measure,
            .time_enabled = true,
            .time_pattern = self.time_pattern,
            .internal_failure = self.internal_failure,
        };
    }

    pub fn GlobalLevel(self: Self, level: Level) Self {
        return Self{
            .allocator = self.allocator,
            .log_level = level,
            .log_format = self.log_format,
            .time_measure = self.time_measure,
            .time_enabled = self.time_enabled,
            .time_pattern = self.time_pattern,
            .internal_failure = self.internal_failure,
        };
    }

    pub fn OutputFormat(self: Self, format: Format) Self {
        return Self{
            .allocator = self.allocator,
            .log_level = self.log_level,
            .log_format = format,
            .time_measure = self.time_measure,
            .time_enabled = self.time_enabled,
            .time_pattern = self.time_pattern,
            .internal_failure = self.internal_failure,
        };
    }

    pub fn TimePattern(self: Self, pattern: []const u8) Self {
        return Self{
            .allocator = self.allocator,
            .log_level = self.log_level,
            .log_format = self.log_format,
            .time_measure = self.time_measure,
            .time_enabled = self.time_enabled,
            .time_pattern = pattern,
            .internal_failure = self.internal_failure,
        };
    }

    pub fn TimeMeasure(self: Self, timemeasure: Measure) Self {
        return Self{
            .allocator = self.allocator,
            .log_level = self.log_level,
            .log_format = self.log_format,
            .time_measure = timemeasure,
            .time_enabled = self.time_enabled,
            .time_pattern = self.time_pattern,
            .internal_failure = self.internal_failure,
        };
    }

    pub fn InternalFailureFn(self: Self, failure: InternalFailure) Self {
        return Self{
            .allocator = self.allocator,
            .log_level = self.log_level,
            .log_format = self.log_format,
            .time_measure = self.time_measure,
            .time_enabled = self.time_enabled,
            .time_pattern = self.time_pattern,
            .internal_failure = failure,
        };
    }

    pub fn build(self: Self) Logger {
        return Logger{
            .allocator = self.allocator,
            .log_level = self.log_level,
            .log_format = self.log_format,
            .time_measure = self.time_measure,
            .time_enabled = self.time_enabled,
            .time_pattern = self.time_pattern,
            .internal_failure = self.internal_failure,
        };
    }
};

pub const Logger = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    log_level: Level,
    log_format: Format,
    time_measure: Measure,
    time_enabled: bool,
    time_pattern: []const u8,
    internal_failure: InternalFailure,

    pub fn init(
        allocator: std.mem.Allocator,
        log_level: Level,
        log_format: Format,
        time_measure: Measure,
        time_enabled: bool,
        time_pattern: []const u8,
        internal_failure: InternalFailure,
    ) Self {
        return Self{
            .allocator = allocator,
            .log_level = log_level,
            .log_format = log_format,
            .time_measure = time_measure,
            .time_enabled = time_enabled,
            .time_pattern = time_pattern,
            .internal_failure = internal_failure,
        };
    }

    inline fn entry(self: Self, comptime op: Level) Entry {
        return Entry.init(
            self.allocator,
            if (@intFromEnum(self.log_level) > @intFromEnum(op)) null else self,
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

pub const Entry = struct {
    const Self = @This();

    logger: ?Logger = null,
    opLevel: Level = .Disabled,

    elems: std.StringHashMap([]const u8),

    fn initEmpty() Self {
        return Self{};
    }

    fn init(
        allocator: std.mem.Allocator,
        logger: ?Logger,
        opLevel: Level,
    ) Self {
        return Self{
            .logger = logger,
            .opLevel = opLevel,
            .elems = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.logger) |logger| {
            var iter = self.elems.iterator();
            while (iter.next()) |entry| {
                logger.allocator.free(entry.value_ptr.*);
            }

            self.elems.deinit();
        }
    }

    pub fn Attr(self: *Self, key: []const u8, comptime V: type, value: V) *Self {
        if (self.logger) |logger| {
            var str = StringBuilder.init(logger.allocator);

            switch (@TypeOf(value)) {
                []const u8 => str.appendf("{s}", .{value}) catch |err| {
                    failureFn(logger.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                },
                else => str.appendf("{}", .{value}) catch |err| {
                    failureFn(logger.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                },
            }

            if (str.find(" ")) |_| {
                switch (logger.log_format) {
                    .simple => {
                        str.insertAt("\u{0022}", 0) catch |err| {
                            failureFn(logger.internal_failure, "Failed to insert and unicode code \u{0022}; {}", .{err});
                        };
                        str.append("\u{0022}") catch |err| {
                            failureFn(logger.internal_failure, "Failed to insert and unicode code \u{0022}; {}", .{err});
                        };
                    },
                    .json => {},
                }
            }

            str.shrink() catch |err| {
                failureFn(logger.internal_failure, "Failed to shrink the result; {}", .{err});
            };

            self.elems.put(key, str.bytes()) catch |err| {
                failureFn(logger.internal_failure, "Failed to store the attribute; {}", .{err});
            };
        }

        return self;
    }

    pub fn Error(self: *Self, value: anyerror) *Self {
        return self.Attr("error", []const u8, @errorName(value));
    }

    pub fn MsgWriter(self: *Self, message: []const u8, writer: anytype) !void {
        if (self.logger) |logger| {
            switch (logger.log_format) {
                inline .simple => try self.simpleMsg(message, writer),
                inline .json => try self.jsonMsg(message, writer),
            }
        }
    }

    pub fn Msg(self: *Self, message: []const u8) !void {
        return self.MsgStdOut(message);
    }

    pub fn MsgStdOut(self: *Self, message: []const u8) !void {
        return self.MsgWriter(message, std.io.getStdOut());
    }

    pub fn MsgStdErr(self: *Self, message: []const u8) !void {
        return self.MsgWriter(message, std.io.getStdErr());
    }

    pub fn MsgStdIn(self: *Self, message: []const u8) !void {
        return self.MsgWriter(message, std.io.getStdIn());
    }

    fn jsonMsg(self: *Self, message: []const u8, writer: anytype) !void {
        if (self.logger) |logger| {
            defer self.deinit();

            var str = StringBuilder.init(logger.allocator);
            defer str.deinit();

            try str.append("{");

            const t = Time.new(logger.time_measure);

            if (logger.time_enabled) {
                var buffer: [512]u8 = undefined;
                const len = try t.format(logger.time_pattern, &buffer);
                try str.appendf("\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}, ", .{ "timestamp", buffer[0..len] });
            }
            try str.appendf("\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ "level", self.opLevel.String() });
            if (message.len > 0) {
                try str.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ "message", message });
            }

            var iter = self.elems.iterator();
            while (iter.next()) |entry| {
                try str.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ entry.key_ptr.*, entry.value_ptr.* });
            }

            try str.append("}\n");

            try str.shrink();

            const result = str.bytes();

            _ = try writer.write(result);

            if (self.opLevel == .Fatal) {
                @panic("logger on fatal");
            }
        }
    }

    fn simpleMsg(self: *Self, message: []const u8, writer: anytype) !void {
        if (self.logger) |logger| {
            defer self.deinit();

            var str = StringBuilder.init(logger.allocator);
            defer str.deinit();

            const t = Time.new(logger.time_measure);

            if (logger.time_enabled) {
                var buffer: [512]u8 = undefined;
                const len = try t.format(logger.time_pattern, &buffer);
                try str.appendf("{s} ", .{buffer[0..len]});
            }

            try str.appendf("{s}", .{self.opLevel.String().ptr[0..4]});
            if (message.len > 0) {
                try str.appendf(" {s}", .{message});
            }
            try str.append(" ");

            var iter = self.elems.iterator();
            while (iter.next()) |entry| {
                try str.appendf("{s}={s} ", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            try str.removeEnd(1);
            try str.append("\n");

            try str.shrink();

            const result = str.bytes();

            _ = try writer.write(result);

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

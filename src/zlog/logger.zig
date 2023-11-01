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
    log_writer: std.fs.File.Writer,
    internalFailure: InternalFailure,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .log_level = Level.Info,
            .log_format = Format.simple,
            .time_measure = Measure.seconds,
            .time_enabled = false,
            .time_pattern = "DD/MM/YYYY'T'HH:mm:ss",
            .internalFailure = InternalFailure.nothing,
            .log_writer = std.io.getStdOut().writer(),
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
            .internalFailure = self.internalFailure,
            .log_writer = self.log_writer,
        };
    }

    pub fn OutputWriter(self: Self, writer: std.fs.File.Writer) Self {
        return Self{
            .allocator = self.allocator,
            .log_level = self.log_level,
            .log_format = self.log_format,
            .time_measure = self.time_measure,
            .time_enabled = self.time_enabled,
            .time_pattern = self.time_pattern,
            .internalFailure = self.internalFailure,
            .log_writer = writer,
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
            .internalFailure = self.internalFailure,
            .log_writer = self.log_writer,
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
            .internalFailure = self.internalFailure,
            .log_writer = self.log_writer,
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
            .internalFailure = self.internalFailure,
            .log_writer = self.log_writer,
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
            .internalFailure = self.internalFailure,
            .log_writer = self.log_writer,
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
            .internalFailure = failure,
            .log_writer = self.log_writer,
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
            .internalFailure = self.internalFailure,
            .log_writer = self.log_writer,
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
    log_writer: std.fs.File.Writer,
    internalFailure: InternalFailure,

    pub fn init(
        allocator: std.mem.Allocator,
        log_level: Level,
        log_format: Format,
        time_measure: Measure,
        time_enabled: bool,
        time_pattern: []const u8,
        internalFailure: InternalFailure,
        log_writer: std.fs.File.Writer,
    ) Self {
        return Self{
            .allocator = allocator,
            .log_level = log_level,
            .log_format = log_format,
            .time_measure = time_measure,
            .time_enabled = time_enabled,
            .time_pattern = time_pattern,
            .internalFailure = internalFailure,
            .log_writer = log_writer,
        };
    }

    pub fn Trace(self: Self) Entry {
        const op = Level.Trace;
        if (@intFromEnum(self.log_level) > @intFromEnum(op)) {
            return Entry.initEmpty();
        }
        return Entry.init(self, op);
    }
    pub fn Debug(self: Self) Entry {
        const op = Level.Debug;
        if (@intFromEnum(self.log_level) > @intFromEnum(op)) {
            return Entry.initEmpty();
        }
        return Entry.init(self, op);
    }
    pub fn Info(self: Self) Entry {
        const op = Level.Info;
        if (@intFromEnum(self.log_level) > @intFromEnum(op)) {
            return Entry.initEmpty();
        }
        return Entry.init(self, op);
    }
    pub fn Warn(self: Self) Entry {
        const op = Level.Warn;
        if (@intFromEnum(self.log_level) > @intFromEnum(op)) {
            return Entry.initEmpty();
        }
        return Entry.init(self, op);
    }
    pub fn Error(self: Self) Entry {
        const op = Level.Error;
        if (@intFromEnum(self.log_level) > @intFromEnum(op)) {
            return Entry.initEmpty();
        }
        return Entry.init(self, op);
    }
    pub fn Fatal(self: Self) Entry {
        const op = Level.Fatal;
        if (@intFromEnum(self.log_level) > @intFromEnum(op)) {
            return Entry.initEmpty();
        }
        return Entry.init(self, op);
    }
    pub fn Disabled(self: Self) Entry {
        _ = self;
        return Entry.initEmpty();
    }
};

pub const Entry = struct {
    const Self = @This();

    logger: ?Logger = null,
    opLevel: Level = .Disabled,

    elems: ?std.StringHashMap([]const u8) = null,

    fn initEmpty() Self {
        return Self{};
    }

    fn init(
        logger: Logger,
        opLevel: Level,
    ) Self {
        return Self{ .logger = logger, .opLevel = opLevel, .elems = std.StringHashMap([]const u8).init(logger.allocator) };
    }

    pub fn deinit(self: *Self) void {
        if (self.elems) |*hash| {
            var iter = hash.iterator();
            while (iter.next()) |entry| {
                self.logger.?.allocator.free(entry.value_ptr.*);
            }

            hash.deinit();
        }
    }

    pub fn Attr(self: *Self, key: []const u8, comptime V: type, value: V) *Self {
        if (self.elems) |*hash| {
            const logger = self.logger.?;
            var str = StringBuilder.init(logger.allocator);

            switch (@TypeOf(value)) {
                []const u8 => str.appendf("{s}", .{value}) catch |err| {
                    switch (logger.internalFailure) {
                        .panic => {
                            std.debug.panic("Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                        },
                        .print => {
                            std.debug.panic("Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                        },
                        else => {},
                    }
                },
                else => str.appendf("{}", .{value}) catch |err| {
                    switch (logger.internalFailure) {
                        .panic => {
                            std.debug.panic("Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                        },
                        .print => {
                            std.debug.panic("Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                        },
                        else => {},
                    }
                },
            }

            if (str.find(" ")) |_| {
                switch (logger.log_format) {
                    .simple => {
                        str.insertAt("\u{0022}", 0) catch |err| {
                            switch (logger.internalFailure) {
                                .panic => {
                                    std.debug.panic("Failed to insert and unicode code \u{0022}; {}", .{err});
                                },
                                .print => {
                                    std.debug.panic("Failed to insert and unicode code \u{0022}; {}", .{err});
                                },
                                else => {},
                            }
                        };
                        str.append("\u{0022}") catch |err| {
                            switch (logger.internalFailure) {
                                .panic => {
                                    std.debug.panic("Failed to insert and unicode code \u{0022}; {}", .{err});
                                },
                                .print => {
                                    std.debug.panic("Failed to insert and unicode code \u{0022}; {}", .{err});
                                },
                                else => {},
                            }
                        };
                    },
                    .json => {},
                }
            }

            str.shrink() catch |err| {
                switch (logger.internalFailure) {
                    .panic => {
                        std.debug.panic("Failed to shrink the result; {}", .{err});
                    },
                    .print => {
                        std.debug.panic("Failed to shrink the result; {}", .{err});
                    },
                    else => {},
                }
            };

            hash.put(key, str.bytes()) catch |err| {
                switch (logger.internalFailure) {
                    .panic => {
                        std.debug.panic("Failed to store the attribute; {}", .{err});
                    },
                    .print => {
                        std.debug.panic("Failed to store the attribute; {}", .{err});
                    },
                    else => {},
                }
            };
        }

        return self;
    }

    pub fn Error(self: *Self, value: anyerror) *Self {
        return self.Attr("error", []const u8, @errorName(value));
    }

    pub fn Msg(self: *Self, message: []const u8) !void {
        if (self.elems) |_| {
            switch (self.logger.?.log_format) {
                .simple => try self.simpleMsg(message),
                .json => try self.jsonMsg(message),
            }
        }
    }

    fn jsonMsg(self: *Self, message: []const u8) !void {
        if (self.elems) |*hash| {
            defer self.deinit();

            const logger = self.logger.?;

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

            var iter = hash.iterator();
            while (iter.next()) |entry| {
                try str.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ entry.key_ptr.*, entry.value_ptr.* });
            }

            try str.append("}\n");

            try str.shrink();

            const result = str.bytes();

            _ = try logger.log_writer.write(result);

            if (self.opLevel == .Fatal) {
                @panic("logger on fatal");
            }
        }
    }

    fn simpleMsg(self: *Self, message: []const u8) !void {
        if (self.elems) |*hash| {
            defer self.deinit();

            const logger = self.logger.?;

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

            var iter = hash.iterator();
            while (iter.next()) |entry| {
                try str.appendf("{s}={s} ", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            try str.removeEnd(1);
            try str.append("\n");

            try str.shrink();

            const result = str.bytes();

            _ = try logger.log_writer.write(result);

            if (self.opLevel == .Fatal) {
                @panic("logger on fatal");
            }
        }
    }

    pub fn Send(self: *Self) void {
        self.Msg("");
    }
};

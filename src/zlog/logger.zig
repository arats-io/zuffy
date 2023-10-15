const std = @import("std");

const StringBuilder = @import("../bytes/mod.zig").StringBuilder;

const Time = @import("../time/mod.zig").Time;
const Measure = @import("../time/mod.zig").Measure;

const Format = @import("common.zig").Format;
const Level = @import("common.zig").Level;

pub fn Logger(comptime format: Format, comptime timemeasure: Measure, comptime pattern: []const u8) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        writer: std.fs.File.Writer,
        level: Level,

        pub fn init(allocator: std.mem.Allocator, l: Level) Self {
            return initWithWriter(allocator, l, std.io.getStdOut().writer());
        }

        pub fn initWithWriter(allocator: std.mem.Allocator, l: Level, writer: std.fs.File.Writer) Self {
            return Self{ .allocator = allocator, .level = l, .writer = writer };
        }

        pub fn Trace(self: Self) Entry(format, timemeasure, pattern) {
            const op = Level.Trace;
            if (@intFromEnum(self.level) > @intFromEnum(op)) {
                return Entry(format, timemeasure, pattern).initEmpty();
            }
            return Entry(format, timemeasure, pattern).init(self, op);
        }
        pub fn Debug(self: Self) Entry(format, timemeasure, pattern) {
            const op = Level.Debug;
            if (@intFromEnum(self.level) > @intFromEnum(op)) {
                return Entry(format, timemeasure, pattern).initEmpty();
            }
            return Entry(format, timemeasure, pattern).init(self, op);
        }
        pub fn Info(self: Self) Entry(format, timemeasure, pattern) {
            const op = Level.Info;
            if (@intFromEnum(self.level) > @intFromEnum(op)) {
                return Entry(format, timemeasure, pattern).initEmpty();
            }
            return Entry(format, timemeasure, pattern).init(self, op);
        }
        pub fn Warn(self: Self) Entry(format, timemeasure, pattern) {
            const op = Level.Warn;
            if (@intFromEnum(self.level) > @intFromEnum(op)) {
                return Entry(format, timemeasure, pattern).initEmpty();
            }
            return Entry(format, timemeasure, pattern).init(self, op);
        }
        pub fn Error(self: Self) Entry(format, timemeasure, pattern) {
            const op = Level.Error;
            if (@intFromEnum(self.level) > @intFromEnum(op)) {
                return Entry(format, timemeasure, pattern).initEmpty();
            }
            return Entry(format, timemeasure, pattern).init(self, op);
        }
        pub fn Fatal(self: Self) Entry(format, timemeasure, pattern) {
            const op = Level.Fatal;
            if (@intFromEnum(self.level) > @intFromEnum(op)) {
                return Entry(format, timemeasure, pattern).initEmpty();
            }
            return Entry(format, timemeasure, pattern).init(self, op);
        }
        pub fn Disabled(self: Self) Entry(format, timemeasure, pattern) {
            _ = self;
            return Entry(format, timemeasure, pattern).initEmpty();
        }
    };
}

pub fn Entry(comptime format: Format, comptime timemeasure: Measure, comptime pattern: []const u8) type {
    return struct {
        const Self = @This();

        logger: ?Logger(format, timemeasure, pattern) = null,
        opLevel: Level = .Disabled,

        elems: ?std.StringHashMap([]const u8) = null,

        fn initEmpty() Self {
            return Self{};
        }

        fn init(
            logger: Logger(format, timemeasure, pattern),
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
                var str = StringBuilder.init(self.logger.?.allocator);

                switch (@TypeOf(value)) {
                    []const u8 => str.appendf("{s}", .{value}) catch {},
                    else => str.appendf("{}", .{value}) catch {},
                }

                if (str.find(" ")) |_| {
                    switch (format) {
                        inline .simple => {
                            str.insertAt("\u{0022}", 0) catch {};
                            str.append("\u{0022}") catch {};
                        },
                        inline .json => {},
                    }
                }

                str.shrink() catch {};

                hash.put(key, str.bytes()) catch {};
            }

            return self;
        }

        pub fn Error(self: *Self, value: anyerror) *Self {
            return self.Attr("error", []const u8, @errorName(value));
        }

        pub fn Msg(self: *Self, message: []const u8) void {
            if (self.elems) |_| {
                switch (format) {
                    inline .simple => self.simpleMsg(message),
                    inline .json => self.jsonMsg(message),
                }
            }
        }

        inline fn jsonMsg(self: *Self, message: []const u8) void {
            if (self.elems) |*hash| {
                defer self.deinit();

                var str = StringBuilder.init(self.logger.?.allocator);
                defer str.deinit();

                str.append("{") catch {};

                const t = Time(timemeasure).now();

                var buffer: [512]u8 = undefined;
                const len = t.format(pattern, buffer[0..]) catch pattern.len;
                str.appendf("\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ "timestamp", buffer[0..len] }) catch {};
                str.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ "level", self.opLevel.String() }) catch {};
                if (message.len > 0) {
                    str.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ "message", message }) catch {};
                }

                var iter = hash.iterator();
                while (iter.next()) |entry| {
                    str.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ entry.key_ptr.*, entry.value_ptr.* }) catch {};
                }

                str.append("}\n") catch {};

                str.shrink() catch {};

                const result = str.bytes();

                _ = self.logger.?.writer.write(result) catch {};

                if (self.opLevel == .Fatal) {
                    @panic("logger on fatal");
                }
            }
        }

        inline fn simpleMsg(self: *Self, message: []const u8) void {
            if (self.elems) |*hash| {
                defer self.deinit();

                var str = StringBuilder.init(self.logger.?.allocator);
                defer str.deinit();

                const t = Time(timemeasure).now();

                var buffer: [512]u8 = undefined;
                const len = t.format(pattern, buffer[0..]) catch pattern.len;
                str.appendf("{s} {s}", .{ buffer[0..len], self.opLevel.String().ptr[0..4] }) catch {};
                if (message.len > 0) {
                    str.appendf(" {s}", .{message}) catch {};
                }
                str.append(" ") catch {};

                var iter = hash.iterator();
                while (iter.next()) |entry| {
                    str.appendf("{s}={s} ", .{ entry.key_ptr.*, entry.value_ptr.* }) catch {};
                }
                str.removeEnd(1) catch {};

                str.append("\n") catch {};

                str.shrink() catch {};

                const result = str.bytes();

                _ = self.logger.?.writer.write(result) catch {};

                if (self.opLevel == .Fatal) {
                    @panic("logger on fatal");
                }
            }
        }

        pub fn Send(self: *Self) void {
            self.Msg("");
        }
    };
}

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const StringHashMap = std.StringHashMap;

const StringBuilder = @import("bytes/types.zig").StringBuilder;
const Time = @import("time.zig").Time;
const Measure = @import("time.zig").Measure;

pub const Format = enum(u4) {
    simple = 0,
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
            .Trace => "TRACE",
            .Debug => "DEBUG",
            .Info => "INFO",
            .Warn => "WARN",
            .Error => "ERROR",
            .Fatal => "FATAL",
            .Disabled => "DISABLED",
        };
    }
    pub fn ParseString(val: []const u8) !Level {
        var buffer: [8]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        var sb = StringBuilder.init(fba.allocator());
        defer sb.deinit();

        try sb.append(val);
        sb.toUppercase();

        const lVal = sb.bytes();
        if (std.mem.eql(u8, "TRACE", lVal)) return .Trace;
        if (std.mem.eql(u8, "DEBUG", lVal)) return .Debug;
        if (std.mem.eql(u8, "INFO", lVal)) return .Info;
        if (std.mem.eql(u8, "WARN", lVal)) return .Warn;
        if (std.mem.eql(u8, "ERROR", lVal)) return .Error;
        if (std.mem.eql(u8, "FATAL", lVal)) return .Fatal;
        if (std.mem.eql(u8, "DISABLED", lVal)) return .Disabled;
        return .Disabled;
    }
};

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

        elems: ?StringHashMap([]const u8) = null,

        fn initEmpty() Self {
            return Self{};
        }

        fn init(
            logger: Logger(format, timemeasure, pattern),
            opLevel: Level,
        ) Self {
            return Self{ .logger = logger, .opLevel = opLevel, .elems = StringHashMap([]const u8).init(logger.allocator) };
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

// const std = @import("std");
// const debug = std.debug;
// const StringBuilder = @import("xstd/bytes/types.zig").StringBuilder;

// const plog = @import("xstd/logger.zig");
// const Logger = plog.Logger(.simple, .nanos, "YYYY MMM Do dddd HH:mm:ss.SSS - Qo");
// const Level = plog.Level;
// const Format = plog.Format;

// const Time = @import("xstd/time.zig").Time;

// const Error = error{OutOfMemoryClient};

// const Element = struct {
//     int: i32,
//     string: []const u8,
//     elem: ?*const Element = null,
// };

// pub fn main() !void {
//     std.debug.print("Starting application.\n", .{});

//     var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     defer arena.deinit();

//     const level = try Level.ParseString("TRACE");
//     const logger = Logger.init(arena.allocator(), level);
//     @constCast(&logger.Trace())
//         .Attr("database", []const u8, "myapp huraaaa !")
//         .Attr("counter", i32, 34)
//         .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
//         .Msg("Initialization...");
//     @constCast(&logger.Debug())
//         .Attr("database", []const u8, "myapp huraaaa !")
//         .Attr("counter", i32, 34)
//         .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
//         .Msg("Initialization...");
//     @constCast(&logger.Info())
//         .Attr("database", []const u8, "myapp huraaaa !")
//         .Attr("counter", i32, 34)
//         .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
//         .Msg("Initialization...");
//     @constCast(&logger.Warn())
//         .Attr("database", []const u8, "myapp huraaaa !")
//         .Attr("counter", i32, 34)
//         .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
//         .Msg("Initialization...");
//     @constCast(&logger.Error())
//         .Attr("database", []const u8, "myapp huraaaa !")
//         .Error(Error.OutOfMemoryClient)
//         .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
//         .Msg("Initialization...");
//     @constCast(&logger.Disabled())
//         .Attr("database", []const u8, "myapp huraaaa !")
//         .Attr("counter", i32, 34)
//         .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
//         .Msg("Initialization...");
// }

const std = @import("std");
const xstd = @import("xstd");

const StringBuilder = xstd.bytes.StringBuilder;
const Buffer = xstd.bytes.Buffer;

const Logger = xstd.zlog.Logger;
const Level = xstd.zlog.Level;
const Format = xstd.zlog.Format;

const Time = xstd.time.Time;

const Error = error{OutOfMemoryClient};

const Element = struct {
    int: i32,
    string: []const u8,
    elem: ?*const Element = null,
};

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const logger = Logger.init(arena.allocator(), .{
        .caller_enabled = true,
        .caller_field_name = "caller",
        .time_enabled = true,
        .time_measure = .micros,
        .time_formating = .pattern,
        .level = Level.ParseString("trace"),
        .format = Format.json,
        .time_pattern = "YYYY MMM Do ddd HH:mm:ss.SSS - Qo",
    });

    while (true) {
        try generateLogsTrace(logger);
        try generateLogsDebug(logger);
        try generateLogsInfo(logger);
        try generateLogsWarn(logger);
        try generateLogsError(logger);
        try generateLogsDisabled(logger);
    }
}

pub fn generateLogsTrace(logger: anytype) !void {
    try @constCast(&logger.Trace())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Send();
}

pub fn generateLogsDebug(logger: anytype) !void {
    try @constCast(&logger.Debug())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Send();
}
pub fn generateLogsInfo(logger: anytype) !void {
    try @constCast(&logger.Info())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Send();
}
pub fn generateLogsWarn(logger: anytype) !void {
    try @constCast(&logger.Warn())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Send();
}
pub fn generateLogsError(logger: anytype) !void {
    try @constCast(&logger.Error())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Send();
}
pub fn generateLogsDisabled(logger: anytype) !void {
    try @constCast(&logger.Disabled())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Send();
}

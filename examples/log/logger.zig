const std = @import("std");
const xstd = @import("xstd");

const StringBuilder = xstd.bytes.StringBuilder;
const Buffer = xstd.bytes.Buffer;

const LoggerBuilder = xstd.zlog.LoggerBuilder;
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

    const logger = LoggerBuilder.init(arena.allocator())
        .GlobalLevel(Level.ParseString("TRACE"))
        .OutputFormat(Format.json)
        .Timestamp()
        .TimePattern("YYYY MMM Do ddd HH:mm:ss.SSS - Qo")
        .build();

    try generateLogs(logger);
}

pub fn generateLogs(logger: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var buffer = Buffer.initWithFactor(arena.allocator(), 10);
    defer buffer.deinit();

    var buffWriter = buffer.writer();

    try @constCast(&logger.Trace())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .MsgWriter("Initialization...", buffWriter);
    try @constCast(&logger.Debug())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .MsgWriter("Initialization...", buffWriter);
    try @constCast(&logger.Info())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .MsgWriter("Initialization...", buffWriter);
    try @constCast(&logger.Warn())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .MsgWriter("Initialization...", buffWriter);
    try @constCast(&logger.Error())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Error(Error.OutOfMemoryClient)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .MsgWriter("Initialization...", buffWriter);
    try @constCast(&logger.Disabled())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .MsgWriter("Initialization...", buffWriter);

    std.debug.print("{s}", .{buffer.bytes()});
}

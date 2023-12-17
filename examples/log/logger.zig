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
        .time_pattern = "YYYY MMM Do ddd HH:mm:ss.SSS UTCZZZ - Qo",
    });

    const max = std.math.maxInt(u16);
    var m: i128 = 0;
    const start = std.time.microTimestamp();
    for (0..max) |_| {
        var startTime = std.time.microTimestamp();
        try @constCast(&logger.Trace())
            .Message("Initialization...")
            .Source(@src())
            .Attr("attribute-null", null)
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Send();
        m += (std.time.microTimestamp() - startTime);

        startTime = std.time.microTimestamp();
        try @constCast(&logger.Debug())
            .Message("Initialization...")
            .Source(@src())
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Send();
        m += (std.time.microTimestamp() - startTime);

        startTime = std.time.microTimestamp();
        try @constCast(&logger.Info())
            .Message("Initialization...")
            .Source(@src())
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Send();
        m += (std.time.microTimestamp() - startTime);

        startTime = std.time.microTimestamp();
        try @constCast(&logger.Warn())
            .Message("Initialization...")
            .Source(@src())
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Send();
        m += (std.time.microTimestamp() - startTime);

        startTime = std.time.microTimestamp();
        try @constCast(&logger.Error())
            .Message("Initialization...")
            .Source(@src())
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Error(Error.OutOfMemoryClient)
            .Send();
        m += (std.time.microTimestamp() - startTime);
    }

    std.debug.print("\n----------------------------------------------------------------------------", .{});
    const total = max * 5;
    std.debug.print("\n\nProcessed {} records in {} micro; Average time spent on log report is {} micro.\n\n", .{ total, (std.time.microTimestamp() - start), @divTrunc(m, total) });
}

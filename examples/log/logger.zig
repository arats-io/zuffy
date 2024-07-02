const std = @import("std");
const xstd = @import("xstd");

const StringBuilder = xstd.bytes.StringBuilder;
const Utf8Buffer = xstd.bytes.Utf8Buffer;
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

    const logger = try Logger.init(arena.allocator(), .{
        .level = Level.ParseString("trace"),
        .format = Format.json,
        .caller_enabled = true,
        .caller_field_name = "caller",
        .time_enabled = true,
        .time_measure = .nanos,
        .time_formating = .pattern,
        .time_pattern = "YYYY MMM Do ddd HH:mm:ss.SSS UTCZZZ - Qo",
        .internal_failure = .panic,
    });

    const max = std.math.maxInt(u18);
    var m: i128 = 0;
    const start = std.time.nanoTimestamp();
    for (0..max) |_| {
        var startTime = std.time.nanoTimestamp();
        var trace = logger.Trace();
        try trace
            .Message("Initialization...")
            .Source(@src())
            .Attr("attribute-null", null)
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Send();
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try @as(*Logger.Entry, @constCast(&logger.Debug()))
            .Message("Initialization...")
            .Source(@src())
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Send();
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try @constCast(&logger.Info())
            .Message("Initialization...")
            .Source(@src())
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Send();
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try @constCast(&logger.Warn())
            .Message("Initialization...")
            .Source(@src())
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Send();
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try @constCast(&logger.Error())
            .Message("Initialization...")
            .Source(@src())
            .Attr("database", "mydb")
            .Attr("counter", 34)
            .Attr("element1", Element{ .int = 32, .string = "Element1" })
            .Error(Error.OutOfMemoryClient)
            .Send();
        m += (std.time.nanoTimestamp() - startTime);
    }

    std.debug.print("\n----------------------------------------------------------------------------", .{});
    const total = max * 5;
    std.debug.print("\n\nProcessed {} records in {} micro; Average time spent on log report is {} micro.\n\n", .{ total, (std.time.nanoTimestamp() - start), @divFloor(m, total) });
}

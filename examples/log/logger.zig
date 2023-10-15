const std = @import("std");
const xstd = @import("xstd");

const StringBuilder = xstd.bytes.StringBuilder;

const Logger = xstd.log.Logger(.simple, .nanos, "YYYY MMM Do dddd HH:mm:ss.SSS - Qo");
const Level = xstd.log.Level;
const Format = xstd.log.Format;

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

    const level = try Level.ParseString("TRACE");
    const logger = Logger.init(arena.allocator(), level);
    @constCast(&logger.Trace())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Msg("Initialization...");
    @constCast(&logger.Debug())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Msg("Initialization...");
    @constCast(&logger.Info())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Msg("Initialization...");
    @constCast(&logger.Warn())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Msg("Initialization...");
    @constCast(&logger.Error())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Error(Error.OutOfMemoryClient)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Msg("Initialization...");
    @constCast(&logger.Disabled())
        .Attr("database", []const u8, "myapp huraaaa !")
        .Attr("counter", i32, 34)
        .Attr("element1", Element, Element{ .int = 32, .string = "Element1" })
        .Msg("Initialization...");
}

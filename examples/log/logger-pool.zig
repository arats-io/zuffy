const std = @import("std");
const xstd = @import("xstd");
const build_options = @import("build_options");

const Utf8Buffer = xstd.bytes.Utf8Buffer;
const Buffer = xstd.bytes.Buffer;
const GenericPool = xstd.pool.Generic;

const zlog = xstd.zlog;

const Error = error{OutOfMemoryClient};

const Element = struct {
    int: i32,
    string: []const u8,
    elem: ?*const Element = null,
};

const NewUtf8Buffer = struct {
    fn f(allocator: std.mem.Allocator) Utf8Buffer {
        return Utf8Buffer.init(allocator);
    }
}.f;

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const pool = GenericPool(Utf8Buffer).init(arena.allocator(), NewUtf8Buffer);
    defer pool.deinit();
    errdefer pool.deinit();

    const logger = zlog.initWithPool(arena.allocator(), &pool, .{
        .level = zlog.Level.ParseString("trace"),
        .format = zlog.Format.json,
        .caller_enabled = true,
        .caller_field_name = "caller",
        .time_enabled = true,
        .time_measure = .nanos,
        .time_formating = .pattern,
        .time_pattern = "YYYY MMM Do ddd HH:mm:ss.SSS UTCZZZ - Qo",
        .escape_enabled = false,
        .stacktrace_ebabled = true,
    });
    defer logger.deinit();

    try logger.With("version", build_options.semver);

    const max = std.math.maxInt(u18);
    var m: i128 = 0;
    const start = std.time.nanoTimestamp();

    const value_database = "my\"db";
    for (0..max) |idx| {
        var startTime = std.time.nanoTimestamp();

        try logger.Trace(
            "Initial\"ization...",
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field([4]i32, "array", [_]i32{ 1, 2, 3, 4 }),
                zlog.Field([2]Element, "array_elements", [_]Element{
                    Element{ .int = 32, .string = "Eleme\"nt1" },
                    Element{ .int = 32, .string = "Eleme\"nt2" },
                }),
                zlog.Field([2][]const u8, "array_strings", [_][]const u8{
                    "eleme\"nt 1",
                    "eleme\"nt 2",
                }),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Eleme\"nt1" }),
            },
        );

        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try logger.Debug(
            "Initialization...",
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
            },
        );
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try logger.Info(
            "Initialization...",
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
            },
        );
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try logger.Warn(
            "Initialization...",
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
            },
        );
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try logger.Error(
            "Initialization...",
            Error.OutOfMemoryClient,
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
            },
        );
        m += (std.time.nanoTimestamp() - startTime);
    }

    std.debug.print("\n----------------------------------------------------------------------------", .{});
    const total = max * 5;
    std.debug.print("\n\nProcessed {} records in {} micro; Average time spent on log report is {} micro.\n\n", .{ total, (std.time.nanoTimestamp() - start), @divFloor(m, total) });
}

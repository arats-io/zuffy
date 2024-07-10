# Zig logger

Is providing a more flexible way to deal with the logs, with a following average performance:

- in debug mode ~60 μs when using time pattern (as per tests was used: YYYY MMM Do ddd HH:mm:ss.SSS - Qo) and ~12 μs using timestamp as integer per entry to be produced on the console
- in release safe mode ~9 μs for both type of time formats per entry to be produced on the console
- in release fast mode ~8 μs for both type of time formats per entry to be produced on the console

# Configuration

Configuration for the logger with default values

```zig
.{
    .level = Level.Info, // Log level, possible values (Trace | Debug | Info | Warn | Error | Fatal | Disabled)
    .level_field_name = "level", // field name for the log level
    .format = Format.json, // format for writing logs, possible values (json | text)

    // time related configuration options
    .time_enabled = false, // flag enabling/disabling the time  for each log record
    .time_field_name = "time", // field name for the time
    .time_measure = Measure.seconds, // time measumerent, possible values (seconds | millis | micros, nanos)
    .time_formating = TimeFormating.timestamp, // time formating, possible values (timestamp | pattern)
    .time_pattern = "DD/MM/YYYY'T'HH:mm:ss", // petttern of time representation, applicable when .time_formating is sen on .pattern

    .message_field_name: = "msg", // field name for the message
    .error_field_name = "error", // field name for the error

    .stacktrace_ebabled = false, // flag enabling/disabling the error tracing reporting in the log
    .stacktrace_field_name = "stacktrace", // field name for the error stacktrace

    .internal_failure = InternalFailure.nothing, // indicator what to do in case is there is a error occuring inside of logger, possible values as doing (nothing | panic | print)

    // caller related configuration options
    .caller_enabled = false,  // flag enabling/disabling the caller reporting in the log
    .caller_field_name = "caller", // field name for the caller source
    .caller_marshal_fn = default_caller_marshal_fn, // handler processing the source object data

    .writer = std.io.getStdOut(), // handler writing the data

    // escaping options
    .escape_enabled = false,
    .src_escape_characters = "\"",
    .dst_escape_characters = "\\\"",
}

```

## Default configuration:

```zig
const zlog = xstd.zlog;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();

const logger = zlog.init(arena.allocator(), .{});
```

## Custom options:

// Example not using any pool for internal created buffers

```zig
const std = @import("std");
const xstd = @import("xstd");

const zlog = xstd.zlog;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();

const logger = zlog.init(arena.allocator(), .{
    .level = zlog.Level.ParseString("trace"),
    .format = zlog.Format.json,
    .caller_enabled = true,
    .caller_field_name = "caller",
    .time_enabled = true,
    .time_measure = .nanos,
    .time_formating = .pattern,
    .time_pattern = "YYYY MMM Do ddd HH:mm:ss.SSS UTCZZZ - Qo",
});
defer logger.deinit();

try logger.With("major_version", 1);
try logger.With("minor_version", 2);
```

// Example not using pool for internal buffers

```zig
const std = @import("std");
const xstd = @import("xstd");

const Utf8Buffer = xstd.bytes.Utf8Buffer;
const Buffer = xstd.bytes.Buffer;
const GenericPool = xstd.pool.Generic;

const zlog = xstd.zlog;

const NewUtf8Buffer = struct {
    fn f(allocator: std.mem.Allocator) Utf8Buffer {
        return Utf8Buffer.init(allocator);
    }
}.f;

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
});
defer logger.deinit();

try logger.With(.{
    zlog.Field(u8, "major_version", 1),
    zlog.Field(u8, "minor_version", 2),
});
```

```zig
try logger.Trace(
    "Initialization...",
    .{
        zlog.Source(@src()),
        zlog.Field([]const u8, "database", value_database),
        zlog.Field(usize, "counter", idx),
        zlog.Field(?[]const u8, "attribute-null", null),
        zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
    },
);
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
```

Output:

```json
{"time": "2024 Jul 4th Thu 17:37:05.80451000 UTC+01:00 - 3rd", "level": "trace", "msg": "Initialization...", "major_version":1, "minor_version":2, "caller": "examples/log/logger-pool.zig:62", "database": "mydb", "counter":262142, "attribute-null":null, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2024 Jul 4th Thu 17:37:05.80507000 UTC+01:00 - 3rd", "level": "debug", "msg": "Initialization...", "major_version":1, "minor_version":2, "caller": "examples/log/logger-pool.zig:76", "database": "mydb", "counter":262142, "attribute-null":null, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2024 Jul 4th Thu 17:37:05.80564000 UTC+01:00 - 3rd", "level": "info", "msg": "Initialization...", "major_version":1, "minor_version":2, "caller": "examples/log/logger-pool.zig:89", "database": "mydb", "counter":262142, "attribute-null":null, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2024 Jul 4th Thu 17:37:05.80621000 UTC+01:00 - 3rd", "level": "warn", "msg": "Initialization...", "major_version":1, "minor_version":2, "caller": "examples/log/logger-pool.zig:102", "database": "mydb", "counter":262142, "attribute-null":null, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2024 Jul 4th Thu 17:37:05.80679000 UTC+01:00 - 3rd", "level": "error", "msg": "Initialization...", "major_version":1, "minor_version":2, "error": "OutOfMemoryClient", "caller": "examples/log/logger-pool.zig:116", "database": "mydb", "counter":262142, "attribute-null":null, "element1":{"int":32,"string":"Element1","elem":null}}
```

### Scoped logger

```zig
const cache_logger = try logger.Scope(.cache);
defer cache_logger.deinit();

try cache_logger.Error(
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
```

Scoped logger Output:

```json
{"time": "2024 Jul 10th Wed 20:27:52.963464000 UTC+02:00 - 3rd", "level": "error", "scope": "cache", "msg": "Initialization...", "version":{"major":0,"minor":1,"patch":4,"pre":null,"build":null}, "hu":1, "error": "OutOfMemoryClient", "caller": "examples/log/logger-pool.zig:144", "database": "my\"db", "counter":1502, "attribute-null":null, "element1":{"int":32,"string":"Element1","elem":null}}.
```

# Zig logger

Is providing a more flexible way to deal with the logs, with a following average performance:

- in debug mode ~80 μs when using time pattern (as per tests was used: YYYY MMM Do ddd HH:mm:ss.SSS - Qo) and ~19 μs using timestamp as integer per entry to be produced on the console
- in release safe mode ~9 μs for both type of time formats per entry to be produced on the console
- in release fast mode ~8 μs for both type of time formats per entry to be produced on the console

# Configuration

Configuration options for the logger with default values

```zig
.{
    .level = Level.Info, // Log level, possible values (Trace | Debug | Info | Warn | Error | Fatal | Disabled)
    .level_field_name = "level", // field name for the log level
    .format = Format.json, // format for writing logs, possible values (json | simple)

    // time related configuration options
    .time_enabled = false, // flag enabling/disabling the time  for each log record
    .time_field_name = "time", // field name for the time
    .time_measure = Measure.seconds, // time measumerent, possible values (seconds | millis | micros, nanos)
    .time_formating = TimeFormating.timestamp, // time formating, possible values (timestamp | pattern)
    .time_pattern = "DD/MM/YYYY'T'HH:mm:ss", // petttern of time representation, applicable when .time_formating is sen on .pattern

    .message_field_name: = "message", // field name for the message
    .error_field_name = "error", // field name for the error

    .internal_failure = InternalFailure.nothing, // indicator what to do in case is there is a error occuring inside of logger, possible values as doing (nothing | panic | print)

    // caller related configuration options
    .caller_enabled = false,  // flag enabling/disabling the caller reporting in the log
    .caller_field_name = "caller", // field name for the caller source
    .caller_marshal_fn = default_caller_marshal_fn, // handler processing the source object data

    // struct marchalling to string options
    .struct_union: = StructUnionOptions{
        // flag enabling/disabling the escapping for marchalled structs
        // searching for \" and replacing with \\\" as per default values
        .escape_enabled = false,
        .src_escape_characters = "\"",
        .dst_escape_characters = "\\\"",
    },
}

```

## Default configuration:

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();

const logger = Logger.init(arena.allocator(), .{});
```

## Custom options:

```zig
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
```

## Examples:

```zig
    try @constCast(&logger.Trace())
        .Message("Initialization...")
        .Source(@src())
        .Attr("attribute-null", null)
        .Attr("database", "mydb")
        .Attr("counter", 34)
        .Attr("element1", Element{ .int = 32, .string = "Element1" })
        .Send();

    try @constCast(&logger.Debug())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", "mydb")
        .Attr("counter", 34)
        .Attr("element1", Element{ .int = 32, .string = "Element1" })
        .Send();

    try @constCast(&logger.Info())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", "mydb")
        .Attr("counter", 34)
        .Attr("element1", Element{ .int = 32, .string = "Element1" })
        .Send();

    try @constCast(&logger.Warn())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", "mydb")
        .Attr("counter", 34)
        .Attr("element1", Element{ .int = 32, .string = "Element1" })
        .Send();

    try @constCast(&logger.Error())
        .Message("Initialization...")
        .Source(@src())
        .Attr("database", "mydb")
        .Attr("counter", 34)
        .Attr("element1", Element{ .int = 32, .string = "Element1" })
        .Error(Error.OutOfMemoryClient)
        .Send();
```

Output:

```json
{"time": "2023 Nov 5th Sun 20:29:40.311932 - 4th", "level": "trace", "message": "Initialization...", "caller": "examples/log/logger.zig:45", "attribute-null":null, "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2023 Nov 5th Sun 20:29:40.312001 - 4th", "level": "debug", "message": "Initialization...", "caller": "examples/log/logger.zig:56", "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2023 Nov 5th Sun 20:29:40.312070 - 4th", "level": "info", "message": "Initialization...", "caller": "examples/log/logger.zig:66", "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2023 Nov 5th Sun 20:29:40.312136 - 4th", "level": "warn", "message": "Initialization...", "caller": "examples/log/logger.zig:76", "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2023 Nov 5th Sun 20:29:40.312203 - 4th", "level": "error", "message": "Initialization...", "caller": "examples/log/logger.zig:86", "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}, "error": "OutOfMemoryClient"}
```

Additional examples:

- Make the trace as a separate variable

  ```zig
      var trace = logger.Trace();
      try trace
          .Message("Initialization...")
          .Source(@src())
          .Attr("attribute-null", null)
          .Attr("database", "mydb")
          .Attr("counter", 34)
          .Attr("element1", Element{ .int = 32, .string = "Element1" })
          .Send();
  ```

- Make the trace as a separate variable

  ```zig
      try @as(*Logger.Entry, @constCast(&logger.Debug()))
          .Message("Initialization...")
          .Source(@src())
          .Attr("attribute-null", null)
          .Attr("database", "mydb")
          .Attr("counter", 34)
          .Attr("element1", Element{ .int = 32, .string = "Element1" })
          .Send();
  ```

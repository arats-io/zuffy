# Zig logger

Is providing a more flexible way to deal with the logs.

# Usage

Usage based on default options:

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();

const logger = Logger.init(arena.allocator(), .{});
```

Usage based on custom options:

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

Usage Examples:

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

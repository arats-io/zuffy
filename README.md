# Extended Zig standard library

Current Zig library do offer some extra functionality missing from official Zig STD.

Work in progress...; If somewthing is not working, feel free to contribute or open a issue.

Require zig version: **0.13.0**

## List of modules

### Bytes

- [x] Buffer
- [x] Utf8Buffer/StringBuilder

---

### Time and Time Zoneinfo

- [x] Time as wrapper which is including the timezone
- [x] Timezone

#### Usage

The Time struct do include machine timezone adjustments as an offset.

Environment variable `TZ` can be used to calculate a time for a different timezone.

```
export TZ='Europe/Tiraspol';

2023 Nov 5th Sun 22:33:05.477603
```

In case if machine is not having a way to fetch desired zoninfo, the library is considering embeded zip(and gziped) archive with all zone information.

```
export TZ='Europe/Tiraspol.zip';

2023 Nov 5th Sun 22:33:05.477603
```

IMPORTANT: As the zip is embeded do affect the binary size. Zip(and gziped) is having 144KB.

- [x] \*nix systems
- [ ] windows systems

---

### Archives

- [x] Zip archive extraction
- [ ] Zip archive creation
- [ ] More format to be supported ...

---

### ZLog a Zig logger

- [x] ZLog - Zig logger

#### Usage

Include the xstd into the `build.zig.zon` file.

```
.dependencies = .{
    .xstd = .{
        .url = "https://github.com/arats-io/zig-xstd/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "12201fd38f467e6c64ee7bca53da95863b6c05da77fc51daf0ab22079ede57cbd4e2",
    },
},
```

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

Example:

```zig
fn testing(logger: anytype) void {
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
}
```

Output:

```json
{"time": "2023 Nov 5th Sun 20:29:40.311932 - 4th", "level": "trace", "message": "Initialization...", "caller": "examples/log/logger.zig:45", "attribute-null":null, "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2023 Nov 5th Sun 20:29:40.312001 - 4th", "level": "debug", "message": "Initialization...", "caller": "examples/log/logger.zig:56", "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2023 Nov 5th Sun 20:29:40.312070 - 4th", "level": "info", "message": "Initialization...", "caller": "examples/log/logger.zig:66", "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2023 Nov 5th Sun 20:29:40.312136 - 4th", "level": "warn", "message": "Initialization...", "caller": "examples/log/logger.zig:76", "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}}
{"time": "2023 Nov 5th Sun 20:29:40.312203 - 4th", "level": "error", "message": "Initialization...", "caller": "examples/log/logger.zig:86", "database": "mydb", "counter":34, "element1":{"int":32,"string":"Element1","elem":null}, "error": "OutOfMemoryClient"}
```

# Extended Zig standard library

Current Zig library do offer some extra functionality missing from official Zig STD.

Work in progress...; If somewthing is not working, feel free to contribute or open a issue.

Require zig version: **0.13.0**

## Usage

Include the xstd into the `build.zig.zon` file.

```
.dependencies = .{
    .xstd = .{
        .url = "https://github.com/arats-io/zig-xstd/archive/refs/tags/v0.1.6.tar.gz",
        .hash = "12201fd38f467e6c64ee7bca53da95863b6c05da77fc51daf0ab22079ede57cbd4e2",
    },
},
```

## List of modules

### Pools

- [x] Generic Pool
      Using allocator and the locker
- [x] Generic Pool Lock & Memory Free
      Based on on implementation of @kprotty's from https://github.com/kprotty/zap
- [x] Thread Pool
      Copied from @kprotty's from https://github.com/kprotty/zap

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

- [x] Zip
  - [x] archive extraction
  - [ ] archive creation
- [ ] More archive formats to be added ...

---

### [ZLog a Zig logger](./src/zlog/README.md)

# Zig UFFY library

Current Zig UFFY library do offer bunch of extra functionality!

Work in progress...; If somewthing is not working, feel free to contribute or open a issue.

Require zig version: **0.14.0-dev.850+ddcb7b1c1**

## Usage

Include the zuffy into the `build.zig.zon` file.

```
zig fetch --save https://github.com/arats-io/zuffy/archive/refs/tags/v<version>.tar.gz

.dependencies = .{
    .zuffy = .{
        .url = "https://github.com/arats-io/zuffy/archive/refs/tags/v0.1.14.tar.gz",
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
- [x] Utf8Buffer (StringBuilder)

---

### Time and Time Zoneinfo

- [x] Time
- [x] Time Zoneinfo

#### Usage

Environment variable `TZ` can be used to calculate a time for a different timezone.

```
export TZ='Europe/Tiraspol';

2023 Nov 5th Sun 22:33:05.477603  UTC+03:00
```

In case if machine is not having a way to fetch desired zoninfo, the library is considering embeded zip(and gziped) archive with all zone information.

```
export TZ='Europe/Tiraspol.zip';

2023 Nov 5th Sun 22:33:05.477603 UTC+03:00
```

**NOTE**

[time zones info](https://www.iana.org/time-zones) data are embeded (zip and gziped, having 92kb) into the code.

- [x] \*nix systems
- [ ] windows systems

---

### Archives

- [x] Zip
  - [x] archive extraction
  - [ ] archive creation
- [ ] More archive formats to be added ...

---

### Lists

- [x] CircularList (FIFO & LIFO)
- [x] SkipList

---

### Eazy Logger

[zlog](./src/zlog.md)

# Contributing

Contributions of all kinds is welcome!

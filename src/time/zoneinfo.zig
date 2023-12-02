const std = @import("std");
const builtin = @import("builtin");

const Buffer = @import("../bytes/mod.zig").Buffer;

pub const Error = error{
    OutOfMemory,
    BadData,
    UnknownTimeZone,
    NotImplemented,
    EndOfStream,
    StreamTooLong,
    InvalidRange,
    NoSpaceLeft,
};

pub const Local = struct {
    const Self = @This();

    var instance: ?Location = null;

    mu: std.Thread.Mutex = .{},

    pub fn Get(self: Self) !Location {
        if (instance) |loc| {
            return loc;
        }

        if (!builtin.single_threaded) {
            const m = @constCast(&self.mu);

            m.lock();
            defer m.unlock();
        }

        if (instance) |loc| {
            return loc;
        } else {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer {
                arena.deinit();
            }

            const allocator = arena.allocator();

            const isUnix = builtin.os.tag.isDarwin() or builtin.os.tag.isBSD() or builtin.os.tag == .linux;
            if (isUnix) {
                const tz_val: ?[]const u8 = std.process.getEnvVarOwned(allocator, "TZ") catch null;
                instance = try unix(allocator, tz_val);
            } else {
                return Error.NotImplemented;
            }
        }

        return instance.?;
    }

    pub fn timezoneLocation(timezone: []const u8) !Location {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer {
            arena.deinit();
        }

        const allocator = arena.allocator();

        const isUnix = builtin.os.tag.isDarwin() or builtin.os.tag.isBSD() or builtin.os.tag == .linux;
        if (isUnix) {
            return try unix(allocator, timezone);
        } else {
            return Error.NotImplemented;
        }
    }
}{};

pub const LookupResult = struct {
    name: []const u8,
    offset: i32,
    start: i64,
    end: i64,
    isDST: bool,
};

pub const Location = struct {
    const Self = @This();

    name: []const u8,
    zone: []zone,
    tx: []zoneTrans,

    // The tzdata information can be followed by a string that describes
    // how to handle DST transitions not recorded in zoneTrans.
    // The format is the TZ environment variable without a colon; see
    // https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html.
    // Example string, for America/Los_Angeles: PST8PDT,M3.2.0,M11.1.0
    extend: []const u8,

    // Most lookups will be for the current time.
    // To avoid the binary search through tx, keep a
    // static one-element cache that gives the correct
    // zone for the time when the Location was created.
    // if cacheStart <= t < cacheEnd,
    // lookup can return cacheZone.
    // The units for cacheStart and cacheEnd are seconds
    // since January 1, 1970 UTC, to match the argument
    // to lookup.
    cacheStart: i64,
    cacheEnd: i64,
    cacheZone: zone,

    pub fn Name(self: Self) []const u8 {
        return self.name;
    }
    pub fn Extend(self: Self) []const u8 {
        return self.extend;
    }

    pub fn Lookup(self: Self) LookupResult {
        const sec = std.time.timestamp();

        if (self.zone.len == 0) {
            return LookupResult{
                .name = self.name[0..],
                .offset = 0,
                .start = std.math.minInt(i64),
                .end = std.math.maxInt(i64),
                .isDST = false,
            };
        }

        if (self.cacheStart <= sec and sec < self.cacheEnd) {
            return LookupResult{
                .name = self.cacheZone.name[0..],
                .offset = self.cacheZone.offset,
                .start = self.cacheStart,
                .end = self.cacheEnd,
                .isDST = self.cacheZone.isDST,
            };
        }

        if (self.tx.len == 0 or sec < self.tx[0].when) {
            const zoneLocal = self.zone[self.lookupFirstZone()];
            return LookupResult{
                .name = zoneLocal.name[0..],
                .offset = zoneLocal.offset,
                .start = std.math.minInt(i64),
                .end = if (self.tx.len > 0) self.tx[0].when else std.math.maxInt(i64),
                .isDST = zoneLocal.isDST,
            };
        }

        // Binary search for entry with largest time <= sec.
        // Not using sort.Search to avoid dependencies.
        const tx = self.tx;
        var end: i64 = std.math.maxInt(i64);
        var lo: usize = 0;
        var hi = tx.len;
        while (hi - lo > 1) {
            const m = lo + @divTrunc(hi - lo, 2);
            const lim = tx[m].when;
            if (sec < lim) {
                end = lim;
                hi = m;
            } else {
                lo = m;
            }
        }
        const zoneLocal = self.zone[tx[lo].index];
        const start = tx[lo].when;

        // If we're at the end of the known zone transitions,
        // try the extend string.
        if (lo == tx.len - 1 and !std.mem.eql(u8, self.extend, "")) {
            const r = tzset(self.extend, start, sec);
            if (r.ok) {
                return LookupResult{
                    .name = r.name[0..],
                    .offset = r.offset,
                    .start = r.start,
                    .end = r.end,
                    .isDST = r.isDST,
                };
            }
        }

        return LookupResult{
            .name = zoneLocal.name[0..],
            .offset = zoneLocal.offset,
            .start = start,
            .end = end,
            .isDST = zoneLocal.isDST,
        };
    }

    // lookupFirstZone returns the index of the time zone to use for times
    // before the first transition time, or when there are no transition
    // times.
    //
    // The reference implementation in localtime.c from
    // https://www.iana.org/time-zones/repository/releases/tzcode2013g.tar.gz
    // implements the following algorithm for these cases:
    //  1. If the first zone is unused by the transitions, use it.
    //  2. Otherwise, if there are transition times, and the first
    //     transition is to a zone in daylight time, find the first
    //     non-daylight-time zone before and closest to the first transition
    //     zone.
    //  3. Otherwise, use the first zone that is not daylight time, if
    //     there is one.
    //  4. Otherwise, use the first zone.
    fn lookupFirstZone(self: Self) usize {
        // Case 1.
        if (!self.firstZoneUsed()) {
            return 0;
        }

        // Case 2.
        if (self.tx.len > 0 and self.zone[self.tx[0].index].isDST) {
            var zi = @as(usize, @intCast(self.tx[0].index - 1));
            while (zi >= 0) : (zi -= 1) {
                if (!self.zone[zi].isDST) {
                    return zi;
                }
            }
        }

        // Case 3.
        for (0..self.zone.len) |idx| {
            if (!self.zone[idx].isDST) {
                return idx;
            }
        }

        // Case 4.
        return 0;
    }

    // firstZoneUsed reports whether the first zone is used by some
    // transition.
    fn firstZoneUsed(self: Self) bool {
        for (0..self.tx.len) |idx| {
            if (self.tx[idx].index == 0) {
                return true;
            }
        }
        return false;
    }
};

const zone = struct {
    name: []const u8, // abbreviated name, "CET"
    offset: i32, // seconds east of UTC
    isDST: bool, // is this zone Daylight Savings Time?
};
const zoneTrans = struct {
    when: i64, // transition time, in seconds since 1970 GMT
    index: u8, // the index of the zone that goes into effect at that time
    isstd: bool, // ignored - no idea what these mean
    isutc: bool, // ignored - no idea what these mean
};

fn unix(allocator: std.mem.Allocator, timezone: ?[]const u8) !Location {
    if (timezone) |tz| {
        var tzTmp = tz;
        if (tzTmp.len > 0 and tzTmp[0] == ':') {
            tzTmp = tzTmp[1..];
        }
        if (tzTmp.len > 4 and std.mem.eql(u8, tzTmp[tzTmp.len - 4 ..], ".zip")) {
            var sources = std.ArrayList([]const u8).init(allocator);
            defer sources.deinit();

            try sources.append(tzTmp);

            const z = try loadLocation(allocator, tzTmp[0 .. tzTmp.len - 4], sources);
            var buf: [1024]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{s}", .{tzTmp});
            return Location{
                .zone = z.zone,
                .tx = z.tx,
                .name = if (std.mem.eql(u8, tzTmp, "/etc/localtime")) "Local" else s,
                .extend = z.extend,
                .cacheStart = z.cacheStart,
                .cacheEnd = z.cacheEnd,
                .cacheZone = z.cacheZone,
            };
        } else if (!std.mem.eql(u8, tzTmp, "") and !std.mem.eql(u8, tzTmp, "UTC")) {
            var sources = std.ArrayList([]const u8).init(allocator);
            defer sources.deinit();

            try sources.append("/etc");
            try sources.append("/usr/share/zoneinfo");
            try sources.append("/usr/share/lib/zoneinfo");
            try sources.append("/usr/lib/locale/TZ");
            try sources.append("/etc/zoneinfo");

            return try loadLocation(allocator, tzTmp, sources);
        }
    }

    var sources = std.ArrayList([]const u8).init(allocator);
    defer sources.deinit();

    try sources.append("/etc");

    const z = try loadLocation(allocator, "localtime", sources);
    var buff = [_]u8{undefined} ** 100;
    const extend = try std.fmt.bufPrint(&buff, "{s}", .{z.extend});
    return Location{
        .zone = z.zone,
        .tx = z.tx,
        .name = "Local",
        .extend = extend,
        .cacheStart = z.cacheStart,
        .cacheEnd = z.cacheEnd,
        .cacheZone = z.cacheZone,
    };
}
// loadLocation returns the Location with the given name from one of
// the specified sources. See loadTzinfo for a list of supported sources.
// The first timezone data matching the given name that is successfully loaded
// and parsed is returned as a Location.
fn loadLocation(allocator: std.mem.Allocator, name: []const u8, sources: std.ArrayList([]const u8)) !Location {
    var arr = sources;
    while (arr.popOrNull()) |item| {
        const zoneData = loadTzinfo(allocator, name, item) catch "";
        if (zoneData.len == 0) continue;

        var buff = std.io.fixedBufferStream(zoneData);
        return try LoadLocationFromTZData(allocator, name, buff.reader());
    }

    return Error.UnknownTimeZone;
}

fn loadTzinfoFromZip(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var filters = std.ArrayList([]const u8).init(allocator);
    try filters.append(name);

    defer filters.deinit();

    const archive = @import("../archive/mod.zig");

    const data = @embedFile("zoneinfo.zip");
    var in_stream = std.io.fixedBufferStream(data);

    var gzip_stream = try std.compress.gzip.decompress(allocator, in_stream.reader());
    defer gzip_stream.deinit();

    const gzip_data = try gzip_stream.reader().readAllAlloc(allocator, std.math.maxInt(usize));

    var entries = try archive.zip.reader.Entries(allocator, std.io.fixedBufferStream(gzip_data));
    defer entries.deinit();

    const Collector = struct {
        const Self = @This();

        pub const Receiver = archive.GenericReceiver(*Self, receive);

        arr: std.ArrayList([]const u8),

        pub fn init(all: std.mem.Allocator) Self {
            return Self{ .arr = std.ArrayList([]const u8).init(all) };
        }

        pub fn deinit(self: *Self) void {
            self.arr.deinit();
        }

        pub fn receive(self: *Self, filename: []const u8, content: []const u8) !void {
            _ = filename;
            var buf: [500 * 1024:0]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{s}", .{content});
            try self.arr.append(s);
        }

        pub fn receiver(self: *Self) Receiver {
            return .{ .context = self };
        }
    };

    var collector = Collector.init(allocator);
    defer collector.deinit();
    _ = try entries.readWithFilters(filters, collector.receiver().contentReceiver());

    if (collector.arr.getLastOrNull()) |item| {
        return item;
    }

    return Error.UnknownTimeZone;
}

// loadTzinfo returns the time zone information of the time zone
// with the given name, from a given source. A source may be a
// timezone database directory, tzdata database file or an uncompressed
// zip file, containing the contents of such a directory.
fn loadTzinfo(allocator: std.mem.Allocator, name: []const u8, source: []const u8) ![]const u8 {
    if (source.len >= 6 and std.mem.eql(u8, source[source.len - 4 ..], ".zip")) {
        return loadTzinfoFromZip(allocator, name);
    }
    if (!std.mem.eql(u8, source, "")) {
        var buf = Buffer.init(allocator);
        defer buf.deinit();
        _ = try buf.write(source);
        _ = try buf.write("/");
        _ = try buf.write(name);
        const res = buf.bytes();
        return try std.fs.cwd().readFileAlloc(allocator, res[0..], 50 * 1024);
    }

    return try std.fs.cwd().readFileAlloc(allocator, name, 1 * 1024 * 1024);
}

// LoadLocationFromTZData returns a Location with the given name
// initialized from the IANA Time Zone database-formatted data.
// The data should be in the format of a standard IANA time zone file
// (for example, the content of /etc/localtime on Unix systems).
fn LoadLocationFromTZData(allocator: std.mem.Allocator, name: []const u8, in_data: anytype) Error!Location {
    // 4-byte magic "TZif"
    const header = (try in_data.readBoundedBytes(4)).slice();
    if (!std.mem.eql(u8, header, "TZif")) {
        return Error.BadData;
    }

    // 1-byte version, then 15 bytes of padding
    const p = (try in_data.readBoundedBytes(16)).slice();
    var version: i8 = -1;
    if (p[0] == '0') {
        version = 1;
    } else if (p[0] == '2') {
        version = 2;
    } else if (p[0] == '3') {
        version = 3;
    }

    if (version == -1) {
        return Error.BadData;
    }

    // six big-endian 32-bit integers:
    //	number of UTC/local indicators
    //	number of standard/wall indicators
    //	number of leap seconds
    //	number of transition times
    //	number of local time zones
    //	number of characters of time zone abbrev strings
    var n: [6]i32 = undefined;
    for (0..6) |idx| {
        n[idx] = try in_data.readInt(i32, .big);
    }

    // If we have version 2 or 3, then the data is first written out
    // in a 32-bit format, then written out again in a 64-bit format.
    // Skip the 32-bit format and read the 64-bit one, as it can
    // describe a broader range of dates.

    const NUTCLocal = 0;
    const NStdWall = 1;
    const NLeap = 2;
    const NTime = 3;
    const NZone = 4;
    const NChar = 5;
    var is64 = false;
    if (version > 1) {
        // Skip the 32-bit data.
        const skip: u64 = @as(u64, @intCast(n[NTime] * 4 + n[NTime] + n[NZone] * 6 + n[NChar] + n[NLeap] * 8 + n[NStdWall] + n[NUTCLocal]));

        // Skip the version 2 header that we just read.
        try in_data.skipBytes(skip + 20, .{});

        is64 = true;

        // Read the counts again, they can differ.
        for (0..6) |idx| {
            n[idx] = try in_data.readInt(i32, .big);
        }
    }

    const size: i32 = if (is64) 8 else 4;

    // Transition times.
    var t = @as(usize, @intCast(n[NTime] * size));
    var txtimes = Buffer.initWithFactor(allocator, 10);
    defer txtimes.deinit();
    try txtimes.writeBytes(in_data, t);

    // Time zone indices for transition times.
    t = @as(usize, @intCast(n[NTime]));
    var txzones = Buffer.initWithFactor(allocator, 10);
    defer txzones.deinit();
    try txzones.writeBytes(in_data, t);

    // Zone info structures
    t = @as(usize, @intCast(n[NZone] * 6));
    var zonedata = Buffer.initWithFactor(allocator, 10);
    defer zonedata.deinit();
    try zonedata.writeBytes(in_data, t);

    // Time zone abbreviations.
    t = @as(usize, @intCast(n[NChar]));
    var abbrev = Buffer.initWithFactor(allocator, 10);
    defer abbrev.deinit();
    try abbrev.writeBytes(in_data, t);

    // Leap-second time pairs
    t = @as(usize, @intCast(n[NLeap] * (size + 4)));
    try in_data.skipBytes(t, .{});

    // Whether tx times associated with local time types
    // are specified as standard time or wall time.
    t = @as(usize, @intCast(n[NStdWall]));

    var isstd = Buffer.initWithFactor(allocator, 10);
    defer isstd.deinit();
    try isstd.writeBytes(in_data, t);

    // Whether tx times associated with local time types
    // are specified as UTC or local time.
    t = @as(usize, @intCast(n[NUTCLocal]));
    var isutc = Buffer.initWithFactor(allocator, 10);
    defer isutc.deinit();
    try isutc.writeBytes(in_data, t);

    var extent_buff: [1024]u8 = undefined;
    const extend_size = try in_data.read(&extent_buff);
    var extend = extent_buff[0..extend_size];

    if (extend.len > 2 and extend[0] == '\n' and extend[extend.len - 1] == '\n') {
        extend = extend[1 .. extend.len - 1];
    }

    // Now we can build up a useful data structure.
    // First the zone information.
    //	utcoff[4] isdst[1] nameindex[1]
    const nzone = @as(usize, @intCast(n[NZone]));
    if (nzone == 0) {
        // Reject tzdata files with no zones. There's nothing useful in them.
        // This also avoids a panic later when we add and then use a fake transition (golang.org/issue/29437).
        return Error.BadData;
    }

    var zonesBuff = [_]zone{undefined} ** 10000;

    var zonedataBuffTReam = std.io.fixedBufferStream(zonedata.bytes());
    var in_zonedata = zonedataBuffTReam.reader();

    for (0..nzone) |idx| {
        const offset = try in_zonedata.readInt(i32, .big);

        var b = try in_zonedata.readByte();
        const isDST = b != 0;

        b = try in_zonedata.readByte();
        if (b >= abbrev.len) {
            return Error.BadData;
        }

        var zname = try abbrev.fromBytes(b);

        if (builtin.os.tag == .aix and name.len > 8 and (std.mem.eql(u8, name[0..8], "Etc/GMT+") or std.mem.eql(u8, name[0..8], "Etc/GMT-"))) {
            // There is a bug with AIX 7.2 TL 0 with files in Etc,
            // GMT+1 will return GMT-1 instead of GMT+1 or -01.
            if (!std.mem.eql(u8, name, "Etc/GMT+0")) {
                // GMT+0 is OK
                zname = name[4..];
                b = name.len - 4;
            }
        }
        var buf: [1024]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "{s}", .{zname});
        zonesBuff[idx] = zone{ .name = s, .offset = offset, .isDST = isDST };
    }
    const zones = zonesBuff[0..nzone];

    // Now the transition time info.
    const nzonerx = @as(usize, @intCast(n[NTime]));
    var txBuff = [_]zoneTrans{undefined} ** 10000;

    var txtimesBuffTReam = std.io.fixedBufferStream(txtimes.bytes());
    var in_txtimes = txtimesBuffTReam.reader();

    for (0..nzonerx) |idx| {
        var when: i64 = 0;
        if (!is64) {
            const val = try in_txtimes.readInt(u32, .big);
            when = @as(i64, @intCast(val));
        } else {
            const val = try in_txtimes.readInt(u64, .big);
            when = @as(i64, @bitCast(val));
        }

        const index = try txzones.byteAt(idx);
        if (index >= zones.len) {
            return Error.BadData;
        }

        const isstdBool: bool = if (idx < isstd.len) blk: {
            const val = try isstd.byteAt(idx);
            break :blk val != 0;
        } else false;
        const isutcBool: bool = if (idx < isutc.len) blk: {
            const val = try isstd.byteAt(idx);
            break :blk val != 0;
        } else false;

        txBuff[idx] = zoneTrans{ .when = when, .index = index, .isstd = isstdBool, .isutc = isutcBool };
    }
    const tx = txBuff[0..nzonerx];

    if (tx.len == 0) {
        // Build fake transition to cover all time.
        // This happens in fixed locations like "Etc/GMT0".
        tx[0] = zoneTrans{ .when = std.math.minInt(u64), .index = 0, .isstd = false, .isutc = false };
    }

    // Fill in the cache with information about right now,
    // since that will be the most common lookup.
    var cacheStart: i64 = 0;
    var cacheEnd: i64 = 0;
    var cacheZone: ?zone = null;

    const sec: i64 = unixToInternal + internalToAbsolute + std.time.timestamp();
    for (0..tx.len) |txIdx| {
        if (tx[txIdx].when <= sec and (txIdx + 1 == tx.len or sec < tx[txIdx + 1].when)) {
            cacheStart = tx[txIdx].when;
            cacheEnd = std.math.maxInt(i64);
            cacheZone = zones[tx[txIdx].index];
            if (txIdx + 1 < tx.len) {
                cacheEnd = tx[txIdx + 1].when;
            } else if (!std.mem.eql(u8, extend, "")) {
                // If we're at the end of the known zone transitions,
                // try the extend string.

                const r = tzset(extend, cacheStart, sec);
                if (r.ok) {
                    const zname = r.name;
                    const zoffset = r.offset;
                    cacheStart = r.start;
                    cacheEnd = r.end;
                    const zisDST = r.isDST;

                    // Find the zone that is returned by tzset to avoid allocation if possible.
                    for (zones) |z| {
                        if (std.mem.eql(u8, z.name, zname) and z.offset == zoffset and z.isDST == zisDST) {
                            cacheZone = z;
                            break;
                        }
                    }
                    var buf: [1024]u8 = undefined;
                    const s = try std.fmt.bufPrint(&buf, "{s}", .{zname});
                    cacheZone = zone{
                        .name = s,
                        .offset = zoffset,
                        .isDST = zisDST,
                    };
                }
            }
            break;
        }
    }

    var buf: [1024]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "{s}", .{name});
    return Location{
        .zone = zones,
        .tx = tx,
        .name = s,
        .extend = extend[0..extend.len],
        .cacheStart = cacheStart,
        .cacheEnd = cacheEnd,
        .cacheZone = cacheZone.?,
    };
}

// tzset takes a timezone string like the one found in the TZ environment
// variable, the time of the last time zone transition expressed as seconds
// since January 1, 1970 00:00:00 UTC, and a time expressed the same way.
// We call this a tzset string since in C the function tzset reads TZ.
// The return values are as for lookup, plus ok which reports whether the
// parse succeeded.

const internalYear = 1;
const unixToInternal = (1969 * 365 + @divTrunc(1969, 4) - @divTrunc(1969, 100) + @divTrunc(1969, 400)) * std.time.s_per_day;
const internalToUnix = -unixToInternal;

const absoluteToInternal = @as(i64, @intFromFloat(1969 * 365.2425 * std.time.s_per_day));
const internalToAbsolute = -absoluteToInternal;
const wallToInternal: i64 = (1884 * 365 + @divTrunc(1884, 4) - @divTrunc(1884, 100) + @divTrunc(1884, 400)) * std.time.s_per_day;

const tzsetResult = struct {
    name: []const u8,
    offset: i32,
    start: i64,
    end: i64,
    isDST: bool,
    ok: bool,
};
fn tzset(source: []const u8, lastTxSec: i64, sec: i64) tzsetResult {
    var stdOffset: i32 = 0;
    var dstOffset: i32 = 0;

    var r = tzsetName(source);
    const stdName = r.name;
    var s = r.rest;
    if (r.ok) {
        const offRes = tzsetOffset(s);
        stdOffset = -offRes.offset;

        if (!offRes.ok) {
            return tzsetResult{
                .name = "",
                .offset = 0,
                .start = 0,
                .end = 0,
                .isDST = false,
                .ok = false,
            };
        }
    }
    if (s.len == 0 or s[0] == ',') {
        // No daylight savings time.
        return tzsetResult{
            .name = stdName,
            .offset = stdOffset,
            .start = lastTxSec,
            .end = std.math.maxInt(i64),
            .isDST = false,
            .ok = true,
        };
    }

    r = tzsetName(s);
    const dstName = r.name;
    s = r.rest;
    if (r.ok) {
        if (s.len == 0 or s[0] == ',') {
            dstOffset = stdOffset + std.time.s_per_hour;
        } else {
            const offRes = tzsetOffset(s);
            if (!offRes.ok) {
                return tzsetResult{
                    .name = "",
                    .offset = 0,
                    .start = 0,
                    .end = 0,
                    .isDST = false,
                    .ok = false,
                };
            }
            s = offRes.rest;
            dstOffset = -offRes.offset;
        }
    }

    if (s.len == 0) {
        // Default DST rules per tzcode.
        s = ",M3.2.0,M11.1.0";
    }
    // The TZ definition does not mention ';' here but tzcode accepts it.
    if (s[0] != ',' and s[0] != ';') {
        return tzsetResult{
            .name = "",
            .offset = 0,
            .start = 0,
            .end = 0,
            .isDST = false,
            .ok = false,
        };
    }
    s = s[1..];

    var ru = tzsetRule(s);
    s = ru.rest;
    if (!ru.ok or s.len == 0 or s[0] != ',') {
        return tzsetResult{
            .name = "",
            .offset = 0,
            .start = 0,
            .end = 0,
            .isDST = false,
            .ok = false,
        };
    }
    const startRule = ru.rule;

    s = s[1..];
    ru = tzsetRule(s);
    s = ru.rest;
    if (!ru.ok or s.len > 0) {
        return tzsetResult{
            .name = "",
            .offset = 0,
            .start = 0,
            .end = 0,
            .isDST = false,
            .ok = false,
        };
    }
    const endRule = ru.rule;

    const lptime = @import("time.zig");
    const t = lptime.absDate(sec);

    const year = t.year;
    const yday = @as(i32, @intCast(t.yday));

    const ysec = yday * std.time.s_per_day + @rem(sec, std.time.s_per_day);

    // Compute start of year in seconds since Unix epoch.
    const d = lptime.daysSinceEpoch(year);
    var abs = d * std.time.s_per_day;
    abs += absoluteToInternal + internalToUnix;

    var startSec = tzruleTime(year, startRule, stdOffset);
    var endSec = tzruleTime(year, endRule, dstOffset);

    var dstIsDST = false;
    var stdIsDST = true;

    // Note: this is a flipping of "DST" and "STD" while retaining the labels
    // This happens in southern hemispheres. The labelling here thus is a little
    // inconsistent with the goal.
    if (endSec < startSec) {
        std.mem.swap(i64, @constCast(&startSec), @constCast(&endSec));
        std.mem.swap([]const u8, @constCast(&stdName), @constCast(&dstName));
        std.mem.swap(i32, @constCast(&stdOffset), @constCast(&dstOffset));
        std.mem.swap(bool, @constCast(&stdIsDST), @constCast(&dstIsDST));
    }

    // The start and end values that we return are accurate
    // close to a daylight savings transition, but are otherwise
    // just the start and end of the year. That suffices for
    // the only caller that cares, which is Date.
    if (ysec < startSec) {
        return tzsetResult{
            .name = stdName,
            .offset = stdOffset,
            .start = abs,
            .end = startSec + abs,
            .isDST = stdIsDST,
            .ok = true,
        };
    }

    if (ysec >= endSec) {
        return tzsetResult{
            .name = stdName,
            .offset = stdOffset,
            .start = endSec + abs,
            .end = abs + 365 * std.time.s_per_day,
            .isDST = stdIsDST,
            .ok = true,
        };
    }

    return tzsetResult{
        .name = stdName,
        .offset = stdOffset,
        .start = startSec + abs,
        .end = endSec + abs,
        .isDST = stdIsDST,
        .ok = true,
    };
}

// tzsetName returns the timezone name at the start of the tzset string s,
// and the remainder of s, and reports whether the parsing is OK.

const tzsetNameResult = struct {
    name: []const u8,
    rest: []const u8,
    ok: bool,
};
fn tzsetName(s: []const u8) tzsetNameResult {
    if (s.len == 0) {
        return tzsetNameResult{ .name = "", .rest = "", .ok = false };
    }
    if (s[0] != '<') {
        for (s, 0..) |r, i| {
            switch (r) {
                '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '-', '+' => {
                    if (i < 3) {
                        return tzsetNameResult{ .name = "", .rest = "", .ok = false };
                    }
                    return tzsetNameResult{ .name = s[0..i], .rest = s[i..], .ok = true };
                },
                else => {},
            }
        }
        if (s.len < 3) {
            return tzsetNameResult{ .name = "", .rest = "", .ok = false };
        }
        return tzsetNameResult{ .name = s, .rest = "", .ok = true };
    } else {
        for (s, 0..) |r, i| {
            if (r == '>') {
                return tzsetNameResult{ .name = s[1..i], .rest = s[i + 1 ..], .ok = true };
            }
        }
        return tzsetNameResult{ .name = "", .rest = "", .ok = false };
    }
}

// tzsetOffset returns the timezone offset at the start of the tzset string s,
// and the remainder of s, and reports whether the parsing is OK.
// The timezone offset is returned as a number of seconds.
const tzsetOffsetResult = struct {
    offset: i32,
    rest: []const u8,
    ok: bool,
};
fn tzsetOffset(source: []const u8) tzsetOffsetResult {
    var s = source;
    if (s.len == 0) {
        return tzsetOffsetResult{ .offset = 0, .rest = "", .ok = false };
    }

    var neg = false;
    if (s[0] == '+') {
        s = s[1..];
    } else if (s[0] == '-') {
        s = s[1..];
        neg = true;
    }

    // The tzdata code permits values up to 24 * 7 here,
    // although POSIX does not.
    var tynumResult = tzsetNum(s, 0, 24 * 7);
    const hours = tynumResult.num;
    s = tynumResult.rest;
    if (!tynumResult.ok) {
        return tzsetOffsetResult{ .offset = 0, .rest = "", .ok = false };
    }
    var off = hours * std.time.s_per_hour;
    if (s.len == 0 or s[0] != ':') {
        if (neg) {
            off = -off;
        }
        return tzsetOffsetResult{ .offset = off, .rest = s, .ok = true };
    }

    tynumResult = tzsetNum(s[1..], 0, 59);
    const mins = tynumResult.num;
    s = tynumResult.rest;
    if (!tynumResult.ok) {
        return tzsetOffsetResult{ .offset = 0, .rest = "", .ok = false };
    }
    off += mins * std.time.s_per_min;
    if (s.len == 0 or s[0] != ':') {
        if (neg) {
            off = -off;
        }
        return tzsetOffsetResult{ .offset = off, .rest = s, .ok = true };
    }

    tynumResult = tzsetNum(s[1..], 0, 59);
    const secs = tynumResult.num;
    s = tynumResult.rest;
    if (!tynumResult.ok) {
        return tzsetOffsetResult{ .offset = 0, .rest = "", .ok = false };
    }

    off += secs;

    if (neg) {
        off = -off;
    }
    return tzsetOffsetResult{ .offset = off, .rest = s, .ok = true };
}

// tzsetNum parses a number from a tzset string.
// It returns the number, and the remainder of the string, and reports success.
// The number must be between min and max.
const tzsetNumResult = struct {
    num: i32,
    rest: []const u8,
    ok: bool,
};
fn tzsetNum(s: []const u8, min: i32, max: i32) tzsetNumResult {
    if (s.len == 0) {
        return tzsetNumResult{ .num = 0, .rest = "", .ok = false };
    }
    var num: i32 = 0;
    for (s, 0..) |r, i| {
        if (r < '0' or r > '9') {
            if (i == 0 or num < min) {
                return tzsetNumResult{ .num = 0, .rest = "", .ok = false };
            }
            return tzsetNumResult{ .num = num, .rest = s[i..], .ok = true };
        }
        num *= 10;
        num += r - '0';

        if (num > max) {
            return tzsetNumResult{ .num = 0, .rest = "", .ok = false };
        }
    }
    if (num < min) {
        return tzsetNumResult{ .num = 0, .rest = "", .ok = false };
    }
    return tzsetNumResult{ .num = num, .rest = "", .ok = true };
}

// tzsetRule parses a rule from a tzset string.
// It returns the rule, and the remainder of the string, and reports success.
// rule is a rule read from a tzset string.
const ruleKind = enum(u8) {
    Julian = 0,
    DOY,
    MonthWeekDay,
};
const rule = struct {
    kind: ruleKind,
    day: i32,
    week: i32,
    mon: i32,
    time: i32, // transition time

    pub fn empty() rule {
        return .{ .kind = .Julian, .day = 0, .week = 0, .mon = 0, .time = 0 };
    }
};

const tzsetRuleResult = struct {
    rule: rule,
    rest: []const u8,
    ok: bool,
};
fn tzsetRule(source: []const u8) tzsetRuleResult {
    var s = source;
    if (s.len == 0) {
        return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
    }

    var kind: ruleKind = ruleKind.Julian;
    var day: i32 = 0;
    var week: i32 = 0;
    var mon: i32 = 0;
    var ltime: i32 = 0;
    if (s[0] == 'J') {
        kind = ruleKind.Julian;

        const r = tzsetNum(s[1..], 1, 365);
        if (!r.ok) {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        day = r.num;
    } else if (s[0] == 'M') {
        kind = ruleKind.MonthWeekDay;

        var r = tzsetNum(s[1..], 1, 12);
        s = r.rest;
        if (!r.ok or s.len == 0 or s[0] != '.') {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        mon = r.num;

        r = tzsetNum(s[1..], 1, 5);
        s = r.rest;
        if (!r.ok or s.len == 0 or s[0] != '.') {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        week = r.num;

        r = tzsetNum(s[1..], 0, 6);
        if (!r.ok) {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        day = r.num;
        s = r.rest;
    } else {
        kind = ruleKind.DOY;

        const r = tzsetNum(s, 0, 365);
        if (!r.ok) {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        day = r.num;
    }

    if (s.len == 0 or s[0] != '/') {
        ltime = 2 * std.time.s_per_hour; // 2am is the default

        return tzsetRuleResult{
            .rule = rule{ .kind = kind, .day = day, .week = week, .mon = mon, .time = ltime },
            .rest = s,
            .ok = true,
        };
    }

    const r = tzsetOffset(s[1..]);
    if (!r.ok) {
        return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
    }

    return tzsetRuleResult{
        .rule = rule{ .kind = kind, .day = day, .week = week, .mon = mon, .time = r.offset },
        .rest = r.rest,
        .ok = true,
    };
}

// tzruleTime takes a year, a rule, and a timezone offset,
// and returns the number of seconds since the start of the year
// that the rule takes effect.
fn tzruleTime(year: i32, r: rule, off: i32) i64 {
    const ltime = @import("time.zig");
    var s: i64 = 0;
    switch (r.kind) {
        .Julian => {
            s = (r.day - 1) * std.time.s_per_day;
            if (ltime.isLeap(year) and r.day >= 60) {
                s += std.time.s_per_day;
            }
        },

        .DOY => s = r.day * std.time.s_per_day,
        .MonthWeekDay => {
            // Zeller's Congruence.
            const m1 = @rem((r.mon + 9), 12) + 1;
            var yy0 = year;
            if (r.mon <= 2) {
                yy0 -= 1;
            }
            const yy1 = @divFloor(yy0, 100);
            const yy2 = @rem(yy0, 100);
            var dow = @rem((@divFloor((26 * m1 - 2), 10) + 1 + yy2 + @divFloor(yy2, 4) + @divFloor(yy1, 4) - 2 * yy1), 7);
            if (dow < 0) {
                dow += 7;
            }
            // Now dow is the day-of-week of the first day of r.mon.
            // Get the day-of-month of the first "dow" day.
            var d = r.day - dow;
            if (d < 0) {
                d += 7;
            }

            for (1..@as(usize, @intCast(r.week))) |_| {
                if (d + 7 >= ltime.daysIn(r.mon, year)) {
                    break;
                }
                d += 7;
            }

            const idx = @as(usize, @intCast(r.mon));
            d += @as(i32, @intCast(ltime.daysBefore[idx - 1]));
            if (ltime.isLeap(year) and r.mon > 2) {
                d += 1;
            }
            s = d * std.time.s_per_day;
        },
    }

    return s + r.time - off;
}

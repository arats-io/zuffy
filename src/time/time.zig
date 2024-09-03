const std = @import("std");
const Utf8Buffer = @import("../bytes/mod.zig").Utf8Buffer;

pub const Measure = enum(u2) { seconds = 0, millis = 1, micros = 2, nanos = 3 };

pub const Month = enum(u4) {
    January = 1,
    February,
    March,
    April,
    May,
    June,
    July,
    August,
    September,
    October,
    November,
    December,

    pub inline fn string(self: Month) []const u8 {
        return @tagName(self);
    }

    pub inline fn shortString(self: Month) []const u8 {
        return @tagName(self)[0..3];
    }
};

pub const Weekday = enum(u3) {
    Monday = 1,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
    Sunday,

    pub inline fn string(self: Weekday) []const u8 {
        return @tagName(self);
    }
    pub inline fn shortString(self: Weekday) []const u8 {
        return @tagName(self)[0..3];
    }

    pub inline fn shorterString(self: Weekday) []const u8 {
        return @tagName(self)[0..2];
    }
};

pub const DateTime = struct {
    year: u16,
    month: u5,
    yday: u9,
    wday: u3,
    day: u5,
    hour: u6,
    min: u6,
    sec: u6,
};

pub const Time = struct {
    const Self = @This();

    measure: Measure,
    value: i128,

    date_time: ?DateTime = null,
    offset: ?i32 = null,

    rest: u64 = 0,
    milli: u10 = 0,
    micro: u10 = 0,
    nano: u10 = 0,

    pub fn new(measure: Measure) Self {
        const t = @constCast(&Self{ .measure = measure, .value = switch (measure) {
            inline .seconds => std.time.timestamp(),
            inline .millis => std.time.milliTimestamp(),
            inline .micros => std.time.microTimestamp(),
            inline .nanos => std.time.nanoTimestamp(),
        } }).pupulate();
        return t.*;
    }

    inline fn dateTime(self: Self) DateTime {
        return self.date_time.?;
    }

    inline fn pupulate(self: *Self) *Self {
        const seconds = switch (self.measure) {
            inline .seconds => self.value,
            inline .millis => blk: {
                const milli = @rem(self.value, std.time.ms_per_s);
                @atomicStore(u10, @constCast(&self.milli), @as(u10, @intCast(milli)), .monotonic);
                @atomicStore(u64, @constCast(&self.rest), @as(u64, @intCast(milli)), .monotonic);

                break :blk @divTrunc(self.value, std.time.ms_per_s);
            },
            inline .micros => blk: {
                const micro = @rem(self.value, std.time.ns_per_us);
                @atomicStore(u10, @constCast(&self.micro), @as(u10, @intCast(micro)), .monotonic);

                var milli = @rem(self.value, std.time.us_per_s);
                @atomicStore(u64, @constCast(&self.rest), @as(u64, @intCast(milli)), .monotonic);

                milli = @divTrunc(milli, std.time.ns_per_us);
                @atomicStore(u10, @constCast(&self.milli), @as(u10, @intCast(milli)), .monotonic);

                break :blk @divTrunc(self.value, std.time.us_per_s);
            },
            inline .nanos => blk: {
                const nano = @rem(self.value, std.time.ns_per_us);
                @atomicStore(u10, @constCast(&self.nano), @as(u10, @intCast(nano)), .monotonic);

                var micro = @rem(self.value, std.time.ns_per_ms);
                micro = @divTrunc(micro, std.time.ns_per_us);
                @atomicStore(u10, @constCast(&self.micro), @as(u10, @intCast(micro)), .monotonic);

                var milli = @rem(self.value, std.time.ns_per_s);
                @atomicStore(u64, @constCast(&self.rest), @as(u64, @intCast(milli)), .monotonic);

                milli = @divTrunc(milli, std.time.ns_per_ms);
                @atomicStore(u10, @constCast(&self.milli), @as(u10, @intCast(milli)), .monotonic);

                break :blk @divTrunc(self.value, std.time.ns_per_s);
            },
        };

        self.offset = offsetValue();
        self.date_time = absDate(seconds + self.offset.?);

        return self;
    }

    inline fn offsetValue() i32 {
        const loc = @import("zoneinfo.zig").Local.Get() catch |err| {
            std.debug.panic("{any}", .{err});
        };
        return @as(i32, @bitCast(loc.Lookup().offset));
    }

    /// Format a date to a string according to requested pattern.
    ///
    /// Example:
    /// `Time.now().formatf('MMMM Mo YY N kk:mm:ss A')) -> January 1st 22 AD 13:45:33 PM`
    ///
    /// **Month**
    ///   - `M  -> 1 2 ... 11 12`
    ///   - `Mo -> 1st 2nd ... 11th 12th`
    ///   - `MM -> 01 02 ... 11 12`
    ///   - `MMM -> Jan Feb ... Nov Dec`
    ///   - `MMMM -> January February ... November December`
    ///
    /// **Quarter**
    ///   - `Q  -> 1 2 3 4`
    ///   - `QQ -> 01 02 03 04`
    ///   - `Qo -> 1st 2nd 3rd 4th`
    ///
    /// **Day of Month**
    ///   - `D  -> 1 2 ... 30 31`
    ///   - `Do -> 1st 2nd ... 30th 31st`
    ///   - `DD -> 01 02 ... 30 31`
    ///
    /// **Day of Year**
    ///   - `DDD -> 1 2 ... 364 365`
    ///   - `DDDo -> 1st 2nd ... 364th 365th`
    ///   - `DDDD -> 001 002 ... 364 365`
    ///
    ///  **Day of Week**
    ///   - `d -> 0 1 ... 5 6 (Sun-Sat)`
    ///   - `c -> 1 2 ... 6 7 (Mon-Sun)`
    ///   - `dd -> Su Mo ... Fr Sa`
    ///   - `ddd -> Sun Mon ... Fri Sat`
    ///   - `dddd -> Sunday Monday ... Friday Saturday`
    ///   - `e -> 0 1 ... 5 6 (locale)`
    ///   - `E -> 1 2 ... 6 7 (ISO)`
    ///
    /// **Week of Year**
    ///   - `w  -> 1 2 ... 52 53`
    ///   - `wo -> 1st 2nd ... 52nd 53rd`
    ///   - `ww -> 01 02 ... 52 53`
    ///
    /// **Year**
    ///   - `Y -> 11970 11971 ... 19999 20000 20001 (Holocene calendar)`
    ///   - `YY -> 70 71 ... 29 30`
    ///   - `YYY -> 1 2 ... 1970 1971 ... 2029 2030`
    ///   - `YYYY -> 1970 1971 ... 2029 2030`
    ///
    /// **Era**
    ///   - `N  -> BC AD`                       //AD (Not yet supported)
    ///   - `NN -> Before Christ, Anno Domini`  //AD (Not yet supported)
    ///
    /// **AM/PM**
    ///   - `A -> AM PM`
    ///   - `a -> am pm`
    ///
    /// **Hour**
    ///   - `H  -> 0 1 ... 22 23`
    ///   - `HH -> 00 01 ... 22 23`
    ///   - `h  -> 1 2 ... 11 12`
    ///   - `hh -> 01 02 ... 11 12`
    ///   - `k  -> 1 2 ... 23 24`
    ///   - `kk -> 01 02 ... 23 24`
    ///
    /// **Minute**
    ///   - `m  -> 0 1 ... 58 59`
    ///   - `mm -> 00 01 ... 58 59`
    ///
    /// **Second**
    ///   - `s  -> 0 1 ... 58 59`
    ///   - `ss -> 00 01 ... 58 59`
    ///   - `S -> 0 1 ... 8 9 (second fraction)`
    ///   - `SS -> 00 01 ... 98 99`
    ///   - `SSS -> 000 001 ... 998 999`
    ///
    /// **Offset**
    ///   - `Z   -> -7 -6 ... +5 +6`
    ///   - `ZZ  -> -0700 -0600 ... +0500 +0600`
    ///   - `ZZZ -> -07:00 -06:00 ... +05:00 +06:00`
    ///
    pub fn formatf(self: Self, allocator: std.mem.Allocator, pattern: []const u8, writer: anytype) !void {
        var sb = try self.format(allocator, pattern);
        defer sb.deinit();
        errdefer sb.deinit();
        _ = try writer.write(sb.bytes());
    }

    /// Format the date and time according to requested pattern to a destination
    pub fn formatfInto(self: Self, allocator: std.mem.Allocator, pattern: []const u8, dst: []const u8) !usize {
        var sb = try Utf8Buffer.initWithCapacity(allocator, pattern.len);
        errdefer sb.deinit();
        defer sb.deinit();

        try self.format(@constCast(&sb.writer()), pattern);
        return try sb.bytesInto(dst);
    }

    inline fn format(self: Self, writer: anytype, pattern: []const u8) !void {
        var tokens = TokenIterator.init(pattern);
        while (tokens.next()) |token| {
            try self.appendToken(token, writer);
        }
    }

    inline fn suffix(m: i128) []const u8 {
        return switch (m) {
            inline 1 => "st",
            inline 2 => "nd",
            inline 3 => "rd",
            else => "th",
        };
    }

    inline fn appendToken(self: Self, token: []const u8, writer: anytype) !void {
        const date_time = self.dateTime();

        if (std.meta.stringToEnum(FormatToken, token)) |tag| {
            switch (tag) {
                .Y => try writer.print("{}", .{date_time.year + 10000}),
                .YY => {
                    var buf: [4]u8 = undefined;
                    var yy = try std.fmt.bufPrint(&buf, "{}", .{date_time.year});
                    try writer.print("{s}", .{yy[2..]});
                },
                .YYY => try writer.print("{}", .{date_time.year}),
                .YYYY => try writer.print("{d:0>4}", .{date_time.year}),
                .MMMM => try writer.print("{s}", .{self.getMonth().string()}),
                .MMM => try writer.print("{s}", .{self.getMonth().shortString()}),
                .MM => try writer.print("{d:0>2}", .{date_time.month}),
                .M => try writer.print("{}", .{date_time.month}),
                .Mo => try writer.print("{}{s}", .{ date_time.month, suffix(date_time.month) }),
                .DD => try writer.print("{d:0>2}", .{date_time.day}),
                .D => try writer.print("{}", .{date_time.day}),
                .Do => {
                    const rem = @rem(date_time.day, 30);
                    try writer.print("{}{s}", .{ date_time.day, suffix(rem) });
                },
                .DDDD => try writer.print("{d:0>3}", .{date_time.yday}),
                .DDD => try writer.print("{}", .{date_time.yday}),
                .DDDo => {
                    const rem = @rem(date_time.yday, daysBefore[date_time.month]);
                    try writer.print("{}{s}", .{ date_time.yday, suffix(rem) });
                },
                .HH => try writer.print("{d:0>2}", .{date_time.hour}),
                .H => try writer.print("{}", .{date_time.hour}),
                .kk => try writer.print("{d:0>2}", .{date_time.hour}),
                .k => try writer.print("{}", .{date_time.hour}),
                .hh => {
                    const h = @rem(date_time.hour, 12);
                    try writer.print("{d:0>2}", .{h});
                },
                .h => {
                    const h = @rem(date_time.hour, 12);
                    try writer.print("{}", .{h});
                },
                .mm => try writer.print("{d:0>2}", .{date_time.min}),
                .m => try writer.print("{}", .{date_time.min}),
                .ss => try writer.print("{d:0>2}", .{date_time.sec}),
                .s => try writer.print("{}", .{date_time.sec}),

                .S => if (@intFromEnum(self.measure) < @intFromEnum(Measure.millis)) try writer.print("{}", .{self.rest / 100}),
                .SS => if (@intFromEnum(self.measure) < @intFromEnum(Measure.millis)) try writer.print("{}", .{self.rest / 10}),
                .SSS => if (@intFromEnum(self.measure) >= @intFromEnum(Measure.millis)) try writer.print("{}", .{self.rest}),

                .A => _ = try writer.write(if (date_time.hour <= 11) "AM" else "PM"),
                .a => _ = try writer.write(if (date_time.hour <= 11) "am" else "pm"),
                .d => try writer.print("{}", .{date_time.wday - 1}),
                .c => try writer.print("{}", .{date_time.wday}),
                .dd => try writer.print("{s}", .{self.getWeekday().shorterString()}),
                .ddd => try writer.print("{s}", .{self.getWeekday().shortString()}),
                .dddd => try writer.print("{s}", .{self.getWeekday().string()}),
                .e => try writer.print("{}", .{date_time.wday}),
                .E => try writer.print("{}", .{date_time.wday + 1}),
                .ZZZ => try self.zzz(writer, ":"),
                .ZZ => try self.zzz(writer, ""),
                .Z => {
                    const h = @divFloor(self.offset.?, std.time.s_per_hour);
                    try writer.print("{s}{}", .{ if (h > 0) "+" else "", h });
                },
                .NN => _ = try writer.write("BC"),
                .N => _ = try writer.write("Before Christ"),
                .w => {
                    const l: u32 = if (isLeap(date_time.year)) 1 else 0;
                    const wy = @divTrunc(mceil(date_time.day + daysBefore[date_time.month - 1] + l), 7);
                    try writer.print("{}", .{wy});
                },
                .wo => {
                    const l: u32 = if (isLeap(date_time.year)) 1 else 0;
                    const wy = @divTrunc(mceil(date_time.day + daysBefore[date_time.month - 1] + l), 7);
                    try writer.print("{}{s}", .{ wy, suffix(wy) });
                },
                .ww => {
                    const l: u32 = if (isLeap(date_time.year)) 1 else 0;
                    const wy = @divTrunc(mceil(date_time.day + daysBefore[date_time.month - 1] + l), 7);
                    try writer.print("{d:0>2}", .{wy});
                },
                .QQ => {
                    const q = @divTrunc(date_time.month - 1, 3) + 1;
                    try writer.print("0{}", .{q});
                },
                .Q => {
                    const q = @divTrunc(date_time.month - 1, 3) + 1;
                    try writer.print("{}", .{q});
                },
                .Qo => {
                    const q = @divTrunc(date_time.month - 1, 3) + 1;
                    try writer.print("{}{s}", .{ q, suffix(q) });
                },
                .x => try writer.print("{}", .{std.time.milliTimestamp()}),
                .X => try writer.print("{}", .{std.time.timestamp()}),
                else => {},
            }
        } else {
            _ = try writer.write(token);
        }
    }

    pub inline fn getWeekday(self: Self) Weekday {
        return @as(Weekday, @enumFromInt(self.dateTime().wday));
    }
    pub inline fn getMonth(self: Self) Month {
        return @as(Month, @enumFromInt(self.dateTime().month));
    }

    inline fn zzz(self: Self, writer: anytype, delimeter: []const u8) !void {
        var h = @divFloor(self.offset.?, std.time.s_per_hour);
        if (h > 0) {
            _ = try writer.write("+");
        } else if (h < 0) {
            _ = try writer.write("-");
            h = @as(i32, @intCast(@abs(h)));
        }
        if (h < 10) {
            try writer.print("0{d}", .{h});
        } else {
            try writer.print("{d}", .{h});
        }

        const m = @as(i32, @intCast(@divFloor(@as(i32, @intCast(@abs(self.offset.?))) - h * std.time.s_per_hour, std.time.s_per_min)));
        if (m < 10) {
            try writer.print("{s}0{d}", .{ delimeter, m });
        } else {
            try writer.print("{s}{d}", .{ delimeter, m });
        }
    }
};

/// Verify if the year is a leap year, which is a number which divide by 4, 100 and 400 having remaining number equal with 0.
pub inline fn isLeap(year: i128) bool {
    return @rem(year, 4) == 0 and (@rem(year, 100) != 0 or @rem(year, 400) == 0);
}

pub inline fn daysIn(m: i32, year: i32) u32 {
    if (m == 2 and isLeap(year)) {
        return 29;
    }
    const idx = @as(usize, @intCast(m));
    return daysBefore[idx] - daysBefore[idx - 1];
}

pub const absolute_zero_year = 1970;
pub const days_per_year = 365;
pub const days_per_400_years = days_per_year * 400 + 97;
pub const days_per_100_years = days_per_year * 100 + 24;
pub const days_per_4_years = days_per_year * 4 + 1;

// daysBefore[m] counts the number of days in a non-leap year
// before month m begins. There is an entry for m=12, counting
// the number of days before January of next year (365).
pub const daysBefore = [13]u32{
    0,
    31,
    31 + 28,
    31 + 28 + 31,
    31 + 28 + 31 + 30,
    31 + 28 + 31 + 30 + 31,
    31 + 28 + 31 + 30 + 31 + 30,
    31 + 28 + 31 + 30 + 31 + 30 + 31,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30 + 31,
};

inline fn mceil(x: i128) i128 {
    return if (x > 0) 1 + x else if (x < 0) x else 0;
}

const weekday_t = [_]u8{ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
fn weekday(y: u16, m: u5, d: u5) u16 {
    // Sakomotho's algorithm is explained here:
    // https://stackoverflow.com/a/6385934
    var sy = y;
    if (m < 3) {
        sy = sy - 1;
    }
    const t1 = @divTrunc(sy, 4);
    const t2 = @divTrunc(sy, 100);
    const t3 = @divTrunc(sy, 400);

    const i = @as(usize, @intCast(m));
    return @rem((sy + t1 - t2 + t3 + weekday_t[i - 1] + d - 1), 7) + 1;
}

pub fn daysSinceEpoch(year: i32) i64 {
    var y = year - absolute_zero_year;

    // Add in days from 400-year cycles.
    var n = @divFloor(y, 400);
    y -= 400 * n;
    var d = days_per_400_years * n;

    // Add in 100-year cycles.
    n = @divFloor(y, 100);
    y -= 100 * n;
    d += days_per_100_years * n;

    // Add in 4-year cycles.
    n = @divFloor(y, 4);
    y -= 4 * n;
    d += days_per_4_years * n;

    // Add in non-leap years.
    n = y;
    d += 365 * n;

    return @as(i64, @intCast(d));
}

pub fn absDate(seconds: i128) DateTime {
    // Split into time and day.
    var d = @divFloor(seconds, std.time.s_per_day);

    // Account for 400 year cycles.
    var n = @divFloor(d, days_per_400_years);
    var y = 400 * n;
    d -= days_per_400_years * n;

    // Cut off 100-year cycles.
    // The last cycle has one extra leap year, so on the last day
    // of that year, day / daysPer100Years will be 4 instead of 3.
    // Cut it back down to 3 by subtracting n>>2.
    n = @divFloor(d, days_per_100_years);
    n -= n >> 2;
    y += 100 * n;
    d -= days_per_100_years * n;

    // Cut off 4-year cycles.
    // The last cycle has a missing leap year, which does not
    // affect the computation.
    n = @divFloor(d, days_per_4_years);
    y += 4 * n;
    d -= days_per_4_years * n;

    // Cut off years within a 4-year cycle.
    // The last year is a leap year, so on the last day of that year,
    // day / 365 will be 4 instead of 3. Cut it back down to 3
    // by subtracting n>>2.
    n = @divFloor(d, days_per_year);
    n -= n >> 2;
    y += n;
    d -= days_per_year * n;

    var sec = @rem(seconds, std.time.s_per_day);
    const hour = @divFloor(sec, std.time.s_per_hour);
    sec -= hour * std.time.s_per_hour;
    const min = @divFloor(sec, std.time.s_per_min);
    sec -= min * std.time.s_per_min;

    const year = y + absolute_zero_year;

    var day = d;

    // Estimate month on assumption that every month has 31 days.
    // The estimate may be too low by at most one month, so adjust.
    var month = @divFloor(day, 31);
    if (isLeap(year)) {
        // Leap year
        if (day > 31 + 29 - 1) {
            day -= 1;
        }
        if (day == 31 + 29 - 1) {
            day -= 1;
            // Leap day.
            month = 2; // February
            day = 29;

            return DateTime{
                .year = @as(u16, @intCast(year)),
                .month = @as(u5, @intCast(month)),
                .yday = @as(u9, @intCast(d)),
                .wday = @as(u3, @intCast(weekday(@as(u16, @intCast(year)), @as(u5, @intCast(month)), @as(u5, @intCast(day))))),
                .day = @as(u5, @intCast(day)),
                .hour = @as(u6, @intCast(hour)),
                .min = @as(u6, @intCast(min)),
                .sec = @as(u6, @intCast(sec)),
            };
        }
    }

    const i = @as(usize, @intCast(month));
    var begin = daysBefore[i];
    const end = daysBefore[i + 1];

    if (day >= end) {
        month += 1;
        begin = end;
    }

    month += 1; // because January is 1
    day = day - begin + 1;

    return DateTime{
        .year = @as(u16, @intCast(year)),
        .month = @as(u5, @intCast(month)),
        .yday = @as(u9, @intCast(d)),
        .wday = @as(u3, @intCast(weekday(@as(u16, @intCast(year)), @as(u5, @intCast(month)), @as(u5, @intCast(day))))),
        .day = @as(u5, @intCast(day)),
        .hour = @as(u6, @intCast(hour)),
        .min = @as(u6, @intCast(min)),
        .sec = @as(u6, @intCast(sec)),
    };
}

const FormatToken = enum {
    M, // 1 2 ... 11 12
    Mo, // 1st 2nd ... 11th 12th
    MM, // 01 02 ... 11 12
    MMM, // Jan Feb ... Nov Dec
    MMMM, // January February ... November December
    Q, // 1 2 3 4
    QQ, // 01 02 03 04
    Qo, // 1st 2nd 3rd 4th
    D, // 1 2 ... 30 31
    Do, // 1st 2nd ... 30th 31st
    DD, // 01 02 ... 30 31
    DDD, // 1 2 ... 364 365
    DDDo, // 1st 2nd ... 364th 365th
    DDDD, // 001 002 ... 364 365
    d, // 0 1 ... 5 6
    c, // 1 2 ... 6 7 (Mon-Sun)
    do, // 0th 1st ... 5th 6th
    dd, // Su Mo ... Fr Sa
    ddd, // Sun Mon ... Fri Sat
    dddd, // Sunday Monday ... Friday Saturday
    e, // 0 1 ... 5 6 (locale)
    E, // 1 2 ... 6 7 (ISO)
    w, // 1 2 ... 52 53
    wo, // 1st 2nd ... 52nd 53rd
    ww, // 01 02 ... 52 53
    Y, // 11970 11971 ... 19999 20000 20001 (Holocene calendar)
    YY, // 70 71 ... 29 30
    YYY, // 1 2 ... 1970 1971 ... 2029 2030
    YYYY, // 0001 0002 ... 1970 1971 ... 2029 2030
    N, // BC AD
    NN, // Before Christ ... Anno Domini
    A, // AM PM
    a, // am pm
    H, // 0 1 ... 22 23
    HH, // 00 01 ... 22 23
    h, // 1 2 ... 11 12
    hh, // 01 02 ... 11 12
    k, // 1 2 ... 23 24
    kk, // 01 02 ... 23 24
    m, // 0 1 ... 58 59
    mm, // 00 01 ... 58 59
    s, // 0 1 ... 58 59
    ss, // 00 01 ... 58 59
    S, // 0 1 ... 8 9 (second fraction)
    SS, // 00 01 ... 98 99
    SSS, // 000 001 ... 998 999
    z, // EST CST ... MST PST
    Z, // -7 -6 ... +5 +6
    ZZ, // -0700 -0600 ... +0600 +0700
    ZZZ, // -07:00 -06:00 ... +05:00 +06:00
    x, // unix milli
    X, // unix
};

const tokens_2 = [_][]const u8{ "MM", "Mo", "DD", "Do", "YY", "ss", "kk", "NN", "mm", "hh", "HH", "ZZ", "dd", "Qo", "QQ", "wo", "ww" };
const tokens_3 = [_][]const u8{ "MMM", "DDD", "ZZZ", "ddd", "SSS", "YYY" };
const tokens_4 = [_][]const u8{ "MMMM", "DDDD", "DDDo", "dddd", "YYYY" };

inline fn in(comptime tokentype: u4, elem: []const u8) bool {
    inline for (switch (tokentype) {
        inline 2 => tokens_2,
        inline 3 => tokens_3,
        inline 4 => tokens_4,
        inline 5...15, 0...1 => [_][]const u8{},
    }) |item| {
        if (std.mem.eql(u8, item, elem)) {
            return true;
        }
    }
    return false;
}

const TokenIterator = struct {
    const Self = @This();

    i: usize = 0,
    expression: []const u8,

    pub fn init(expression: []const u8) Self {
        return Self{ .expression = expression };
    }

    pub fn next(self: *Self) ?[]const u8 {
        while (self.i < self.expression.len) {
            var j: usize = 12;
            var token: ?[]const u8 = null;
            while (j > 0) : (j -= 1) {
                if (self.i > self.expression.len - j) {
                    continue;
                }

                const slice = self.expression.ptr[self.i .. self.i + j];
                const l1 = j == 1;
                const l2 = j == 2 and in(2, slice);
                const l3 = j == 3 and in(3, slice);
                const l4 = j == 4 and in(4, slice);
                if (l1 or l2 or l3 or l4) {
                    token = self.expression.ptr[self.i .. self.i + j];
                    _ = @atomicRmw(usize, &self.i, .Add, j - 1, .seq_cst);
                    break;
                }
            }
            _ = @atomicRmw(usize, &self.i, .Add, 1, .seq_cst);
            if (token) |item| {
                return item;
            }
        }
        return null;
    }
};

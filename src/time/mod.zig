pub const zoneinfo = @import("zoneinfo.zig");

pub const Time = @import("time.zig").Time;
pub const Measure = @import("time.zig").Measure;
pub const Month = @import("time.zig").Month;
pub const Weekday = @import("time.zig").Weekday;

pub fn now() Time {
    return Time.new(.seconds);
}

pub fn unixMilli() Time {
    return Time.new(.millis);
}

pub fn unixMicros() Time {
    return Time.new(.micros);
}

pub fn unixNanos() Time() {
    return Time.new(.nanos);
}

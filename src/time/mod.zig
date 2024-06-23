pub const zoneinfo = @import("zoneinfo.zig");

const time = @import("time.zig");
pub const Time = time.Time;
pub const Measure = time.Measure;
pub const Month = time.Month;
pub const Weekday = time.Weekday;

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

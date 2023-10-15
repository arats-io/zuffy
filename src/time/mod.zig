pub const Time = @import("time.zig").Time;
pub const Measure = @import("time.zig").Measure;
pub const Month = @import("time.zig").Month;
pub const Weekday = @import("time.zig").Weekday;

pub fn now() Time {
    return Time(.seconds).now();
}

pub fn unixMilli() Time {
    return Time(.millis).now();
}

pub fn unixMicros() Time {
    return Time(.micros).now();
}

pub fn unixNanos() Time {
    return Time(.nanos).now();
}

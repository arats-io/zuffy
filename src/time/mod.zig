pub const Time = @import("time.zig").Time;
pub const Measure = @import("time.zig").Measure;
pub const Month = @import("time.zig").Month;
pub const Weekday = @import("time.zig").Weekday;

pub const zoneinfo = @import("zoneinfo.zig");

pub fn now() Time(.seconds) {
    return Time(.seconds).new();
}

pub fn unixMilli() Time(.millis) {
    return Time(.millis).new();
}

pub fn unixMicros() Time(.micros) {
    return Time(.micros).new();
}

pub fn unixNanos() Time(.nanos) {
    return Time(.nanos).new();
}

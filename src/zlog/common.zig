const std = @import("std");

pub const InternalFailure = enum {
    nothing,
    panic,
    print,
};

pub const TimeFormating = enum(u4) {
    timestamp = 0,
    pattern = 1,
};

pub const Format = enum(u4) {
    simple = 0,
    json = 1,
};

pub const Level = enum(u4) {
    Trace = 0x0,
    Debug = 0x1,
    Info = 0x2,
    Warn = 0x3,
    Error = 0x4,
    Fatal = 0x5,
    Disabled = 0xF,

    pub fn String(self: Level) []const u8 {
        return switch (self) {
            .Trace => "trace",
            .Debug => "debug",
            .Info => "info",
            .Warn => "warn",
            .Error => "error",
            .Fatal => "fatal",
            .Disabled => "disabled",
        };
    }
    pub fn ParseString(val: []const u8) Level {
        var buffer: [8]u8 = undefined;
        const lVal = std.ascii.lowerString(&buffer, val);

        if (std.mem.eql(u8, "trace", lVal)) return .Trace;
        if (std.mem.eql(u8, "debug", lVal)) return .Debug;
        if (std.mem.eql(u8, "info", lVal)) return .Info;
        if (std.mem.eql(u8, "warn", lVal)) return .Warn;
        if (std.mem.eql(u8, "error", lVal)) return .Error;
        if (std.mem.eql(u8, "fatal", lVal)) return .Fatal;
        if (std.mem.eql(u8, "disabled", lVal)) return .Disabled;
        return .Disabled;
    }
};

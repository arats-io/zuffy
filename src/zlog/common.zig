const std = @import("std");

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
            .Trace => "TRACE",
            .Debug => "DEBUG",
            .Info => "INFO",
            .Warn => "WARN",
            .Error => "ERROR",
            .Fatal => "FATAL",
            .Disabled => "DISABLED",
        };
    }
    pub fn ParseString(val: []const u8) !Level {
        var buffer: [50]u8 = undefined;
        const lVal = std.ascii.upperString(&buffer, val);

        if (std.mem.eql(u8, "TRACE", lVal)) return .Trace;
        if (std.mem.eql(u8, "DEBUG", lVal)) return .Debug;
        if (std.mem.eql(u8, "INFO", lVal)) return .Info;
        if (std.mem.eql(u8, "WARN", lVal)) return .Warn;
        if (std.mem.eql(u8, "ERROR", lVal)) return .Error;
        if (std.mem.eql(u8, "FATAL", lVal)) return .Fatal;
        if (std.mem.eql(u8, "DISABLED", lVal)) return .Disabled;
        return .Disabled;
    }
};

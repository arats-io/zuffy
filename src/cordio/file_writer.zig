const std = @import("std");
const builtin = @import("builtin");

const CompressionType = @import("types.zig").Compression;

const Self = @This();

open: bool,
closed: bool,

file: std.io.File,
currentOffset: usize,
compressionType: CompressionType = .none,

const std = @import("std");
const xstd = @import("xstd");

const Allocator = std.mem.Allocator;
const AllocatorError = std.mem.Allocator.Error;

const Error = xstd.bytes.Error;
const Utf8BufferPool = xstd.bytes.Utf8BufferPool;
const Utf8Buffer = xstd.bytes.Utf8Buffer;

const Pool = xstd.Pool;

pub fn NewUtf8Buffer(allocator: std.mem.Allocator) Utf8Buffer {
    return Utf8Buffer.init(allocator);
}

pub fn PrintElement(ch: []const u8) void {
    std.debug.print("{s}", .{ch});
}

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // var utf8BufferPool = Utf8BufferPool(true).init(allocator);
    // var sb = try utf8BufferPool.pop();
    // defer sb.deinit();

    var utf8BufferPool = Pool(Utf8Buffer).initFixed(allocator, NewUtf8Buffer);
    var sb = utf8BufferPool.pop();

    try sb.append("SB------");
    try sb.append("A");
    try sb.append("\u{5360}");
    try sb.append("💯");
    try sb.append("Hell");
    std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

    try sb.appendf("🔥 Hello {s} World 🔥", .{"Ionel"});
    std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

    _ = try sb.replaceFirst("💯", "+++++💯+++++");
    std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });
    _ = try sb.replaceFirst("+++++💯+++++", "💯");
    std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });
    _ = try sb.replaceFirst("💯", "");
    std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

    try sb.insertAt("🔥", 1);
    std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

    _ = try sb.replaceLast("🔥", "§");
    std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

    _ = try sb.removeAll("🔥");
    std.debug.print("[{s}] --- from {any}\n", .{ sb.bytes(), @intFromPtr(&sb) });

    try utf8BufferPool.push(&sb);

    var sb10 = utf8BufferPool.pop();
    try sb10.append("-Second Round SB");
    std.debug.print("[{s}] --- from {any}\n", .{ sb10.bytes(), @intFromPtr(&sb10) });

    var sb2 = utf8BufferPool.pop();
    try sb2.append("SB2------");
    try sb2.append("💯");
    std.debug.print("[{s}] --- from {any}\n", .{ sb2.bytes(), @intFromPtr(&sb2) });

    try utf8BufferPool.push(&sb10);
    try utf8BufferPool.push(&sb2);

    var sb21 = utf8BufferPool.pop();
    try sb21.append("Finally");
    std.debug.print("[{s}] --- from {any}\n", .{ sb21.bytes(), @intFromPtr(&sb21) });

    var sb11 = utf8BufferPool.pop();
    try sb11.append("Finally");
    std.debug.print("[{s}] --- from {any}\n", .{ sb11.bytes(), @intFromPtr(&sb11) });

    try utf8BufferPool.push(&sb11);
    try utf8BufferPool.push(&sb21);

    var sb12 = utf8BufferPool.pop();
    try sb12.append("Finally2");
    std.debug.print("[{s}] --- from {any}\n", .{ sb12.bytes(), @intFromPtr(&sb12) });

    var sb22 = utf8BufferPool.pop();
    try sb22.append("Finally2");
    std.debug.print("[{s}] --- from {any}\n", .{ sb22.bytes(), @intFromPtr(&sb22) });

    var sb3 = utf8BufferPool.pop();
    try sb3.append("SB3------");
    try sb3.append("New Finally");
    std.debug.print("[{s}] --- from {any}\n", .{ sb3.bytes(), @intFromPtr(&sb3) });

    try utf8BufferPool.push(&sb12);
    try utf8BufferPool.push(&sb22);
    try utf8BufferPool.push(&sb3);
    try utf8BufferPool.push(&sb3);

    std.debug.print("=============================\n", .{});
    var sb31 = utf8BufferPool.pop();
    std.debug.print("[{s}] --- from {any}\n", .{ sb31.bytes(), @intFromPtr(&sb31) });
    var sb32 = utf8BufferPool.pop();
    std.debug.print("[{s}] --- from {any}\n", .{ sb32.bytes(), @intFromPtr(&sb32) });
    var sb23 = utf8BufferPool.pop();
    std.debug.print("[{s}] --- from {any}\n", .{ sb23.bytes(), @intFromPtr(&sb23) });

    var sb24 = utf8BufferPool.pop();
    std.debug.print("[{s}] --- from {any}\n", .{ sb24.bytes(), @intFromPtr(&sb24) });

    var sb4 = utf8BufferPool.pop();
    std.debug.print("--- [{s}] --- from {any}\n", .{ sb4.bytes(), @intFromPtr(&sb4) });
}

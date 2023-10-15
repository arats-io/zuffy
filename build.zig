const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // create a module to be used internally.
    _ = b.addModule("xstd", .{
        .source_file = .{ .path = "src/lib.zig" },
    });

    const lib = b.addStaticLibrary(.{
        .name = "xstd",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    var tests_suite = b.step("test-suite", "Run unit tests");
    {
        var dir = try std.fs.cwd().openDir(".", .{});

        const walker = try dir.openIterableDir("src", .{ .access_sub_paths = true });
        var iter = try walker.walk(b.allocator);

        const allowed_exts = [_][]const u8{".zig"};
        while (try iter.next()) |entry| {
            const ext = std.fs.path.extension(entry.basename);
            const include_file = for (allowed_exts) |e| {
                if (std.mem.eql(u8, ext, e))
                    break true;
            } else false;
            if (include_file) {
                // we have to clone the path as walker.next() or walker.deinit() will override/kill it

                var buff: [1024]u8 = undefined;
                const testPath = try std.fmt.bufPrint(&buff, "src/{s}", .{entry.path});
                //std.debug.print("Testing: {s}\n", .{testPath});

                tests_suite.dependOn(&b.addRunArtifact(b.addTest(.{
                    .root_source_file = .{ .path = testPath },
                    .target = target,
                    .optimize = optimize,
                })).step);
            }
        }
    }
}

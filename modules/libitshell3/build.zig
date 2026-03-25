const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- ghostty dependency (vendored) ---
    const ghostty_dep = b.dependency("ghostty", .{
        .target = target,
        .optimize = optimize,
        .@"emit-lib-vt" = true,
    });
    const ghostty_vt = ghostty_dep.module("ghostty-vt");

    // --- libitshell3 static library ---
    const lib = b.addLibrary(.{
        .name = "itshell3",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "ghostty", .module = ghostty_vt },
            },
        }),
    });
    b.installArtifact(lib);

    // --- Tests ---
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "ghostty", .module = ghostty_vt },
            },
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_tests.step);
}

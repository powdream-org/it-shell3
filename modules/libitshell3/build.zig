const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- ghostty dependency (vendored) ---
    const ghostty_simd = b.option(bool, "ghostty-simd", "Enable ghostty SIMD (disable for kcov)") orelse true;
    const ghostty_dep = b.dependency("ghostty", .{
        .target = target,
        .optimize = optimize,
        .@"version-string" = "1.3.1",
        .simd = ghostty_simd,
    });
    const ghostty_vt = ghostty_dep.module("ghostty-vt");

    // --- Protocol dependency ---
    const protocol_dep = b.dependency("itshell3-protocol", .{
        .target = target,
        .optimize = optimize,
    });
    const protocol_mod = protocol_dep.module("itshell3-protocol");

    // --- Named sub-modules (available via @import in all source files) ---
    const named_imports: []const std.Build.Module.Import = &.{
        .{ .name = "ghostty", .module = ghostty_vt },
        .{ .name = "itshell3_protocol", .module = protocol_mod },
        .{ .name = "itshell3_core", .module = b.createModule(.{
            .root_source_file = b.path("src/core/root.zig"),
            .target = target,
            .optimize = optimize,
        }) },
        .{ .name = "itshell3_os", .module = b.createModule(.{
            .root_source_file = b.path("src/os/root.zig"),
            .target = target,
            .optimize = optimize,
        }) },
    };

    // --- libitshell3 static library ---
    const lib = b.addLibrary(.{
        .name = "itshell3",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = named_imports,
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
            .imports = named_imports,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_tests.step);
}

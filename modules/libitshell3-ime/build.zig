const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libhangul_path = b.path("../../vendors/libhangul");

    // --- libhangul static library (vendored C) ---
    // Use ReleaseSafe for the vendored C library to disable UBSan
    // instrumentation that Zig applies to C code in Debug mode.
    // Zig's UBSan traps interact badly with kcov's ptrace-based
    // breakpoint handling on macOS, causing segfaults.
    const libhangul = b.addLibrary(.{
        .name = "hangul",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = .ReleaseSafe,
            .link_libc = true,
        }),
    });

    libhangul.root_module.addCSourceFiles(.{
        .root = libhangul_path,
        .files = &.{
            "hangul/hangulctype.c",
            "hangul/hangulinputcontext.c",
            "hangul/hangulkeyboard.c",
        },
        .flags = &.{
            "-DENABLE_EXTERNAL_KEYBOARDS=0",
            "-UENABLE_NLS",
            "-D_POSIX_C_SOURCE=200809L",
            "-std=c99",
        },
    });

    // config.h lives in this module's root
    libhangul.root_module.addIncludePath(b.path("."));
    // hangul.h includes via "hangul/hangul.h" from the libhangul root
    libhangul.root_module.addIncludePath(libhangul_path);

    // --- libitshell3-ime Zig library ---
    const lib = b.addLibrary(.{
        .name = "itshell3-ime",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.root_module.linkLibrary(libhangul);
    lib.root_module.addIncludePath(libhangul_path);
    lib.root_module.addIncludePath(b.path("."));
    b.installArtifact(lib);

    // --- Tests ---
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.linkLibrary(libhangul);
    tests.root_module.addIncludePath(libhangul_path);
    tests.root_module.addIncludePath(b.path("."));

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all unit and integration tests");
    test_step.dependOn(&run_tests.step);
}

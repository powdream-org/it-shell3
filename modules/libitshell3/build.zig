const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- External dependencies ---
    const ghostty_simd = b.option(bool, "ghostty-simd", "Enable ghostty SIMD (disable for kcov)") orelse true;
    const ghostty_dep = b.dependency("ghostty", .{
        .target = target,
        .optimize = optimize,
        .@"version-string" = "1.3.1",
        .simd = ghostty_simd,
    });
    const ghostty_vt = ghostty_dep.module("ghostty-vt");

    const protocol_dep = b.dependency("itshell3-protocol", .{
        .target = target,
        .optimize = optimize,
    });
    const protocol_mod = protocol_dep.module("itshell3-protocol");

    const transport_dep = b.dependency("itshell3-transport", .{
        .target = target,
        .optimize = optimize,
    });
    const transport_mod = transport_dep.module("itshell3-transport");

    const ime_dep = b.dependency("itshell3-ime", .{
        .target = target,
        .optimize = optimize,
    });
    const ime_artifact = ime_dep.artifact("itshell3-ime");
    const ime_mod = ime_artifact.root_module;

    // --- Internal named modules ---
    const core_mod = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const server_mod = b.createModule(.{
        .root_source_file = b.path("src/server/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const input_mod = b.createModule(.{
        .root_source_file = b.path("src/input/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const testing_mod = b.createModule(.{
        .root_source_file = b.path("src/testing/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const ghostty_helpers_mod = b.createModule(.{
        .root_source_file = b.path("src/ghostty/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // --- Wire cross-module dependencies ---
    const all_internal = [_]struct { name: []const u8, mod: *std.Build.Module }{
        .{ .name = "itshell3_core", .mod = core_mod },
        .{ .name = "itshell3_server", .mod = server_mod },
        .{ .name = "itshell3_input", .mod = input_mod },
        .{ .name = "itshell3_testing", .mod = testing_mod },
        .{ .name = "itshell3_ghostty", .mod = ghostty_helpers_mod },
    };
    for (all_internal) |entry| {
        for (all_internal) |dep| {
            entry.mod.addImport(dep.name, dep.mod);
        }
        entry.mod.addImport("itshell3_protocol", protocol_mod);
        entry.mod.addImport("itshell3_transport", transport_mod);
        entry.mod.addImport("itshell3_ime", ime_mod);
        entry.mod.addImport("ghostty", ghostty_vt);
    }

    // --- Root module (library) ---
    const root_imports: []const std.Build.Module.Import = &.{
        .{ .name = "ghostty", .module = ghostty_vt },
        .{ .name = "itshell3_protocol", .module = protocol_mod },
        .{ .name = "itshell3_transport", .module = transport_mod },
        .{ .name = "itshell3_ime", .module = ime_mod },
        .{ .name = "itshell3_core", .module = core_mod },
        .{ .name = "itshell3_server", .module = server_mod },
        .{ .name = "itshell3_input", .module = input_mod },
        .{ .name = "itshell3_testing", .module = testing_mod },
        .{ .name = "itshell3_ghostty", .module = ghostty_helpers_mod },
    };
    const lib = b.addLibrary(.{
        .name = "itshell3",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = root_imports,
        }),
    });
    b.installArtifact(lib);

    // --- Per-module test steps ---
    const test_step = b.step("test", "Run all unit tests");

    for (all_internal) |entry| {
        const t = b.addTest(.{ .root_module = entry.mod });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}

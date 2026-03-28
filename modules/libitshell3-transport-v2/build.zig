const std = @import("std");

const TransportSide = enum { server, client, both };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const side = b.option(TransportSide, "transport-side", "Include server, client, or both transport code") orelse .both;

    const root_file = switch (side) {
        .both => b.path("src/root.zig"),
        .server => b.path("src/root_server.zig"),
        .client => b.path("src/root_client.zig"),
    };

    _ = b.addModule("itshell3-transport-v2", .{
        .root_source_file = root_file,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .name = "itshell3-transport-v2",
        .root_module = b.createModule(.{
            .root_source_file = root_file,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(lib);

    // Tests always use the full root (both) regardless of -Dtransport-side.
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_tests.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const debug_build = b.option(bool, "debug", "debug build");
    const exe = b.addExecutable(.{
        .name = "zlox_treewalker",
        .use_llvm = debug_build,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = debug_build,
        }),
    });
    exe.pie = debug_build;

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the compiler");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const test_step = b.step("test", "Run tests");

    b.installArtifact(exe_tests);
    const install_tests_cmd = b.addInstallArtifact(exe_tests, .{});
    const test_cmd = b.addRunArtifact(exe_tests);
    test_step.dependOn(&install_tests_cmd.step);
    test_step.dependOn(&test_cmd.step);
}

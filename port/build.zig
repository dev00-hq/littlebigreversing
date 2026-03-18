const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_mod = b.addModule("lba2", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const app = b.addExecutable(.{
        .name = "lba2",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lba2", .module = root_mod },
            },
        }),
    });
    app.linkLibC();
    app.linkSystemLibrary("SDL2");
    b.installArtifact(app);

    const tool = b.addExecutable(.{
        .name = "lba2-tool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tool_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lba2", .module = root_mod },
            },
        }),
    });
    b.installArtifact(tool);

    const install_app = b.addInstallArtifact(app, .{});
    const install_tool = b.addInstallArtifact(tool, .{});

    const run_step = b.step("run", "Run the SDL smoke app");
    const run_cmd = b.addRunArtifact(app);
    run_cmd.step.dependOn(&install_app.step);
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const tool_step = b.step("tool", "Run the asset CLI");
    const tool_cmd = b.addRunArtifact(tool);
    tool_cmd.step.dependOn(&install_tool.step);
    if (b.args) |args| tool_cmd.addArgs(args);
    tool_step.dependOn(&tool_cmd.step);

    const validate_step = b.step("validate-phase1", "Validate phase 1 outputs");
    const validate_cmd = b.addRunArtifact(tool);
    validate_cmd.step.dependOn(&install_tool.step);
    validate_cmd.addArg("validate-phase1");
    validate_step.dependOn(&validate_cmd.step);

    const tests = b.addTest(.{
        .root_module = root_mod,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run synthetic fixture tests");
    test_step.dependOn(&run_tests.step);
}

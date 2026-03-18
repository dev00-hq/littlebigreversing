const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdl_lib_rel = "../vcpkg_installed/x64-windows/lib/SDL2.lib";
    const sdl_lib_dir_rel = "../vcpkg_installed/x64-windows/lib";
    const sdl_dll_rel = "../vcpkg_installed/x64-windows/bin/SDL2.dll";

    requirePathExists(b, sdl_lib_rel);
    requirePathExists(b, sdl_dll_rel);

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
    app.root_module.addLibraryPath(b.path(sdl_lib_dir_rel));
    app.root_module.linkSystemLibrary("SDL2", .{});
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
    const install_sdl2_dll = b.addInstallBinFile(b.path(sdl_dll_rel), "SDL2.dll");
    b.getInstallStep().dependOn(&install_sdl2_dll.step);

    const run_step = b.step("run", "Run the SDL smoke app");
    const run_cmd = b.addRunArtifact(app);
    run_cmd.step.dependOn(&install_app.step);
    run_cmd.step.dependOn(&install_sdl2_dll.step);
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

fn requirePathExists(b: *std.Build, relative_path: []const u8) void {
    const absolute_path = b.pathFromRoot(relative_path);
    std.fs.cwd().access(absolute_path, .{}) catch {
        std.debug.panic("missing required SDL2 dependency: {s}", .{absolute_path});
    };
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdl_lib_rel = "../vcpkg_installed/x64-windows/lib/SDL2.lib";
    const sdl_lib_dir_rel = "../vcpkg_installed/x64-windows/lib";
    const sdl_dll_rel = "../vcpkg_installed/x64-windows/bin/SDL2.dll";
    const reference_metadata_script = b.pathFromRoot("../tools/generate_reference_metadata.py");
    const reference_metadata_root = b.pathFromRoot("../../lba-reference-repos/metadata");
    const generated_reference_metadata = b.pathFromRoot("src/generated/reference_metadata.zig");

    requirePathExists(b, sdl_lib_rel);
    requirePathExists(b, sdl_dll_rel);

    const app = b.addExecutable(.{
        .name = "lba2",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    app.root_module.addLibraryPath(b.path(sdl_lib_dir_rel));
    app.root_module.linkSystemLibrary("SDL2", .{});
    b.installArtifact(app);

    const tool = b.addExecutable(.{
        .name = "lba2-tool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tool_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(tool);

    const install_app = b.addInstallArtifact(app, .{});
    const install_tool = b.addInstallArtifact(tool, .{});
    const install_sdl2_dll = b.addInstallBinFile(b.path(sdl_dll_rel), "SDL2.dll");
    b.getInstallStep().dependOn(&install_sdl2_dll.step);

    const run_step = b.step("run", "Run the data-backed interior viewer shell");
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

    const stage_viewer_step = b.step("stage-viewer", "Install staged viewer binaries for verification");
    stage_viewer_step.dependOn(&install_app.step);
    stage_viewer_step.dependOn(&install_tool.step);
    stage_viewer_step.dependOn(&install_sdl2_dll.step);

    const verify_reference_metadata_cmd = b.addSystemCommand(&.{
        "py",
        "-3",
        reference_metadata_script,
        "--metadata-root",
        reference_metadata_root,
        "--output",
        generated_reference_metadata,
        "--check",
    });
    const verify_reference_metadata_step = b.step(
        "verify-reference-metadata",
        "Verify that checked-in reference metadata matches the local LBALab metadata clone",
    );
    verify_reference_metadata_step.dependOn(&verify_reference_metadata_cmd.step);

    const regen_reference_metadata_cmd = b.addSystemCommand(&.{
        "py",
        "-3",
        reference_metadata_script,
        "--metadata-root",
        reference_metadata_root,
        "--output",
        generated_reference_metadata,
    });
    const regen_reference_metadata_step = b.step(
        "regen-reference-metadata",
        "Regenerate checked-in reference metadata from the local LBALab metadata clone",
    );
    regen_reference_metadata_step.dependOn(&regen_reference_metadata_cmd.step);

    const test_reference_metadata_generator_cmd = b.addSystemCommand(&.{
        "py",
        "-3",
        b.pathFromRoot("../tools/test_generate_reference_metadata.py"),
    });
    const test_reference_metadata_generator_step = b.step(
        "test-reference-metadata-generator",
        "Run the reference metadata generator unit tests",
    );
    test_reference_metadata_generator_step.dependOn(&test_reference_metadata_generator_cmd.step);

    const test_promotion_packets_cmd = b.addSystemCommand(&.{
        "py",
        "-3",
        b.pathFromRoot("../tools/validate_promotion_packets.py"),
    });
    const test_promotion_packets_step = b.step(
        "test-promotion-packets",
        "Validate canonical runtime/gameplay promotion packets",
    );
    test_promotion_packets_step.dependOn(&test_promotion_packets_cmd.step);

    const fast_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_fast.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_fast_tests = b.addRunArtifact(fast_tests);
    const test_fast_step = b.step("test-fast", "Run the fast parser and runtime regression suite");
    test_fast_step.dependOn(&run_fast_tests.step);

    const cli_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_cli_integration.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_cli_integration_tests = b.addRunArtifact(cli_integration_tests);
    run_cli_integration_tests.step.dependOn(&install_tool.step);
    run_cli_integration_tests.setEnvironmentVariable(
        "LBA2_TOOL_PATH",
        b.getInstallPath(.bin, "lba2-tool.exe"),
    );
    const test_cli_integration_step = b.step("test-cli-integration", "Run the slower asset-backed CLI room/load integration tests");
    test_cli_integration_step.dependOn(&run_cli_integration_tests.step);

    const life_audit_all_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_life_audit_all.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_life_audit_all_tests = b.addRunArtifact(life_audit_all_tests);
    const test_life_audit_all_step = b.step("test-life-audit-all", "Run the slow all-scene life-audit inventory tests");
    test_life_audit_all_step.dependOn(&run_life_audit_all_tests.step);

    const test_step = b.step("test", "Run the full parser and runtime regression suite");
    test_step.dependOn(verify_reference_metadata_step);
    test_step.dependOn(test_reference_metadata_generator_step);
    test_step.dependOn(test_promotion_packets_step);
    test_step.dependOn(test_fast_step);
    test_step.dependOn(test_cli_integration_step);
    test_step.dependOn(test_life_audit_all_step);
}

fn requirePathExists(b: *std.Build, relative_path: []const u8) void {
    const absolute_path = b.pathFromRoot(relative_path);
    std.Io.Dir.accessAbsolute(b.graph.io, absolute_path, .{}) catch {
        std.debug.panic("missing required SDL2 dependency: {s}", .{absolute_path});
    };
}

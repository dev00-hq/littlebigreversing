const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const life_audit = @import("../game_data/scene/life_audit.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const scene_data = @import("../game_data/scene.zig");
const room_state = @import("../runtime/room_state.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");

var tool_build_lock: std.Thread.Mutex = .{};
var tool_build_attempted = false;
var tool_build_error: ?anyerror = null;

fn ensureToolBuilt(allocator: std.mem.Allocator, repo_root: []const u8) !void {
    tool_build_lock.lock();
    defer tool_build_lock.unlock();

    if (tool_build_attempted) {
        if (tool_build_error) |err| return err;
        return;
    }

    tool_build_attempted = true;
    const build_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "py",
            "-3",
            ".\\scripts\\dev-shell.py",
            "exec",
            "--cwd",
            "port",
            "--",
            "zig",
            "build",
        },
        .cwd = repo_root,
        .max_output_bytes = 8 * 1024 * 1024,
    }) catch |err| {
        tool_build_error = err;
        return err;
    };
    defer allocator.free(build_result.stdout);
    defer allocator.free(build_result.stderr);

    switch (build_result.term) {
        .Exited => |code| {
            if (code == 0) return;
        },
        else => {},
    }

    tool_build_error = error.ToolBuildFailed;
    return error.ToolBuildFailed;
}

fn runToolCommandAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    tool_args: []const []const u8,
) !std.process.Child.RunResult {
    try ensureToolBuilt(allocator, repo_root);

    const tool_path = try std.fs.path.join(allocator, &.{ repo_root, "port", "zig-out", "bin", "lba2-tool.exe" });
    defer allocator.free(tool_path);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, tool_path);
    try argv.appendSlice(allocator, tool_args);

    return std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
        .cwd = repo_root,
        .max_output_bytes = 8 * 1024 * 1024,
    });
}

fn runToolCommandToFileAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    tool_args: []const []const u8,
) !struct {
    result: std.process.Child.RunResult,
    output_path: []u8,
    output_bytes: []u8,
} {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();

    const tmp_root = try tmp.dir.realpathAlloc(allocator, ".");
    errdefer allocator.free(tmp_root);
    const output_path = try std.fs.path.join(allocator, &.{ tmp_root, "room-intelligence.json" });
    errdefer allocator.free(output_path);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, tool_args);
    try argv.appendSlice(allocator, &.{ "--out", output_path });

    const result = try runToolCommandAlloc(allocator, repo_root, argv.items);
    errdefer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    var output_file = try std.fs.openFileAbsolute(output_path, .{});
    defer output_file.close();
    const output_bytes = try output_file.readToEndAlloc(allocator, 8 * 1024 * 1024);
    errdefer allocator.free(output_bytes);

    tmp.cleanup();
    allocator.free(tmp_root);

    return .{
        .result = result,
        .output_path = output_path,
        .output_bytes = output_bytes,
    };
}

fn expectExited(term: std.process.Child.Term, code: u8) !void {
    switch (term) {
        .Exited => |actual| try std.testing.expectEqual(code, actual),
        else => return error.UnexpectedChildTermination,
    }
}

fn requireJsonField(value: std.json.Value, field: []const u8) !std.json.Value {
    return switch (value) {
        .object => |object| object.get(field) orelse error.MissingJsonField,
        else => error.ExpectedJsonObject,
    };
}

fn requireJsonArrayItem(value: std.json.Value, index: usize) !std.json.Value {
    return switch (value) {
        .array => |array| if (index < array.items.len) array.items[index] else error.ArrayIndexOutOfRange,
        else => error.ExpectedJsonArray,
    };
}

fn expectJsonString(value: std.json.Value, expected: []const u8) !void {
    switch (value) {
        .string => |actual| try std.testing.expectEqualStrings(expected, actual),
        else => return error.ExpectedJsonString,
    }
}

fn expectJsonInteger(value: std.json.Value, expected: i64) !void {
    switch (value) {
        .integer => |actual| try std.testing.expectEqual(expected, actual),
        else => return error.ExpectedJsonInteger,
    }
}

fn expectJsonBool(value: std.json.Value, expected: bool) !void {
    switch (value) {
        .bool => |actual| try std.testing.expectEqual(expected, actual),
        else => return error.ExpectedJsonBool,
    }
}

fn expectJsonNull(value: std.json.Value) !void {
    switch (value) {
        .null => {},
        else => return error.ExpectedJsonNull,
    }
}

fn expectJsonFieldAbsent(value: std.json.Value, field: []const u8) !void {
    switch (value) {
        .object => |object| try std.testing.expect(object.get(field) == null),
        else => return error.ExpectedJsonObject,
    }
}

fn findInstructionByMnemonic(instructions: std.json.Value, mnemonic: []const u8) !std.json.Value {
    return switch (instructions) {
        .array => |array| blk: {
            for (array.items) |instruction| {
                const actual = try requireJsonField(instruction, "mnemonic");
                switch (actual) {
                    .string => |value| {
                        if (std.mem.eql(u8, value, mnemonic)) break :blk instruction;
                    },
                    else => return error.ExpectedJsonString,
                }
            }
            return error.MissingJsonInstruction;
        },
        else => error.ExpectedJsonArray,
    };
}

test "inspect-room widened guarded admissions stay covered outside the fast shard" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const guarded_22 = try room_fixtures.guarded22();
    try std.testing.expectEqual(@as(usize, 2), guarded_22.scene.entry_index);
    try std.testing.expectEqualStrings("interior", guarded_22.scene.scene_kind);
    try std.testing.expectEqual(@as(usize, 2), guarded_22.background.entry_index);

    const guarded_1110 = try room_fixtures.guarded1110();
    try std.testing.expectEqual(@as(usize, 11), guarded_1110.scene.entry_index);
    try std.testing.expectEqualStrings("interior", guarded_1110.scene.scene_kind);
    try std.testing.expectEqual(@as(usize, 10), guarded_1110.background.entry_index);

    try std.testing.expectError(
        error.ViewerSceneMustBeInterior,
        room_state.loadRoomSnapshot(allocator, resolved, 44, 2),
    );
}

test "inspect-room-intelligence subprocess emits machine-facing JSON for the canonical 2/2 pair" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "2",
        "--background-entry",
        "2",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "command"), "inspect-room-intelligence");

    const selection = try requireJsonField(root, "selection");
    const selected_scene = try requireJsonField(selection, "scene");
    try expectJsonString(try requireJsonField(selected_scene, "metadata_source"), "port/src/generated/room_metadata.zig");
    try expectJsonString(try requireJsonField(selected_scene, "selector_kind"), "entry");
    try expectJsonInteger(try requireJsonField(selected_scene, "resolved_entry_index"), 2);
    const selected_background = try requireJsonField(selection, "background");
    try expectJsonString(try requireJsonField(selected_background, "metadata_source"), "port/src/generated/room_metadata.zig");
    try expectJsonString(try requireJsonField(selected_background, "selector_kind"), "entry");
    try expectJsonInteger(try requireJsonField(selected_background, "resolved_entry_index"), 2);
    try expectJsonString(try requireJsonField(selected_background, "resolved_friendly_name"), "Grid 0: Citadel Island, Twinsen's house");

    const scene = try requireJsonField(root, "scene");
    const counts = try requireJsonField(scene, "counts");
    try expectJsonInteger(try requireJsonField(counts, "decoded_actor_count"), 8);
    try expectJsonInteger(try requireJsonField(counts, "header_object_count"), 9);
    try expectJsonBool(try requireJsonField(counts, "header_object_count_includes_hero"), true);
    try expectJsonBool(try requireJsonField(counts, "decoded_actor_count_matches_header_minus_hero"), true);
    try expectJsonInteger(try requireJsonField(try requireJsonField(scene, "header"), "object_count"), 9);

    const background = try requireJsonField(root, "background");
    try expectJsonInteger(try requireJsonField(background, "entry_index"), 2);
    const composition = try requireJsonField(background, "composition");
    try expectJsonInteger(try requireJsonField(composition, "width"), 64);
    try expectJsonInteger(try requireJsonField(composition, "depth"), 64);

    const validation = try requireJsonField(root, "validation");
    try expectJsonBool(try requireJsonField(validation, "viewer_loadable"), true);
    try expectJsonString(try requireJsonField(try requireJsonField(validation, "scene_life"), "status"), "decoded");
    try expectJsonString(try requireJsonField(try requireJsonField(validation, "fragment_zones"), "status"), "compatible");

    const actors = try requireJsonField(root, "actors");
    const first_actor = try requireJsonArrayItem(actors, 0);
    try expectJsonInteger(try requireJsonField(first_actor, "scene_object_index"), 1);
    try expectJsonInteger(try requireJsonField(first_actor, "array_index"), 0);

    const hero_life = try requireJsonField(try requireJsonField(scene, "hero_start"), "life");
    const hero_instructions = try requireJsonField(hero_life, "instructions");
    const first_instruction = try requireJsonArrayItem(hero_instructions, 0);
    try expectJsonString(try requireJsonField(first_instruction, "mnemonic"), "LM_AND_IF");
    const operands = try requireJsonField(first_instruction, "operands");
    try expectJsonString(try requireJsonField(operands, "kind"), "condition");
    const condition = try requireJsonField(operands, "value");
    try expectJsonString(try requireJsonField(try requireJsonField(condition, "function"), "mnemonic"), "LF_VAR_GAME");
    try expectJsonString(try requireJsonField(try requireJsonField(condition, "comparison"), "mnemonic"), "LT_SUP");

    const switch_instruction = try findInstructionByMnemonic(hero_instructions, "LM_SWITCH");
    try expectJsonString(try requireJsonField(switch_instruction, "mnemonic"), "LM_SWITCH");
    const switch_operands = try requireJsonField(switch_instruction, "operands");
    try expectJsonString(try requireJsonField(switch_operands, "kind"), "switch_expr");
    try expectJsonString(
        try requireJsonField(try requireJsonField(try requireJsonField(switch_operands, "value"), "function"), "mnemonic"),
        "LF_ZONE",
    );

    const case_instruction = try findInstructionByMnemonic(hero_instructions, "LM_CASE");
    try expectJsonString(try requireJsonField(case_instruction, "mnemonic"), "LM_CASE");
    const case_operands = try requireJsonField(case_instruction, "operands");
    try expectJsonString(try requireJsonField(case_operands, "kind"), "case_branch");
    try expectJsonString(
        try requireJsonField(try requireJsonField(try requireJsonField(case_operands, "value"), "switch_return_type"), "mnemonic"),
        "RET_S8",
    );
    try expectJsonString(
        try requireJsonField(try requireJsonField(try requireJsonField(try requireJsonField(case_operands, "value"), "comparison"), "literal"), "kind"),
        "s8_value",
    );

    switch (hero_instructions) {
        .array => |array| try std.testing.expectEqual(@as(usize, 47), array.items.len),
        else => return error.ExpectedJsonArray,
    }
    try expectJsonInteger(try requireJsonField(try requireJsonField(hero_life, "audit"), "instruction_count"), 47);
}

test "inspect-room-intelligence subprocess keeps validation failures in JSON for non-interior rooms" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "44",
        "--background-entry",
        "2",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const validation = try requireJsonField(root, "validation");
    try expectJsonBool(try requireJsonField(validation, "viewer_loadable"), false);
    try expectJsonString(try requireJsonField(try requireJsonField(validation, "scene_kind"), "status"), "non_interior");
    const fragment_zones = try requireJsonField(validation, "fragment_zones");
    try expectJsonString(try requireJsonField(fragment_zones, "status"), "skipped");
    try expectJsonString(try requireJsonField(fragment_zones, "skipped_reason"), "scene_must_be_interior");
    try expectJsonFieldAbsent(root, "fragment_zone_layout");

    const hero_instructions = try requireJsonField(try requireJsonField(try requireJsonField(root, "scene"), "hero_start"), "life");
    const hero_life_instructions = try requireJsonField(hero_instructions, "instructions");
    const switch_instruction = try findInstructionByMnemonic(hero_life_instructions, "LM_SWITCH");
    try expectJsonString(try requireJsonField(switch_instruction, "mnemonic"), "LM_SWITCH");
    try expectJsonString(try requireJsonField(try requireJsonField(switch_instruction, "operands"), "kind"), "switch_expr");
    const case_instruction = try findInstructionByMnemonic(hero_life_instructions, "LM_CASE");
    try expectJsonString(try requireJsonField(case_instruction, "mnemonic"), "LM_CASE");
    try expectJsonString(try requireJsonField(try requireJsonField(case_instruction, "operands"), "kind"), "case_branch");
}

test "inspect-room-intelligence subprocess reports unknown numeric scene selectors early" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "9999",
        "--background-entry",
        "2",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 1);
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "status"), "error");
    const error_payload = try requireJsonField(root, "error");
    try expectJsonString(try requireJsonField(error_payload, "phase"), "scene_load");
    try expectJsonString(try requireJsonField(error_payload, "kind"), "UnknownSceneEntryIndex");
    try expectJsonString(try requireJsonField(error_payload, "target"), "scene");
}

test "inspect-room-intelligence subprocess reports unknown numeric background selectors early" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "2",
        "--background-entry",
        "9999",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 1);
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "status"), "error");
    const error_payload = try requireJsonField(root, "error");
    try expectJsonString(try requireJsonField(error_payload, "phase"), "background_load");
    try expectJsonString(try requireJsonField(error_payload, "kind"), "UnknownBackgroundEntryIndex");
    try expectJsonString(try requireJsonField(error_payload, "target"), "background");
}

test "inspect-room-intelligence subprocess reports unknown name selectors as machine-facing JSON" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-name",
        "Does Not Exist",
        "--background-entry",
        "2",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 1);
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "status"), "error");
    const error_payload = try requireJsonField(root, "error");
    try expectJsonString(try requireJsonField(error_payload, "phase"), "scene_selection");
    try expectJsonString(try requireJsonField(error_payload, "kind"), "UnknownSceneName");
    try expectJsonString(try requireJsonField(error_payload, "target"), "scene");
}

test "inspect-room-intelligence subprocess keeps invalid option shapes in machine-facing JSON" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "2",
        "--background-entry",
        "2",
        "--json",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 1);
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "status"), "error");
    const selection = try requireJsonField(root, "selection");
    try expectJsonInteger(try requireJsonField(try requireJsonField(selection, "scene"), "requested_entry_index"), 2);
    try expectJsonInteger(try requireJsonField(try requireJsonField(selection, "background"), "requested_entry_index"), 2);
    const error_payload = try requireJsonField(root, "error");
    try expectJsonString(try requireJsonField(error_payload, "phase"), "parse");
    try expectJsonString(try requireJsonField(error_payload, "kind"), "UnknownOption");
    try expectJsonString(try requireJsonField(error_payload, "target"), "command");
}

test "inspect-room-intelligence subprocess supports --out without changing the JSON payload" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const output = try runToolCommandToFileAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "2",
        "--background-entry",
        "2",
    });
    defer allocator.free(output.result.stdout);
    defer allocator.free(output.result.stderr);
    defer allocator.free(output.output_path);
    defer allocator.free(output.output_bytes);

    try expectExited(output.result.term, 0);
    try std.testing.expectEqual(@as(usize, 0), output.result.stdout.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.output_bytes, .{});
    defer parsed.deinit();
    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "command"), "inspect-room-intelligence");
    try expectJsonBool(try requireJsonField(try requireJsonField(root, "validation"), "viewer_loadable"), true);
}

test "inspect-room-intelligence subprocess includes runtime composition and fragment-zone layout for 11/10" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const output = try runToolCommandToFileAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "11",
        "--background-entry",
        "10",
    });
    defer allocator.free(output.result.stdout);
    defer allocator.free(output.result.stderr);
    defer allocator.free(output.output_path);
    defer allocator.free(output.output_bytes);

    try expectExited(output.result.term, 0);
    try std.testing.expectEqual(@as(usize, 0), output.result.stdout.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.output_bytes, .{});
    defer parsed.deinit();
    const root = parsed.value;
    try expectJsonBool(try requireJsonField(try requireJsonField(root, "validation"), "viewer_loadable"), true);
    const background = try requireJsonField(root, "background");
    const composition = try requireJsonField(background, "composition");
    const tiles = try requireJsonField(composition, "tiles");
    switch (tiles) {
        .array => |array| try std.testing.expect(array.items.len != 0),
        else => return error.ExpectedJsonArray,
    }
    const height_grid = try requireJsonField(composition, "height_grid");
    switch (height_grid) {
        .array => |array| try std.testing.expect(array.items.len != 0),
        else => return error.ExpectedJsonArray,
    }
    const fragment_zone_layout = try requireJsonField(root, "fragment_zone_layout");
    const first_zone = try requireJsonArrayItem(fragment_zone_layout, 0);
    try expectJsonInteger(try requireJsonField(first_zone, "zone_num"), 0);
    try expectJsonInteger(try requireJsonField(first_zone, "fragment_entry_index"), 149);
    const cells = try requireJsonField(first_zone, "cells");
    switch (cells) {
        .array => |array| try std.testing.expect(array.items.len != 0),
        else => return error.ExpectedJsonArray,
    }
}

test "inspect-room-intelligence keeps archive-metadata gaps explicit without failing the payload" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "219",
        "--background-entry",
        "219",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    const background_selection = try requireJsonField(try requireJsonField(root, "selection"), "background");
    try expectJsonInteger(try requireJsonField(background_selection, "resolved_entry_index"), 219);
    try expectJsonNull(try requireJsonField(background_selection, "resolved_friendly_name"));
    try expectJsonString(
        try requireJsonField(try requireJsonField(try requireJsonField(root, "validation"), "fragment_zones"), "status"),
        "invalid_bounds",
    );
}

test "inspect-room-intelligence emits machine-facing JSON for malformed archives" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const scene_source = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(scene_source);
    const scene_bytes = try std.fs.cwd().readFileAlloc(allocator, scene_source, 64 * 1024 * 1024);
    defer allocator.free(scene_bytes);

    try tmp.dir.writeFile(.{
        .sub_path = "SCENE.HQR",
        .data = scene_bytes[0 .. scene_bytes.len - 1],
    });

    const background_source = try std.fs.path.join(allocator, &.{ resolved.asset_root, "LBA_BKG.HQR" });
    defer allocator.free(background_source);
    try std.fs.cwd().copyFile(
        background_source,
        tmp.dir,
        "LBA_BKG.HQR",
        .{},
    );

    const temp_asset_root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(temp_asset_root);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "--asset-root",
        temp_asset_root,
        "inspect-room-intelligence",
        "--scene-entry",
        "2",
        "--background-entry",
        "2",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 1);
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "status"), "error");
    const error_payload = try requireJsonField(root, "error");
    try expectJsonString(try requireJsonField(error_payload, "phase"), "scene_load");
    try expectJsonString(try requireJsonField(error_payload, "kind"), "InvalidArchiveOffset");
    try expectJsonString(try requireJsonField(error_payload, "target"), "scene");
}

test "inspect-room-intelligence hero and first actor life sections match direct life audits for 2/2" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const scene_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(scene_path);
    const scene = try scene_data.loadSceneMetadata(allocator, scene_path, 2);
    defer scene.deinit(allocator);

    const hero_audit = try life_audit.inspectSceneLifeProgram(allocator, scene_path, 2, .{ .hero = {} });
    const first_actor_audit = try life_audit.inspectSceneLifeProgram(allocator, scene_path, 2, .{ .object = 1 });
    const hero_instructions = try life_program.decodeLifeProgram(allocator, scene.hero_start.life.bytes);
    defer allocator.free(hero_instructions);
    const first_actor_instructions = try life_program.decodeLifeProgram(allocator, scene.objects[0].life.bytes);
    defer allocator.free(first_actor_instructions);

    try std.testing.expectEqual(@as(usize, 203), scene.hero_start.life.bytes.len);
    try std.testing.expectEqual(scene.hero_start.life.bytes.len, hero_audit.life_byte_length);
    try std.testing.expectEqual(hero_audit.instruction_count, 47);
    try std.testing.expect(hero_audit.status == .decoded);
    try std.testing.expectEqual(hero_audit.instruction_count, hero_instructions.len);
    try std.testing.expectEqual(life_program.LifeOpcode.LM_AND_IF, hero_instructions[0].opcode);

    try std.testing.expectEqual(@as(usize, 8), scene.objects.len);
    try std.testing.expectEqual(@as(usize, 1), scene.objects[0].index);
    try std.testing.expectEqual(scene.objects[0].life.bytes.len, first_actor_audit.life_byte_length);
    try std.testing.expectEqual(scene.objects[0].track.bytes.len, 1);
    try std.testing.expectEqual(first_actor_audit.instruction_count, 1);
    try std.testing.expect(first_actor_audit.status == .decoded);
    try std.testing.expectEqual(first_actor_audit.instruction_count, first_actor_instructions.len);
    try std.testing.expectEqual(life_program.LifeOpcode.LM_END, first_actor_instructions[0].opcode);
    try std.testing.expectEqual(scene.objects.len + 1, scene.object_count);
}

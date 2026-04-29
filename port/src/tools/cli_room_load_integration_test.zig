const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const process = @import("../foundation/process.zig");
const life_audit = @import("../game_data/scene/life_audit.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const scene_data = @import("../game_data/scene.zig");
const room_state = @import("../runtime/room_state.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");

fn tempDirAbsolutePathAlloc(allocator: std.mem.Allocator, tmp: *const std.testing.TmpDir, sub_path: []const u8) ![]u8 {
    const cwd = try process.currentPathAlloc(allocator);
    defer allocator.free(cwd);
    return std.fs.path.join(allocator, &.{ cwd, ".zig-cache", "tmp", &tmp.sub_path, sub_path });
}

fn requireToolPathAlloc(allocator: std.mem.Allocator) ![]u8 {
    return std.process.Environ.getAlloc(.{ .block = .global }, allocator, "LBA2_TOOL_PATH") catch |err| switch (err) {
        error.EnvironmentVariableMissing => error.MissingToolPath,
        else => err,
    };
}

fn runToolCommandAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    tool_args: []const []const u8,
) !std.process.RunResult {
    const tool_path = try requireToolPathAlloc(allocator);
    defer allocator.free(tool_path);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, tool_path);
    try argv.appendSlice(allocator, tool_args);

    return std.process.run(allocator, std.testing.io, .{
        .argv = argv.items,
        .cwd = .{ .path = repo_root },
        .stdout_limit = .limited(8 * 1024 * 1024),
        .stderr_limit = .limited(8 * 1024 * 1024),
    });
}

fn runToolCommandToFileAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    tool_args: []const []const u8,
) !struct {
    result: std.process.RunResult,
    output_path: []u8,
    output_bytes: []u8,
} {
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();

    const tmp_root = try tempDirAbsolutePathAlloc(allocator, &tmp, ".");
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

    const output_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        output_path,
        allocator,
        .limited(8 * 1024 * 1024),
    );
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
        .exited => |actual| try std.testing.expectEqual(code, actual),
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

fn jsonInteger(value: std.json.Value) !i64 {
    return switch (value) {
        .integer => |actual| actual,
        else => error.ExpectedJsonInteger,
    };
}

fn expectJsonPointMatchesFixture(actual: std.json.Value, fixture_point: std.json.Value) !void {
    try expectJsonInteger(
        try requireJsonField(actual, "x"),
        try jsonInteger(try requireJsonField(fixture_point, "x")),
    );
    try expectJsonInteger(
        try requireJsonField(actual, "y"),
        try jsonInteger(try requireJsonField(fixture_point, "y")),
    );
    try expectJsonInteger(
        try requireJsonField(actual, "z"),
        try jsonInteger(try requireJsonField(fixture_point, "z")),
    );
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
    try std.testing.expectEqual(@as(usize, 1), guarded_1110.background.fragments.fragment_count);

    const guarded_187187 = try room_fixtures.guarded187187();
    try std.testing.expectEqual(@as(usize, 187), guarded_187187.scene.entry_index);
    try std.testing.expectEqualStrings("interior", guarded_187187.scene.scene_kind);
    try std.testing.expectEqual(@as(usize, 187), guarded_187187.background.entry_index);
    try std.testing.expectEqual(@as(usize, 2), guarded_187187.background.fragments.fragment_count);
    try std.testing.expectEqual(@as(usize, 2), guarded_187187.fragment_zones.len);

    try std.testing.expectError(
        error.ViewerSceneMustBeInterior,
        room_state.loadRoomSnapshot(allocator, resolved, 44, 2),
    );
}

test "inspect-room subprocess emits machine-facing JSON for the bounded Sendell 36/36 pair" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room",
        "36",
        "36",
        "--json",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "command"), "inspect-room");

    const scene = try requireJsonField(root, "scene");
    try expectJsonInteger(try requireJsonField(scene, "entry_index"), 36);
    try expectJsonInteger(try requireJsonField(scene, "classic_loader_scene_number"), 34);
    try expectJsonString(try requireJsonField(scene, "scene_kind"), "interior");
    try expectJsonInteger(try requireJsonField(scene, "object_count"), 6);
    try expectJsonInteger(try requireJsonField(scene, "zone_count"), 6);

    const background = try requireJsonField(root, "background");
    try expectJsonInteger(try requireJsonField(background, "entry_index"), 36);
    try expectJsonInteger(
        try requireJsonField(try requireJsonField(background, "fragments"), "fragment_count"),
        0,
    );
    try expectJsonInteger(
        try requireJsonField(try requireJsonField(background, "linkage"), "grm_entry_index"),
        151,
    );
    try expectJsonInteger(
        try requireJsonField(try requireJsonField(background, "bricks"), "preview_count"),
        62,
    );
}

test "inspect-hqr subprocess enriches BODY.HQR json entries with metadata overlays" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-hqr",
        "BODY.HQR",
        "--json",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "asset_path"), "BODY.HQR");
    try expectJsonInteger(try requireJsonField(root, "entry_count"), 469);
    const entries = try requireJsonField(root, "entries");
    const first_entry = try requireJsonArrayItem(entries, 0);
    try expectJsonInteger(try requireJsonField(first_entry, "index"), 1);
    try expectJsonString(try requireJsonField(first_entry, "entry_type"), "mesh");
    try expectJsonString(try requireJsonField(first_entry, "entry_description"), "Twinsen without tunic model");
}

test "inspect-hqr subprocess normalizes EN_GAM voices onto shared VOX metadata" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-hqr",
        "VOX/EN_GAM.VOX",
        "--json",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "asset_path"), "VOX/EN_GAM.VOX");
    const entries = try requireJsonField(root, "entries");
    const first_entry = try requireJsonArrayItem(entries, 0);
    try expectJsonInteger(try requireJsonField(first_entry, "index"), 1);
    try expectJsonString(try requireJsonField(first_entry, "entry_type"), "wave_audio");
    try expectJsonString(try requireJsonField(first_entry, "entry_description"), "Voice for Holomap");

    const ninth_entry = try requireJsonArrayItem(entries, 8);
    try expectJsonNull(try requireJsonField(ninth_entry, "entry_type"));
    try expectJsonNull(try requireJsonField(ninth_entry, "entry_description"));
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
    try expectJsonFieldAbsent(root, "scripts");
    try expectJsonInteger(try requireJsonField(scene, "entry_index"), 2);
    try expectJsonInteger(try requireJsonField(scene, "classic_loader_scene_number"), 0);
    try expectJsonFieldAbsent(scene, "scripts");
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

    const decoded_scene_zones = try requireJsonField(root, "zones");
    switch (decoded_scene_zones) {
        .array => |array| try std.testing.expectEqual(@as(usize, 10), array.items.len),
        else => return error.ExpectedJsonArray,
    }
    const first_decoded_zone = try requireJsonArrayItem(decoded_scene_zones, 0);
    try expectJsonFieldAbsent(first_decoded_zone, "cells");

    const decoded_scene_tracks = try requireJsonField(root, "tracks");
    switch (decoded_scene_tracks) {
        .array => |array| try std.testing.expectEqual(@as(usize, 4), array.items.len),
        else => return error.ExpectedJsonArray,
    }
    const fragment_zone_layout = try requireJsonField(root, "fragment_zone_layout");
    switch (fragment_zone_layout) {
        .array => |array| try std.testing.expectEqual(@as(usize, 0), array.items.len),
        else => return error.ExpectedJsonArray,
    }

    const validation = try requireJsonField(root, "validation");
    try expectJsonBool(try requireJsonField(validation, "viewer_loadable"), true);
    try expectJsonString(try requireJsonField(try requireJsonField(validation, "scene_life"), "status"), "decoded");
    try expectJsonString(try requireJsonField(try requireJsonField(validation, "fragment_zones"), "status"), "compatible");

    const actors = try requireJsonField(root, "actors");
    const first_actor = try requireJsonArrayItem(actors, 0);
    try expectJsonInteger(try requireJsonField(first_actor, "scene_object_index"), 1);
    try expectJsonInteger(try requireJsonField(first_actor, "array_index"), 0);
    try expectJsonFieldAbsent(first_actor, "script");

    _ = try requireJsonField(try requireJsonField(scene, "hero_start"), "track");
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

test "inspect-room-intelligence keeps guarded 2/2 change-cube semantics machine-facing" {
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

    const zones = try requireJsonField(parsed.value, "zones");
    const change_cube_zone = switch (zones) {
        .array => |array| blk: {
            for (array.items) |zone| {
                const semantics = try requireJsonField(zone, "semantics");
                const kind = try requireJsonField(semantics, "kind");
                switch (kind) {
                    .string => |value| {
                        if (std.mem.eql(u8, value, "change_cube")) break :blk zone;
                    },
                    else => return error.ExpectedJsonString,
                }
            }
            return error.MissingJsonField;
        },
        else => return error.ExpectedJsonArray,
    };

    try expectJsonString(try requireJsonField(change_cube_zone, "zone_type"), "change_cube");
    const semantics = try requireJsonField(change_cube_zone, "semantics");
    try expectJsonString(try requireJsonField(semantics, "kind"), "change_cube");
    try expectJsonInteger(try requireJsonField(semantics, "destination_cube"), 0);
    try expectJsonInteger(try requireJsonField(semantics, "destination_x"), 2560);
    try expectJsonInteger(try requireJsonField(semantics, "destination_y"), 2048);
    try expectJsonInteger(try requireJsonField(semantics, "destination_z"), 3072);
    try expectJsonInteger(try requireJsonField(semantics, "yaw"), 0);
    try expectJsonBool(try requireJsonField(semantics, "test_brick"), false);
    try expectJsonBool(try requireJsonField(semantics, "dont_readjust_twinsen"), false);
    try expectJsonBool(try requireJsonField(semantics, "initially_on"), true);
}

test "inspect-room-intelligence keeps the guarded 2/2 public door as the only enabled cube-0 change-cube seam" {
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

    const zones = try requireJsonField(parsed.value, "zones");
    const matching_zone = switch (zones) {
        .array => |array| blk: {
            var found: ?std.json.Value = null;
            var count: usize = 0;
            for (array.items) |zone| {
                const zone_type = try requireJsonField(zone, "zone_type");
                switch (zone_type) {
                    .string => |value| if (!std.mem.eql(u8, value, "change_cube")) continue,
                    else => return error.ExpectedJsonString,
                }

                const semantics = try requireJsonField(zone, "semantics");
                try expectJsonString(try requireJsonField(semantics, "kind"), "change_cube");
                const destination_cube = try requireJsonField(semantics, "destination_cube");
                const initially_on = try requireJsonField(semantics, "initially_on");
                switch (destination_cube) {
                    .integer => |value| {
                        if (value != 0) continue;
                    },
                    else => return error.ExpectedJsonInteger,
                }
                switch (initially_on) {
                    .bool => |value| {
                        if (!value) continue;
                    },
                    else => return error.ExpectedJsonBool,
                }

                count += 1;
                found = zone;
            }
            try std.testing.expectEqual(@as(usize, 1), count);
            break :blk found orelse return error.MissingJsonField;
        },
        else => return error.ExpectedJsonArray,
    };

    try expectJsonInteger(try requireJsonField(matching_zone, "x0"), 9728);
    try expectJsonInteger(try requireJsonField(matching_zone, "y0"), 1024);
    try expectJsonInteger(try requireJsonField(matching_zone, "z0"), 512);
    try expectJsonInteger(try requireJsonField(matching_zone, "x1"), 10239);
    try expectJsonInteger(try requireJsonField(matching_zone, "y1"), 2815);
    try expectJsonInteger(try requireJsonField(matching_zone, "z1"), 1535);
}

test "inspect-room-transitions keeps guarded 3/3 scoped to cellar-source destination handoffs" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-transitions",
        "3",
        "3",
        "--json",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "command"), "inspect-room-transitions");
    try expectJsonInteger(try requireJsonField(root, "source_scene_entry_index"), 3);
    try expectJsonInteger(try requireJsonField(root, "source_background_entry_index"), 3);
    try expectJsonInteger(try requireJsonField(root, "transition_count"), 3);

    const transitions = try requireJsonField(root, "transitions");
    var found_zone_1 = false;
    var found_zone_8 = false;
    var found_zone_15 = false;

    switch (transitions) {
        .array => |array| {
            for (array.items) |transition| {
                try expectJsonString(try requireJsonField(transition, "source_kind"), "decoded_change_cube");
                try expectJsonString(try requireJsonField(transition, "canonical_result_source"), "decoded_transition");
                try expectJsonNull(try requireJsonField(transition, "canonical_runtime_contract"));

                const source_zone_index = try jsonInteger(try requireJsonField(transition, "source_zone_index"));
                if (source_zone_index == 1) {
                    found_zone_1 = true;
                    try expectJsonInteger(try requireJsonField(transition, "source_zone_num"), 19);
                    try expectJsonInteger(try requireJsonField(transition, "destination_cube"), 19);
                    try expectJsonString(try requireJsonField(transition, "result"), "committed");
                    try expectJsonNull(try requireJsonField(transition, "rejection_reason"));
                    try expectJsonInteger(try requireJsonField(transition, "destination_scene_entry_index"), 21);
                    try expectJsonInteger(try requireJsonField(transition, "destination_background_entry_index"), 19);
                    try expectJsonNull(try requireJsonField(transition, "runtime_no_key_effect"));
                    try expectJsonNull(try requireJsonField(transition, "runtime_with_key_effect"));
                    try expectJsonNull(try requireJsonField(transition, "runtime_unlocked_effect"));
                } else if (source_zone_index == 8) {
                    found_zone_8 = true;
                    try expectJsonInteger(try requireJsonField(transition, "source_zone_num"), 20);
                    try expectJsonInteger(try requireJsonField(transition, "destination_cube"), 20);
                    try expectJsonString(try requireJsonField(transition, "result"), "committed");
                    try expectJsonNull(try requireJsonField(transition, "rejection_reason"));
                    try expectJsonInteger(try requireJsonField(transition, "destination_scene_entry_index"), 22);
                    try expectJsonInteger(try requireJsonField(transition, "destination_background_entry_index"), 20);
                    try expectJsonNull(try requireJsonField(transition, "runtime_no_key_effect"));
                    try expectJsonNull(try requireJsonField(transition, "runtime_with_key_effect"));
                    try expectJsonNull(try requireJsonField(transition, "runtime_unlocked_effect"));
                } else if (source_zone_index == 15) {
                    found_zone_15 = true;
                    try expectJsonInteger(try requireJsonField(transition, "source_zone_num"), 45);
                    try expectJsonInteger(try requireJsonField(transition, "destination_cube"), 45);
                    try expectJsonString(try requireJsonField(transition, "result"), "rejected");
                    try expectJsonString(try requireJsonField(transition, "rejection_reason"), "unsupported_destination_cube");
                    try expectJsonNull(try requireJsonField(transition, "destination_scene_entry_index"));
                    try expectJsonNull(try requireJsonField(transition, "destination_background_entry_index"));
                    try expectJsonNull(try requireJsonField(transition, "runtime_no_key_effect"));
                    try expectJsonNull(try requireJsonField(transition, "runtime_with_key_effect"));
                    try expectJsonNull(try requireJsonField(transition, "runtime_unlocked_effect"));
                } else {
                    return error.UnexpectedGuarded33TransitionZone;
                }
            }
        },
        else => return error.ExpectedJsonArray,
    }

    try std.testing.expect(found_zone_1);
    try std.testing.expect(found_zone_8);
    try std.testing.expect(found_zone_15);
}

test "inspect-room-transitions identifies the 0013 runtime contract as canonical" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-transitions",
        "2",
        "1",
        "--json",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const fixture_path = try std.fs.path.join(allocator, &.{ resolved.repo_root, "tools/fixtures/phase5_0013_runtime_proof.json" });
    defer allocator.free(fixture_path);
    const fixture_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        fixture_path,
        allocator,
        .limited(1024 * 1024),
    );
    defer allocator.free(fixture_bytes);

    try expectExited(result.term, 0);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    const fixture = try std.json.parseFromSlice(std.json.Value, allocator, fixture_bytes, .{});
    defer fixture.deinit();

    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "command"), "inspect-room-transitions");
    try expectJsonInteger(try requireJsonField(root, "source_scene_entry_index"), 2);
    try expectJsonInteger(try requireJsonField(root, "source_background_entry_index"), 1);
    try expectJsonInteger(try requireJsonField(root, "transition_count"), 1);

    const transition = try requireJsonArrayItem(try requireJsonField(root, "transitions"), 0);
    try expectJsonString(try requireJsonField(transition, "source_kind"), "decoded_change_cube");
    try expectJsonString(try requireJsonField(transition, "canonical_result_source"), "runtime_effects");
    try expectJsonString(try requireJsonField(transition, "canonical_runtime_contract"), "secret_room_key_gate_to_cellar");

    const no_key = try requireJsonField(transition, "runtime_no_key_effect");
    try expectJsonBool(try requireJsonField(no_key, "triggered_room_transition"), false);
    try expectJsonString(try requireJsonField(no_key, "secret_room_door_event"), "house_locked_no_key");

    const with_key = try requireJsonField(transition, "runtime_with_key_effect");
    try expectJsonBool(try requireJsonField(with_key, "triggered_room_transition"), false);
    try expectJsonString(try requireJsonField(with_key, "secret_room_door_event"), "house_consumed_key");
    try expectJsonInteger(
        try requireJsonField(with_key, "little_keys_before"),
        try jsonInteger(try requireJsonField(try requireJsonField(try requireJsonField(fixture.value, "door"), "key_consumed"), "nb_little_keys_before")),
    );
    try expectJsonInteger(
        try requireJsonField(with_key, "little_keys_after"),
        try jsonInteger(try requireJsonField(try requireJsonField(try requireJsonField(fixture.value, "door"), "key_consumed"), "nb_little_keys_after")),
    );

    const unlocked = try requireJsonField(transition, "runtime_unlocked_effect");
    try expectJsonBool(try requireJsonField(unlocked, "triggered_room_transition"), true);
    try expectJsonString(try requireJsonField(unlocked, "result"), "committed");
    try expectJsonInteger(try requireJsonField(unlocked, "destination_scene_entry_index"), 2);
    try expectJsonInteger(try requireJsonField(unlocked, "destination_background_entry_index"), 0);
    try expectJsonPointMatchesFixture(
        try requireJsonField(unlocked, "pending_runtime_new_position"),
        try requireJsonField(try requireJsonField(try requireJsonField(fixture.value, "door"), "cellar_transition"), "new_pos"),
    );
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

test "inspect-room-intelligence attributes malformed scene entry values to the scene selector" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "abc",
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
    const selection = try requireJsonField(root, "selection");
    const scene_selection = try requireJsonField(selection, "scene");
    try expectJsonString(try requireJsonField(scene_selection, "selector_kind"), "entry");
    try expectJsonNull(try requireJsonField(scene_selection, "requested_entry_index"));
    try expectJsonString(try requireJsonField(scene_selection, "requested_raw_value"), "abc");
    const background_selection = try requireJsonField(selection, "background");
    try expectJsonInteger(try requireJsonField(background_selection, "requested_entry_index"), 2);
    try expectJsonNull(try requireJsonField(background_selection, "requested_raw_value"));
    const error_payload = try requireJsonField(root, "error");
    try expectJsonString(try requireJsonField(error_payload, "phase"), "parse");
    try expectJsonString(try requireJsonField(error_payload, "kind"), "InvalidCharacter");
    try expectJsonString(try requireJsonField(error_payload, "target"), "scene");
}

test "inspect-room-intelligence attributes negative background entry values to the background selector" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "2",
        "--background-entry",
        "-1",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 1);
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    const selection = try requireJsonField(root, "selection");
    const background_selection = try requireJsonField(selection, "background");
    try expectJsonString(try requireJsonField(background_selection, "selector_kind"), "entry");
    try expectJsonNull(try requireJsonField(background_selection, "requested_entry_index"));
    try expectJsonString(try requireJsonField(background_selection, "requested_raw_value"), "-1");
    const error_payload = try requireJsonField(root, "error");
    try expectJsonString(try requireJsonField(error_payload, "phase"), "parse");
    try expectJsonString(try requireJsonField(error_payload, "kind"), "Overflow");
    try expectJsonString(try requireJsonField(error_payload, "target"), "background");
}

test "inspect-room-intelligence attributes overflow background entry values to the background selector" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const result = try runToolCommandAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "2",
        "--background-entry",
        "184467440737095516160",
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try expectExited(result.term, 1);
    try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    const selection = try requireJsonField(root, "selection");
    const background_selection = try requireJsonField(selection, "background");
    try expectJsonString(try requireJsonField(background_selection, "selector_kind"), "entry");
    try expectJsonNull(try requireJsonField(background_selection, "requested_entry_index"));
    try expectJsonString(try requireJsonField(background_selection, "requested_raw_value"), "184467440737095516160");
    const error_payload = try requireJsonField(root, "error");
    try expectJsonString(try requireJsonField(error_payload, "phase"), "parse");
    try expectJsonString(try requireJsonField(error_payload, "kind"), "Overflow");
    try expectJsonString(try requireJsonField(error_payload, "target"), "background");
}

test "inspect-room-intelligence writes parse failures to --out files without stdout spill" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const output = try runToolCommandToFileAlloc(allocator, resolved.repo_root, &.{
        "inspect-room-intelligence",
        "--scene-entry",
        "abc",
        "--background-entry",
        "2",
    });
    defer allocator.free(output.result.stdout);
    defer allocator.free(output.result.stderr);
    defer allocator.free(output.output_path);
    defer allocator.free(output.output_bytes);

    try expectExited(output.result.term, 1);
    try std.testing.expectEqual(@as(usize, 0), output.result.stderr.len);
    try std.testing.expectEqual(@as(usize, 0), output.result.stdout.len);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, output.output_bytes, .{});
    defer parsed.deinit();
    const root = parsed.value;
    try expectJsonString(try requireJsonField(root, "status"), "error");
    try expectJsonString(try requireJsonField(try requireJsonField(root, "error"), "target"), "scene");
    try expectJsonString(
        try requireJsonField(try requireJsonField(try requireJsonField(root, "selection"), "scene"), "requested_raw_value"),
        "abc",
    );
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
    try expectJsonFieldAbsent(root, "scripts");
    try expectJsonInteger(try requireJsonField(try requireJsonField(root, "scene"), "entry_index"), 11);
    try expectJsonInteger(try requireJsonField(try requireJsonField(root, "scene"), "classic_loader_scene_number"), 9);
    try expectJsonBool(try requireJsonField(try requireJsonField(root, "validation"), "viewer_loadable"), true);
    const decoded_scene_zones = try requireJsonField(root, "zones");
    const first_decoded_zone = try requireJsonArrayItem(decoded_scene_zones, 0);
    try expectJsonFieldAbsent(first_decoded_zone, "cells");
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
    const scene_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        scene_source,
        allocator,
        .limited(64 * 1024 * 1024),
    );
    defer allocator.free(scene_bytes);

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "SCENE.HQR",
        .data = scene_bytes[0 .. scene_bytes.len - 1],
    });

    const background_source = try std.fs.path.join(allocator, &.{ resolved.asset_root, "LBA_BKG.HQR" });
    defer allocator.free(background_source);
    try std.Io.Dir.cwd().copyFile(
        background_source,
        tmp.dir,
        "LBA_BKG.HQR",
        std.testing.io,
        .{},
    );

    const temp_asset_root = try tempDirAbsolutePathAlloc(allocator, &tmp, ".");
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

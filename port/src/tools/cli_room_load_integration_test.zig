const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const life_audit = @import("../game_data/scene/life_audit.zig");
const scene_data = @import("../game_data/scene.zig");
const room_state = @import("../runtime/room_state.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");

fn runToolCommandAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    tool_args: []const []const u8,
) !std.process.Child.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.appendSlice(allocator, &.{
        "py",
        "-3",
        ".\\scripts\\dev-shell.py",
        "exec",
        "--cwd",
        "port",
        "--",
        "zig",
        "build",
        "tool",
        "--",
    });
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
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"command\": \"inspect-room-intelligence\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"selector_kind\": \"entry\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"resolved_entry_index\": 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"decoded_actor_count\": 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"header_object_count\": 9") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"header_object_count_includes_hero\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"decoded_actor_count_matches_header_minus_hero\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"object_count\": 9") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"viewer_loadable\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\": \"decoded\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\": \"compatible\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"actors\": [") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"scene_object_index\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"array_index\": 0") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"viewer_loadable\": false") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"scene_kind\": \"exterior\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\": \"non_interior\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\": \"skipped\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"skipped_reason\": \"scene_must_be_interior\"") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "UnknownSceneEntryIndex") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "UnknownBackgroundEntryIndex") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, output.output_bytes, "\"command\": \"inspect-room-intelligence\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.output_bytes, "\"viewer_loadable\": true") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, output.output_bytes, "\"viewer_loadable\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.output_bytes, "\"fragment_zone_layout\": [") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.output_bytes, "\"tiles\": [") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.output_bytes, "\"height_grid\": [") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.output_bytes, "\"fragment_entry_index\": 149") != null);
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

    try std.testing.expectEqual(@as(usize, 203), scene.hero_start.life.bytes.len);
    try std.testing.expectEqual(scene.hero_start.life.bytes.len, hero_audit.life_byte_length);
    try std.testing.expectEqual(hero_audit.instruction_count, 47);
    try std.testing.expect(hero_audit.status == .decoded);

    try std.testing.expectEqual(@as(usize, 8), scene.objects.len);
    try std.testing.expectEqual(@as(usize, 1), scene.objects[0].index);
    try std.testing.expectEqual(scene.objects[0].life.bytes.len, first_actor_audit.life_byte_length);
    try std.testing.expectEqual(scene.objects[0].track.bytes.len, 1);
    try std.testing.expectEqual(first_actor_audit.instruction_count, 1);
    try std.testing.expect(first_actor_audit.status == .decoded);
    try std.testing.expectEqual(scene.objects.len + 1, scene.object_count);
}

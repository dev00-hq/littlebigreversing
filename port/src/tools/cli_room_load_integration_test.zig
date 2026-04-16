const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
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
        .max_output_bytes = 1024 * 1024,
    });
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
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"object_count\": 9") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"viewer_loadable\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\": \"decoded\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"status\": \"compatible\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"actors\": [") != null);
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

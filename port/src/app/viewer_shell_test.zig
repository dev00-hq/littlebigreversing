const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const runtime_query = @import("../runtime/world_query.zig");
const viewer_shell = @import("viewer_shell.zig");

test "viewer argument parsing requires explicit scene and background entries" {
    const parsed = try viewer_shell.parseArgs(std.testing.allocator, &.{
        "--scene-entry",
        "2",
        "--background-entry",
        "2",
        "--asset-root",
        "D:/assets",
    });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), parsed.scene_entry);
    try std.testing.expectEqual(@as(usize, 2), parsed.background_entry);
    try std.testing.expectEqualStrings("D:/assets", parsed.asset_root_override.?);
}

test "viewer window title carries the canonical room metadata" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try viewer_shell.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    const title = try viewer_shell.formatWindowTitleZ(allocator, room);
    defer allocator.free(title);

    try std.testing.expect(std.mem.indexOf(u8, title, "scene=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "background=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "kind=interior") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "loader=17") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "hero=1987,512,3743") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "cube=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "gri=20(grm=2,bll=1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "grm=151") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "bll=180") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "fragments=0/0") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "blocks=73[1|2|3|4|5|7|...]") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "columns=64x64") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "comp=1246") != null);
}

test "viewer locomotion harness keeps raw invalid 19/19 starts non-mutating" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try viewer_shell.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var runtime_session = viewer_shell.initSession(&room);
    const raw_start = runtime_session.heroWorldPosition();
    const attempt = viewer_shell.attemptLocomotionStep(&room, &runtime_session, .south);

    try std.testing.expectEqual(viewer_shell.ViewerLocomotionStepStatus.origin_invalid, attempt.status);
    try std.testing.expectEqual(raw_start, runtime_session.heroWorldPosition());
    try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_empty, attempt.origin.status);
    try std.testing.expectEqual(attempt.origin.target_world_position, attempt.target.target_world_position);
}

test "viewer locomotion harness seeds the session to the checked-in 19/19 movement fixture" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try viewer_shell.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var runtime_session = viewer_shell.initSession(&room);
    const seeded = try viewer_shell.seedSessionToLocomotionFixture(&room, &runtime_session);
    const query = runtime_query.init(&room);
    const seeded_eval = query.evaluateHeroMoveTarget(seeded);

    try std.testing.expectEqual(seeded, runtime_session.heroWorldPosition());
    try std.testing.expectEqual(runtime_query.MoveTargetStatus.allowed, seeded_eval.status);
    try std.testing.expectEqual(@as(?viewer_shell.GridCell, viewer_shell.locomotion_fixture_cell), seeded_eval.raw_cell.cell);
    try std.testing.expect(runtime_session.heroWorldPosition().x != room.scene.hero_start.x);
    try std.testing.expect(runtime_session.heroWorldPosition().z != room.scene.hero_start.z);
}

test "viewer locomotion harness mutates only on allowed seeded steps" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try viewer_shell.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var runtime_session = viewer_shell.initSession(&room);
    const seeded = try viewer_shell.seedSessionToLocomotionFixture(&room, &runtime_session);

    const moved = viewer_shell.attemptLocomotionStep(&room, &runtime_session, .south);
    try std.testing.expectEqual(viewer_shell.ViewerLocomotionStepStatus.moved, moved.status);
    try std.testing.expectEqual(@as(?viewer_shell.GridCell, .{ .x = 39, .z = 7 }), moved.target.raw_cell.cell);
    try std.testing.expect(runtime_session.heroWorldPosition().z > seeded.z);

    runtime_session.setHeroWorldPosition(seeded);
    const before_reject = runtime_session.heroWorldPosition();
    const rejected = viewer_shell.attemptLocomotionStep(&room, &runtime_session, .west);
    try std.testing.expectEqual(viewer_shell.ViewerLocomotionStepStatus.target_rejected, rejected.status);
    try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_empty, rejected.target.status);
    try std.testing.expectEqual(before_reject, runtime_session.heroWorldPosition());
}

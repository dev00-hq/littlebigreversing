const std = @import("std");
const builtin = @import("builtin");
const paths = @import("../foundation/paths.zig");
const viewer_shell = if (builtin.is_test) @import("../app/viewer_shell.zig") else struct {};
const locomotion = @import("locomotion.zig");
const room_entry_state = @import("room_entry_state.zig");
const room_state = @import("room_state.zig");
const room_fixtures = if (builtin.is_test) @import("../testing/room_fixtures.zig") else struct {};
const runtime_session = @import("session.zig");
const runtime_update = @import("update.zig");
const runtime_query = @import("world_query.zig");

pub const TransitionRejectionReason = enum {
    unsupported_yaw,
    unsupported_test_brick,
    unsupported_dont_readjust_twinsen,
    unsupported_exterior_destination_cube,
    unsupported_destination_cube,
    unsupported_destination_post_load_adjustment,
    unsupported_destination_world_position,
};

pub const TransitionCommitted = struct {
    source_scene_entry_index: usize,
    source_background_entry_index: usize,
    destination_cube: i16,
    destination_scene_entry_index: usize,
    destination_background_entry_index: usize,
    hero_position: locomotion.WorldPointSnapshot,
};

pub const TransitionRejected = struct {
    source_scene_entry_index: usize,
    source_background_entry_index: usize,
    destination_cube: i16,
    reason: TransitionRejectionReason,
    hero_position: locomotion.WorldPointSnapshot,
};

pub const TransitionApplyResult = union(enum) {
    committed: TransitionCommitted,
    rejected: TransitionRejected,
};

pub fn applyPendingRoomTransition(
    allocator: std.mem.Allocator,
    resolved: paths.ResolvedPaths,
    room: *room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
    locomotion_status: *locomotion.LocomotionStatus,
    pre_commit_locomotion_status: locomotion.LocomotionStatus,
) !TransitionApplyResult {
    const transition = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;
    const source_scene_entry_index = room.scene.entry_index;
    const source_background_entry_index = room.background.entry_index;

    if (unsupportedPendingRoomTransitionReason(transition)) |reason| {
        return rejectPendingRoomTransition(
            current_session,
            locomotion_status,
            pre_commit_locomotion_status,
            source_scene_entry_index,
            source_background_entry_index,
            transition.destination_cube,
            reason,
        );
    }

    if (unsupportedExteriorDestinationReason(
        source_scene_entry_index,
        source_background_entry_index,
        transition,
    )) |reason| {
        return rejectPendingRoomTransition(
            current_session,
            locomotion_status,
            pre_commit_locomotion_status,
            source_scene_entry_index,
            source_background_entry_index,
            transition.destination_cube,
            reason,
        );
    }

    const destination_entries = room_state.resolveGuardedTransitionRoomEntriesForCube(
        allocator,
        resolved,
        transition.destination_cube,
    ) catch |err| switch (err) {
        error.UnsupportedDestinationCube => return rejectPendingRoomTransition(
            current_session,
            locomotion_status,
            pre_commit_locomotion_status,
            source_scene_entry_index,
            source_background_entry_index,
            transition.destination_cube,
            .unsupported_destination_cube,
        ),
        else => return err,
    };

    var next_room = try room_state.loadRoomSnapshot(
        allocator,
        resolved,
        destination_entries.scene_entry_index,
        destination_entries.background_entry_index,
    );
    var next_room_owned = true;
    errdefer if (next_room_owned) next_room.deinit(allocator);

    const final_landing_world_position = resolveFinalLandingWorldPosition(
        current_session,
        &next_room,
        transition,
        locomotion_status,
        pre_commit_locomotion_status,
        source_scene_entry_index,
        source_background_entry_index,
    ) catch |err| switch (err) {
        error.UnsupportedDestinationPostLoadAdjustment => {
            next_room_owned = false;
            next_room.deinit(allocator);
            return rejectPendingRoomTransition(
                current_session,
                locomotion_status,
                pre_commit_locomotion_status,
                source_scene_entry_index,
                source_background_entry_index,
                transition.destination_cube,
                .unsupported_destination_post_load_adjustment,
            );
        },
        else => return err,
    };

    var transition_probe_session = try runtime_session.Session.initWithObjects(
        allocator,
        final_landing_world_position,
        next_room.scene.objects,
        next_room.scene.object_behavior_seeds,
    );
    defer transition_probe_session.deinit(allocator);
    const destination_locomotion_status = locomotion.inspectCurrentStatusRequiringAdmittedSeed(&next_room, transition_probe_session) catch |err| switch (err) {
        error.LocomotionStatusInvalidPosition => {
            next_room_owned = false;
            next_room.deinit(allocator);
            return rejectPendingRoomTransition(
                current_session,
                locomotion_status,
                pre_commit_locomotion_status,
                source_scene_entry_index,
                source_background_entry_index,
                transition.destination_cube,
                .unsupported_destination_world_position,
            );
        },
        else => return err,
    };

    try current_session.replaceRoomLocalState(
        allocator,
        final_landing_world_position,
        next_room.scene.objects,
        next_room.scene.object_behavior_seeds,
    );
    room_entry_state.applyRoomEntryState(&next_room, current_session);

    next_room_owned = false;
    room.deinit(allocator);
    room.* = next_room;
    locomotion_status.* = destination_locomotion_status;
    return .{
        .committed = .{
            .source_scene_entry_index = source_scene_entry_index,
            .source_background_entry_index = source_background_entry_index,
            .destination_cube = transition.destination_cube,
            .destination_scene_entry_index = destination_entries.scene_entry_index,
            .destination_background_entry_index = destination_entries.background_entry_index,
            .hero_position = final_landing_world_position,
        },
    };
}

fn resolveFinalLandingWorldPosition(
    current_session: *runtime_session.Session,
    next_room: *const room_state.RoomSnapshot,
    transition: runtime_session.PendingRoomTransition,
    locomotion_status: *locomotion.LocomotionStatus,
    pre_commit_locomotion_status: locomotion.LocomotionStatus,
    source_scene_entry_index: usize,
    source_background_entry_index: usize,
) !locomotion.WorldPointSnapshot {
    _ = current_session;
    _ = locomotion_status;
    _ = pre_commit_locomotion_status;
    _ = source_scene_entry_index;
    _ = source_background_entry_index;
    return switch (transition.destination_world_position_kind) {
        .final_landing => transition.destination_world_position,
        .provisional_zone_relative => resolveInteriorPostLoadLandingAdjustment(
            next_room,
            transition.destination_world_position,
        ),
    };
}

fn resolveInteriorPostLoadLandingAdjustment(
    next_room: *const room_state.RoomSnapshot,
    provisional_world_position: locomotion.WorldPointSnapshot,
) !locomotion.WorldPointSnapshot {
    const query = runtime_query.init(next_room);
    const evaluation = query.evaluateHeroMoveTarget(provisional_world_position);
    if (evaluation.isAllowed()) return provisional_world_position;

    if (evaluation.status != .target_height_mismatch) {
        return error.UnsupportedDestinationPostLoadAdjustment;
    }
    return query.classicShadowAdjustedLanding(provisional_world_position) catch
        error.UnsupportedDestinationPostLoadAdjustment;
}

fn unsupportedPendingRoomTransitionReason(
    transition: runtime_session.PendingRoomTransition,
) ?TransitionRejectionReason {
    if (transition.yaw != 0) return .unsupported_yaw;
    if (transition.test_brick) return .unsupported_test_brick;
    if (transition.dont_readjust_twinsen) return .unsupported_dont_readjust_twinsen;
    return null;
}

fn unsupportedExteriorDestinationReason(
    source_scene_entry_index: usize,
    source_background_entry_index: usize,
    transition: runtime_session.PendingRoomTransition,
) ?TransitionRejectionReason {
    // The guarded 2/2 room currently has one enabled type-0 change-cube seam:
    // zone index 0, the public door, targeting cube 0. Exact-seam Frida + cdb
    // runs showed that seam lands outside with `NewCube == 0`, so reject only
    // that proven public-door transition here.
    if (source_scene_entry_index == 2 and
        source_background_entry_index == 2 and
        transition.source_zone_index == 0 and
        transition.destination_cube == 0)
    {
        return .unsupported_exterior_destination_cube;
    }

    return null;
}

fn rejectPendingRoomTransition(
    current_session: *runtime_session.Session,
    locomotion_status: *locomotion.LocomotionStatus,
    pre_commit_locomotion_status: locomotion.LocomotionStatus,
    source_scene_entry_index: usize,
    source_background_entry_index: usize,
    destination_cube: i16,
    reason: TransitionRejectionReason,
) TransitionApplyResult {
    current_session.clearPendingRoomTransition();
    locomotion_status.* = pre_commit_locomotion_status;
    return .{
        .rejected = .{
            .source_scene_entry_index = source_scene_entry_index,
            .source_background_entry_index = source_background_entry_index,
            .destination_cube = destination_cube,
            .reason = reason,
            .hero_position = current_session.heroWorldPosition(),
        },
    };
}

test "guarded 19/19 seeded locomotion still cannot reach a real change-cube zone" {
    const room = try room_fixtures.guarded1919();
    try std.testing.expectEqual(@as(?runtime_session.PendingRoomTransition, null), try findReachableChangeCubeTransition(std.testing.allocator, room));
}

test "guarded 2/2 rejects the public exit as an unsupported exterior destination" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    var current_session = try viewer_shell.initSession(allocator, &room);
    defer current_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    try current_session.submitHeroIntent(.{ .move_cardinal = .east });
    const tick_result = try runtime_update.tick(&room, &current_session);
    try std.testing.expect(tick_result.triggered_room_transition);

    const transition_result = try applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        tick_result.locomotion_status,
    );
    switch (transition_result) {
        .rejected => |value| try std.testing.expectEqual(TransitionRejectionReason.unsupported_exterior_destination_cube, value.reason),
        .committed => return error.UnexpectedCommittedRoomTransition,
    }
}

test "guarded 2/2 only classifies the proven public-door seam as unsupported exterior" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    var current_session = try viewer_shell.initSession(allocator, &room);
    defer current_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    try current_session.setPendingRoomTransition(.{
        .source_zone_index = 9,
        .destination_cube = 0,
        .destination_world_position_kind = .final_landing,
        .destination_world_position = .{ .x = 0, .y = 0, .z = 0 },
        .yaw = 0,
        .test_brick = false,
        .dont_readjust_twinsen = false,
    });

    const transition_result = try applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        locomotion_status,
    );
    switch (transition_result) {
        .rejected => |value| try std.testing.expectEqual(TransitionRejectionReason.unsupported_destination_world_position, value.reason),
        .committed => return error.UnexpectedCommittedRoomTransition,
    }
}

test "guarded scene-2 secret-room door commits through the live-backed cube-0 landing" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    const door_zone = room.scene.zones[0];
    const door_semantics = switch (door_zone.semantics) {
        .change_cube => |value| value,
        else => return error.ExpectedChangeCubeZoneSemantics,
    };
    try std.testing.expectEqual(@as(i32, 9728), door_zone.x0);
    try std.testing.expectEqual(@as(i32, 1024), door_zone.y0);
    try std.testing.expectEqual(@as(i32, 512), door_zone.z0);
    try std.testing.expectEqual(@as(i16, 0), door_semantics.destination_cube);
    try std.testing.expectEqual(@as(i32, 2560), door_semantics.destination_x);
    try std.testing.expectEqual(@as(i32, 2048), door_semantics.destination_y);
    try std.testing.expectEqual(@as(i32, 3072), door_semantics.destination_z);

    var destination_room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer destination_room.deinit(allocator);
    const destination_query = runtime_query.init(&destination_room);
    const live_provisional_position = locomotion.WorldPointSnapshot{ .x = 2562, .y = 2049, .z = 3322 };
    const landing_evaluation = destination_query.evaluateHeroMoveTarget(live_provisional_position);
    try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_height_mismatch, landing_evaluation.status);
    try std.testing.expect(landing_evaluation.raw_cell.cell != null);
    try std.testing.expectEqual(@as(usize, 5), landing_evaluation.raw_cell.cell.?.x);
    try std.testing.expectEqual(@as(usize, 6), landing_evaluation.raw_cell.cell.?.z);
    try std.testing.expect(landing_evaluation.raw_cell.surface != null);
    try std.testing.expectEqual(@as(i32, 2048), landing_evaluation.raw_cell.surface.?.top_y);
    try std.testing.expectEqual(runtime_query.Standability.standable, landing_evaluation.raw_cell.standability.?);

    var current_session = try viewer_shell.initSession(allocator, &room);
    defer current_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    try current_session.setPendingRoomTransition(.{
        .source_zone_index = door_zone.index,
        .destination_cube = door_semantics.destination_cube,
        .destination_world_position_kind = .provisional_zone_relative,
        .destination_world_position = live_provisional_position,
        .yaw = door_semantics.yaw,
        .test_brick = door_semantics.test_brick,
        .dont_readjust_twinsen = door_semantics.dont_readjust_twinsen,
    });

    const transition_result = try applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        locomotion_status,
    );
    switch (transition_result) {
        .committed => |value| {
            try std.testing.expectEqual(@as(usize, 2), value.source_scene_entry_index);
            try std.testing.expectEqual(@as(usize, 1), value.source_background_entry_index);
            try std.testing.expectEqual(@as(i16, 0), value.destination_cube);
            try std.testing.expectEqual(@as(usize, 2), value.destination_scene_entry_index);
            try std.testing.expectEqual(@as(usize, 0), value.destination_background_entry_index);
            try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 2562, .y = 2048, .z = 3322 }, value.hero_position);
        },
        .rejected => return error.UnexpectedRejectedRoomTransition,
    }
}

test "guarded scene-2 reverse secret-room door commits through the live-backed cube-1 landing" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    var destination_room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer destination_room.deinit(allocator);
    const destination_query = runtime_query.init(&destination_room);
    const live_provisional_position = locomotion.WorldPointSnapshot{ .x = 9725, .y = 1278, .z = 1098 };
    const landing_evaluation = destination_query.evaluateHeroMoveTarget(live_provisional_position);
    try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_height_mismatch, landing_evaluation.status);
    try std.testing.expect(landing_evaluation.raw_cell.cell != null);
    try std.testing.expectEqual(runtime_query.Standability.standable, landing_evaluation.raw_cell.standability.?);

    var current_session = try viewer_shell.initSession(allocator, &room);
    defer current_session.deinit(allocator);
    current_session.setLittleKeyCount(0);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    try current_session.setPendingRoomTransition(.{
        .source_zone_index = 0,
        .destination_cube = 1,
        .destination_world_position_kind = .provisional_zone_relative,
        .destination_world_position = live_provisional_position,
        .yaw = 0,
        .test_brick = false,
        .dont_readjust_twinsen = false,
    });

    const transition_result = try applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        locomotion_status,
    );
    switch (transition_result) {
        .committed => |value| {
            try std.testing.expectEqual(@as(usize, 2), value.source_scene_entry_index);
            try std.testing.expectEqual(@as(usize, 0), value.source_background_entry_index);
            try std.testing.expectEqual(@as(i16, 1), value.destination_cube);
            try std.testing.expectEqual(@as(usize, 2), value.destination_scene_entry_index);
            try std.testing.expectEqual(@as(usize, 1), value.destination_background_entry_index);
            try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 9725, .y = 1024, .z = 1098 }, value.hero_position);
        },
        .rejected => return error.UnexpectedRejectedRoomTransition,
    }
}

test "guarded 3/3 resolves but rejects its two current interior destinations at post-load landing" {
    try expectGuarded33ChangeCubeRejection(1, 19, .unsupported_destination_post_load_adjustment);
    try expectGuarded33ChangeCubeRejection(8, 20, .unsupported_destination_post_load_adjustment);
}

test "guarded 3/3 rejects the exterior-facing change-cube destination" {
    const transition_result = try applyGuarded33ChangeCubeZone(15);
    switch (transition_result) {
        .rejected => |value| {
            try std.testing.expectEqual(@as(i16, 45), value.destination_cube);
            try std.testing.expectEqual(TransitionRejectionReason.unsupported_destination_cube, value.reason);
        },
        .committed => return error.UnexpectedCommittedRoomTransition,
    }
}

test "final-landing transitions still reject invalid destination positions explicitly" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var current_session = try viewer_shell.initSession(allocator, &room);
    defer current_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    try current_session.setPendingRoomTransition(.{
        .source_zone_index = 0,
        .destination_cube = 34,
        .destination_world_position_kind = .final_landing,
        .destination_world_position = .{ .x = 2560, .y = 2048, .z = 3072 },
        .yaw = 0,
        .test_brick = false,
        .dont_readjust_twinsen = false,
    });

    const transition_result = try applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        locomotion_status,
    );
    switch (transition_result) {
        .rejected => |value| try std.testing.expectEqual(TransitionRejectionReason.unsupported_destination_world_position, value.reason),
        .committed => return error.UnexpectedCommittedRoomTransition,
    }
}

test "provisional zone-relative transitions can apply bounded post-load vertical adjustment" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    var destination_room = try room_state.loadRoomSnapshot(allocator, resolved, 36, 36);
    defer destination_room.deinit(allocator);

    var expected_destination_session = try viewer_shell.initSession(allocator, &destination_room);
    defer expected_destination_session.deinit(allocator);
    const resolved_destination_world_position = try viewer_shell.seedSessionToLocomotionFixture(
        &destination_room,
        &expected_destination_session,
    );

    var current_session = try viewer_shell.initSession(allocator, &room);
    defer current_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    try current_session.setPendingRoomTransition(.{
        .source_zone_index = 0,
        .destination_cube = 34,
        .destination_world_position_kind = .provisional_zone_relative,
        .destination_world_position = .{
            .x = resolved_destination_world_position.x,
            .y = resolved_destination_world_position.y + 256,
            .z = resolved_destination_world_position.z,
        },
        .yaw = 0,
        .test_brick = false,
        .dont_readjust_twinsen = false,
    });

    const expected_shadow_landing = try runtime_query.init(&destination_room).classicShadowAdjustedLanding(.{
        .x = resolved_destination_world_position.x,
        .y = resolved_destination_world_position.y + 256,
        .z = resolved_destination_world_position.z,
    });

    const transition_result = try applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        locomotion_status,
    );
    switch (transition_result) {
        .committed => |value| {
            try std.testing.expectEqual(expected_shadow_landing, value.hero_position);
        },
        .rejected => return error.UnexpectedRejectedRoomTransition,
    }
}

fn findReachableChangeCubeTransition(
    allocator: std.mem.Allocator,
    room: *const room_state.RoomSnapshot,
) !?runtime_session.PendingRoomTransition {
    var current_session = try viewer_shell.initSession(allocator, room);
    defer current_session.deinit(allocator);
    _ = try viewer_shell.seedSessionToLocomotionFixture(room, &current_session);

    const query = runtime_query.init(room);
    var queue: std.ArrayList(locomotion.WorldPointSnapshot) = .empty;
    defer queue.deinit(allocator);
    var visited = std.AutoHashMap(locomotion.WorldPointSnapshot, void).init(allocator);
    defer visited.deinit();

    const start = current_session.heroWorldPosition();
    try queue.append(allocator, start);
    try visited.put(start, {});

    var head: usize = 0;
    while (head < queue.items.len and visited.count() < 50_000) : (head += 1) {
        const world_position = queue.items[head];
        const zone_membership = try query.containingZonesAtWorldPoint(world_position);
        for (zone_membership.slice()) |zone| {
            if (zone.kind != .change_cube) continue;
            const semantics = switch (zone.semantics) {
                .change_cube => |value| value,
                else => unreachable,
            };
            return .{
                .source_zone_index = zone.index,
                .destination_cube = semantics.destination_cube,
                .destination_world_position_kind = .provisional_zone_relative,
                .destination_world_position = .{
                    .x = semantics.destination_x,
                    .y = semantics.destination_y,
                    .z = semantics.destination_z,
                },
                .yaw = semantics.yaw,
                .test_brick = semantics.test_brick,
                .dont_readjust_twinsen = semantics.dont_readjust_twinsen,
            };
        }

        const options = query.evaluateCardinalMoveOptions(world_position) catch continue;
        for (options.options) |option| {
            if (!option.evaluation.isAllowed()) continue;
            const next_world_position = option.evaluation.target_world_position;
            if (visited.contains(next_world_position)) continue;
            try visited.put(next_world_position, {});
            try queue.append(allocator, next_world_position);
        }
    }

    return null;
}

fn expectGuarded33ChangeCubeRejection(
    source_zone_index: usize,
    destination_cube: i16,
    reason: TransitionRejectionReason,
) !void {
    const transition_result = try applyGuarded33ChangeCubeZone(source_zone_index);
    switch (transition_result) {
        .rejected => |value| {
            try std.testing.expectEqual(@as(usize, 3), value.source_scene_entry_index);
            try std.testing.expectEqual(@as(usize, 3), value.source_background_entry_index);
            try std.testing.expectEqual(destination_cube, value.destination_cube);
            try std.testing.expectEqual(reason, value.reason);
        },
        .committed => return error.UnexpectedCommittedRoomTransition,
    }
}

fn applyGuarded33ChangeCubeZone(source_zone_index: usize) !TransitionApplyResult {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 3, 3);
    defer room.deinit(allocator);

    var current_session = try viewer_shell.initSession(allocator, &room);
    defer current_session.deinit(allocator);
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);

    const zone = room.scene.zones[source_zone_index];
    const semantics = switch (zone.semantics) {
        .change_cube => |value| value,
        else => return error.ExpectedChangeCubeZoneSemantics,
    };
    try current_session.setPendingRoomTransition(.{
        .source_zone_index = zone.index,
        .destination_cube = semantics.destination_cube,
        .destination_world_position_kind = .provisional_zone_relative,
        .destination_world_position = .{
            .x = semantics.destination_x,
            .y = semantics.destination_y,
            .z = semantics.destination_z,
        },
        .yaw = semantics.yaw,
        .test_brick = semantics.test_brick,
        .dont_readjust_twinsen = semantics.dont_readjust_twinsen,
    });

    return applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        locomotion_status,
    );
}

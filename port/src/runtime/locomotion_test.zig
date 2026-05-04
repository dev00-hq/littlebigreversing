const std = @import("std");
const room_fixtures = @import("../testing/room_fixtures.zig");
const locomotion = @import("locomotion.zig");
const room_state = @import("room_state.zig");
const runtime_query = @import("world_query.zig");
const runtime_session = @import("session.zig");

const fixture_cell = locomotion.GridCell{ .x = 39, .z = 6 };

fn seedSessionToFixture(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !locomotion.WorldPointSnapshot {
    const query = runtime_query.init(room);
    const surface = try query.cellTopSurface(fixture_cell.x, fixture_cell.z);
    const seeded_position = runtime_query.gridCellCenterWorldPosition(
        fixture_cell.x,
        fixture_cell.z,
        surface.top_y,
    );
    current_session.setHeroWorldPosition(seeded_position);
    return seeded_position;
}

fn steppedWorldPoint(
    origin_world_position: locomotion.WorldPointSnapshot,
    direction: locomotion.CardinalDirection,
) locomotion.WorldPointSnapshot {
    return switch (direction) {
        .north => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z - runtime_query.world_grid_span_xz,
        },
        .east => .{
            .x = origin_world_position.x + runtime_query.world_grid_span_xz,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
        .south => .{
            .x = origin_world_position.x,
            .y = origin_world_position.y,
            .z = origin_world_position.z + runtime_query.world_grid_span_xz,
        },
        .west => .{
            .x = origin_world_position.x - runtime_query.world_grid_span_xz,
            .y = origin_world_position.y,
            .z = origin_world_position.z,
        },
    };
}

fn expectMoveOptions(
    room: *const room_state.RoomSnapshot,
    hero_position: locomotion.WorldPointSnapshot,
    move_options: locomotion.MoveOptions,
) !void {
    const query = runtime_query.init(room);
    const expected = try query.evaluateCardinalMoveOptions(hero_position);

    try std.testing.expectEqual(expected.origin.raw_cell.cell.?, move_options.current_cell);
    for (expected.options, 0..) |option, index| {
        try std.testing.expectEqual(option.direction, move_options.options[index].direction);
        try std.testing.expectEqual(option.evaluation.raw_cell.cell, move_options.options[index].target_cell);
        try std.testing.expectEqual(option.evaluation.status, move_options.options[index].status);
        try std.testing.expectEqual(option.evaluation.occupied_coverage, move_options.options[index].occupied_coverage);
    }
}

fn expectLocalTopology(
    room: *const room_state.RoomSnapshot,
    current_cell: locomotion.GridCell,
    local_topology: locomotion.LocalNeighborTopology,
) !void {
    const query = runtime_query.init(room);
    const expected = try query.probeLocalNeighborTopology(current_cell.x, current_cell.z);

    try std.testing.expectEqual(expected.origin_surface, local_topology.origin_surface);
    try std.testing.expectEqual(expected.origin_standability, local_topology.origin_standability);
    for (expected.neighbors, 0..) |neighbor, index| {
        try std.testing.expectEqual(neighbor, local_topology.neighbors[index]);
    }
}

fn expectZoneIndices(
    membership: runtime_query.ContainingZoneSet,
    expected_indices: []const usize,
) !void {
    const zones = membership.slice();
    try std.testing.expectEqual(expected_indices.len, zones.len);
    for (zones, expected_indices) |zone, expected_index| {
        try std.testing.expectEqual(expected_index, zone.index);
    }
}

fn expectRawInvalidStartCandidate(
    actual: ?locomotion.RawInvalidStartCandidate,
    expected: ?runtime_query.DiagnosticCandidate,
) !void {
    if (expected) |resolved_expected| {
        const resolved_actual = actual orelse return error.MissingRawInvalidStartCandidate;
        try std.testing.expectEqual(resolved_expected.kind, resolved_actual.kind);
        try std.testing.expectEqual(resolved_expected.cell, resolved_actual.cell);
        try std.testing.expectEqual(resolved_expected.x_distance, resolved_actual.x_distance);
        try std.testing.expectEqual(resolved_expected.z_distance, resolved_actual.z_distance);
        try std.testing.expectEqual(resolved_expected.distance_sq, resolved_actual.distance_sq);
        return;
    }

    try std.testing.expectEqual(@as(?locomotion.RawInvalidStartCandidate, null), actual);
}

fn expectWithinTolerance(expected: i32, actual: i32, tolerance: i32) !void {
    const delta = if (actual >= expected) actual - expected else expected - actual;
    try std.testing.expect(delta <= tolerance);
}

test "runtime locomotion exposes promoted Otringal behavior movement startup profile" {
    const ExpectedProfile = struct {
        mode: runtime_session.BehaviorMode,
        startup_ms: u16,
        distance_z_at_2000ms: i32,
    };
    const expected_profiles = [_]ExpectedProfile{
        .{ .mode = .normal, .startup_ms = 371, .distance_z_at_2000ms = 2008 },
        .{ .mode = .sporty, .startup_ms = 211, .distance_z_at_2000ms = 5066 },
        .{ .mode = .aggressive, .startup_ms = 105, .distance_z_at_2000ms = 2974 },
        .{ .mode = .discreet, .startup_ms = 478, .distance_z_at_2000ms = 772 },
    };

    try std.testing.expectEqualStrings(
        "behavior_movement_speed_startup_otringal",
        locomotion.behavior_movement_speed_startup_otringal_contract,
    );

    for (expected_profiles) |expected| {
        const profile = locomotion.behaviorMovementProfile(expected.mode);
        try std.testing.expectEqual(expected.mode, profile.mode);
        try std.testing.expectEqual(expected.startup_ms, profile.startup_ms);
        try std.testing.expectEqual(expected.distance_z_at_2000ms, profile.distance_z_at_2000ms);
        try std.testing.expectEqual(@as(i32, 0), locomotion.behaviorForwardHoldDistanceZ(expected.mode, expected.startup_ms));
        try std.testing.expect(locomotion.behaviorForwardHoldDistanceZ(expected.mode, expected.startup_ms + 50) > 0);
        try std.testing.expectEqual(
            expected.distance_z_at_2000ms,
            locomotion.behaviorForwardHoldDistanceZ(expected.mode, 2000),
        );
    }
}

test "runtime locomotion exposes decoded behavior walk root-motion curves without wiring movement" {
    const ExpectedRootMotion = struct {
        mode: runtime_session.BehaviorMode,
        animation_asset: []const u8,
        file3d_object: u8,
        decoded_distance_z_at_500ms: i32,
        decoded_distance_z_at_1000ms: i32,
        decoded_distance_z_at_1500ms: i32,
        decoded_distance_z_at_2000ms: i32,
        live_distance_z_at_2000ms: i32,
    };
    const expected_curves = [_]ExpectedRootMotion{
        .{ .mode = .normal, .animation_asset = "ANIM.HQR:1", .file3d_object = 0, .decoded_distance_z_at_500ms = 240, .decoded_distance_z_at_1000ms = 840, .decoded_distance_z_at_1500ms = 1440, .decoded_distance_z_at_2000ms = 2040, .live_distance_z_at_2000ms = 2008 },
        .{ .mode = .sporty, .animation_asset = "ANIM.HQR:67", .file3d_object = 1, .decoded_distance_z_at_500ms = 739, .decoded_distance_z_at_1000ms = 2201, .decoded_distance_z_at_1500ms = 3721, .decoded_distance_z_at_2000ms = 5149, .live_distance_z_at_2000ms = 5066 },
        .{ .mode = .aggressive, .animation_asset = "ANIM.HQR:83", .file3d_object = 2, .decoded_distance_z_at_500ms = 698, .decoded_distance_z_at_1000ms = 1351, .decoded_distance_z_at_1500ms = 2173, .decoded_distance_z_at_2000ms = 3018, .live_distance_z_at_2000ms = 2974 },
        .{ .mode = .discreet, .animation_asset = "ANIM.HQR:94", .file3d_object = 3, .decoded_distance_z_at_500ms = 69, .decoded_distance_z_at_1000ms = 396, .decoded_distance_z_at_1500ms = 616, .decoded_distance_z_at_2000ms = 782, .live_distance_z_at_2000ms = 772 },
    };

    for (expected_curves) |expected| {
        const curve = locomotion.behaviorWalkRootMotion(expected.mode);
        try std.testing.expectEqual(expected.mode, curve.mode);
        try std.testing.expectEqualStrings(expected.animation_asset, curve.animation_asset);
        try std.testing.expectEqual(expected.file3d_object, curve.file3d_object);
        try std.testing.expectEqual(
            expected.decoded_distance_z_at_500ms,
            locomotion.behaviorWalkRootMotionDistanceZ(expected.mode, 500),
        );
        try std.testing.expectEqual(
            expected.decoded_distance_z_at_1000ms,
            locomotion.behaviorWalkRootMotionDistanceZ(expected.mode, 1000),
        );
        try std.testing.expectEqual(
            expected.decoded_distance_z_at_1500ms,
            locomotion.behaviorWalkRootMotionDistanceZ(expected.mode, 1500),
        );
        try std.testing.expectEqual(
            expected.decoded_distance_z_at_2000ms,
            locomotion.behaviorWalkRootMotionDistanceZ(expected.mode, 2000),
        );
        try expectWithinTolerance(
            expected.live_distance_z_at_2000ms,
            locomotion.behaviorWalkRootMotionDistanceZ(expected.mode, 2000),
            100,
        );
    }
}

test "runtime locomotion computes gameplay held-forward deltas from behavior root motion" {
    var movement = locomotion.beginHeldForwardMovement(.normal);

    const first = locomotion.advanceHeldForwardMovement(&movement, 500);
    try std.testing.expectEqual(runtime_session.BehaviorMode.normal, first.mode);
    try std.testing.expectEqual(@as(u16, 0), first.previous_elapsed_ms);
    try std.testing.expectEqual(@as(u16, 500), first.elapsed_ms);
    try std.testing.expectEqual(@as(i32, 0), first.previous_forward_distance_z);
    try std.testing.expectEqual(@as(i32, 240), first.forward_distance_z);
    try std.testing.expectEqual(@as(i32, 240), first.forward_delta_z);

    const second = locomotion.advanceHeldForwardMovement(&movement, 500);
    try std.testing.expectEqual(@as(u16, 500), second.previous_elapsed_ms);
    try std.testing.expectEqual(@as(u16, 1000), second.elapsed_ms);
    try std.testing.expectEqual(@as(i32, 240), second.previous_forward_distance_z);
    try std.testing.expectEqual(@as(i32, 840), second.forward_distance_z);
    try std.testing.expectEqual(@as(i32, 600), second.forward_delta_z);

    try std.testing.expectEqual(
        locomotion.behaviorWalkRootMotionDistanceZ(.normal, 1000),
        first.forward_delta_z + second.forward_delta_z,
    );
}

test "runtime locomotion keeps diagnostic grid step separate from held-forward movement" {
    const room = try room_fixtures.guarded1919();
    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const seeded_position = try seedSessionToFixture(room, &current_session);

    var held_forward = locomotion.beginHeldForwardMovement(.sporty);
    const gameplay_delta = locomotion.advanceHeldForwardMovement(&held_forward, 500);
    try std.testing.expectEqual(@as(i32, 739), gameplay_delta.forward_distance_z);
    try std.testing.expectEqual(seeded_position, current_session.heroWorldPosition());

    const diagnostic_status = try locomotion.applyDiagnosticStep(room, &current_session, .south);
    switch (diagnostic_status) {
        .last_move_accepted => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.south, value.direction);
            try std.testing.expect(current_session.heroWorldPosition().z > seeded_position.z);
        },
        else => return error.UnexpectedDiagnosticLocomotionStatus,
    }
}

test "runtime locomotion applies held-forward root motion through the gameplay seam" {
    const room = try room_fixtures.guarded1919();
    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const seeded_position = try seedSessionToFixture(room, &current_session);

    const status = try locomotion.applyHeldForwardMovement(room, &current_session, 500);

    switch (status) {
        .last_move_accepted => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.north, value.direction);
            try std.testing.expectEqual(fixture_cell, value.origin_cell);
            try std.testing.expectEqual(seeded_position.x, current_session.heroWorldPosition().x);
            try std.testing.expectEqual(seeded_position.y, current_session.heroWorldPosition().y);
            try std.testing.expectEqual(seeded_position.z - 240, current_session.heroWorldPosition().z);
            try std.testing.expectEqual(current_session.heroWorldPosition(), value.hero_position);
            try std.testing.expectEqual(@as(u16, 500), current_session.heldForwardMovement().?.elapsed_ms);
            try std.testing.expectEqual(@as(i32, 240), current_session.heldForwardMovement().?.previous_forward_distance_z);
        },
        else => return error.UnexpectedHeldForwardLocomotionStatus,
    }
}

test "runtime locomotion projects held-forward root motion through hero facing" {
    const room = try room_fixtures.guarded1919();
    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const seeded_position = try seedSessionToFixture(room, &current_session);
    current_session.setHeroBeta(runtime_session.hero_beta_quarter_turn);

    const status = try locomotion.applyHeldForwardMovement(room, &current_session, 500);

    switch (status) {
        .last_move_accepted => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.east, value.direction);
            try std.testing.expectEqual(seeded_position.x + 240, current_session.heroWorldPosition().x);
            try std.testing.expectEqual(seeded_position.z, current_session.heroWorldPosition().z);
        },
        else => return error.UnexpectedHeldForwardLocomotionStatus,
    }
}

fn expectRawInvalidStartMappingHint(
    actual: ?locomotion.RawInvalidStartMappingHint,
    expected: *const runtime_query.HeroStartMappingEvaluation,
) !void {
    const resolved_actual = actual orelse return error.MissingRawInvalidStartMappingHint;

    try std.testing.expectEqual(expected.hypothesis, resolved_actual.hypothesis);
    try std.testing.expectEqual(expected.cell_span_xz, resolved_actual.cell_span_xz);
    try std.testing.expectEqual(expected.raw_cell.cell, resolved_actual.raw_cell);
    try std.testing.expectEqual(expected.exact_status, resolved_actual.exact_status);
    try std.testing.expectEqual(expected.diagnostic_status, resolved_actual.diagnostic_status);
    try std.testing.expectEqual(expected.occupied_coverage, resolved_actual.occupied_coverage);
    try std.testing.expectEqual(expected.comparison_to_canonical.disposition, resolved_actual.disposition);
    try std.testing.expectEqual(expected.comparison_to_canonical.better_metric_count, resolved_actual.better_metric_count);
    try std.testing.expectEqual(expected.comparison_to_canonical.worse_metric_count, resolved_actual.worse_metric_count);
}

test "runtime locomotion reports the baked guarded 19/19 raw start as an invalid non-mutating origin" {
    const room = try room_fixtures.guarded1919();
    const query = runtime_query.init(room);
    const hero_start_probe = try query.probeHeroStart();
    const mapping_report = try query.evaluateHeroStartMappings();
    const best_alt_mapping = mapping_report.evaluation(.dense_swapped_axes_64);

    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const initial_status = try locomotion.inspectCurrentStatus(room, current_session);
    const rejected_status = try locomotion.applyStep(room, &current_session, .south);

    switch (initial_status) {
        .raw_invalid_start => |value| {
            try std.testing.expectEqual(runtime_query.HeroStartExactStatus.mapped_cell_empty, value.exact_status);
            try std.testing.expectEqual(hero_start_probe.diagnostic_status, value.diagnostic_status);
            try std.testing.expectEqual(@as(?locomotion.GridCell, .{ .x = 3, .z = 7 }), value.raw_cell);
            try std.testing.expectEqual(hero_start_probe.occupied_coverage, value.occupied_coverage);
            try expectRawInvalidStartCandidate(value.nearest_occupied, hero_start_probe.nearest_occupied);
            try expectRawInvalidStartCandidate(value.nearest_standable, hero_start_probe.nearest_standable);
            try expectRawInvalidStartMappingHint(value.best_alt_mapping, best_alt_mapping);
            try std.testing.expectEqual(room_state.heroStartWorldPoint(room), value.hero_position);
        },
        else => return error.UnexpectedLocomotionStatus,
    }

    switch (rejected_status) {
        .last_move_rejected => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.south, value.direction);
            try std.testing.expectEqual(locomotion.LocomotionRejectedStage.origin_invalid, value.rejection_stage);
            try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_empty, value.reason);
            try std.testing.expectEqual(@as(?locomotion.GridCell, .{ .x = 3, .z = 7 }), value.current_cell);
            try std.testing.expectEqual(@as(?locomotion.GridCell, .{ .x = 3, .z = 7 }), value.target_cell);
            try std.testing.expectEqual(@as(?runtime_query.OccupiedCoverageProbe, null), value.target_occupied_coverage);
            try std.testing.expectEqual(@as(?locomotion.MoveOptions, null), value.move_options);
            try std.testing.expectEqual(@as(?locomotion.LocalNeighborTopology, null), value.local_topology);
            try std.testing.expectEqual(room_state.heroStartWorldPoint(room), value.hero_position);
            try expectZoneIndices(value.zone_membership, &.{});
        },
        else => return error.UnexpectedLocomotionStatus,
    }

    try std.testing.expectEqual(room_state.heroStartWorldPoint(room), current_session.heroWorldPosition());
}

test "runtime locomotion reports the explicit guarded 19/19 fixture as the admitted current position" {
    const room = try room_fixtures.guarded1919();

    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const seeded_position = try seedSessionToFixture(room, &current_session);
    const status = try locomotion.inspectCurrentStatus(room, current_session);

    switch (status) {
        .seeded_valid => |value| {
            try std.testing.expectEqual(fixture_cell, value.cell);
            try std.testing.expectEqual(seeded_position, value.hero_position);
            try expectMoveOptions(room, seeded_position, value.move_options);
            try expectLocalTopology(room, fixture_cell, value.local_topology);
            try expectZoneIndices(value.zone_membership, &.{});
        },
        else => return error.UnexpectedLocomotionStatus,
    }
}

test "runtime locomotion promotes guarded 187/187 nearest-standable startup seed" {
    const room = try room_fixtures.guarded187187();
    const query = runtime_query.init(room);
    const hero_start_probe = try query.probeHeroStart();
    const candidate = hero_start_probe.nearest_standable orelse return error.MissingNearestStandableDiagnosticCandidate;
    const expected_seed = runtime_query.gridCellCenterWorldPosition(
        candidate.cell.x,
        candidate.cell.z,
        candidate.surface.top_y,
    );

    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const initial_status = try locomotion.inspectCurrentStatus(room, current_session);
    switch (initial_status) {
        .raw_invalid_start => |value| {
            try std.testing.expectEqual(hero_start_probe.exact_status, value.exact_status);
            try std.testing.expectEqual(hero_start_probe.raw_cell.cell, value.raw_cell);
            try expectRawInvalidStartCandidate(value.nearest_standable, hero_start_probe.nearest_standable);
            try std.testing.expectEqual(room_state.heroStartWorldPoint(room), value.hero_position);
        },
        else => return error.UnexpectedLocomotionStatus,
    }

    const seeded_position = try locomotion.seedSessionToNearestStandableStart(room, &current_session);
    try std.testing.expectEqual(expected_seed, seeded_position);
    try std.testing.expectEqual(expected_seed, current_session.heroWorldPosition());

    const seeded_status = try locomotion.inspectCurrentStatus(room, current_session);
    switch (seeded_status) {
        .seeded_valid => |value| {
            try std.testing.expectEqual(candidate.cell, value.cell);
            try std.testing.expectEqual(expected_seed, value.hero_position);
            try expectMoveOptions(room, expected_seed, value.move_options);
            try expectLocalTopology(room, candidate.cell, value.local_topology);
        },
        else => return error.UnexpectedLocomotionStatus,
    }
}

test "runtime locomotion allows a bounded raw-zone recovery nudge into guarded 2/2 change-cube" {
    const room = try room_fixtures.guarded22();

    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const raw_start = current_session.heroWorldPosition();
    const moved_status = try locomotion.applyStep(room, &current_session, .east);

    switch (moved_status) {
        .last_zone_recovery_accepted => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.east, value.direction);
            try std.testing.expectEqual(raw_start.y, value.hero_position.y);
            try std.testing.expectEqual(raw_start.z, value.hero_position.z);
            try std.testing.expectEqual(
                raw_start.x + locomotion.raw_invalid_zone_entry_step_xz,
                value.hero_position.x,
            );
            try std.testing.expectEqual(current_session.heroWorldPosition(), value.hero_position);
            try expectZoneIndices(value.zone_membership, &.{0});
        },
        else => return error.UnexpectedLocomotionStatus,
    }
}

test "runtime locomotion mutates only on allowed seeded steps and preserves zone membership on rejected steps" {
    const room = try room_fixtures.guarded1919();

    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const seeded_position = try seedSessionToFixture(room, &current_session);

    const moved_status = try locomotion.applyStep(room, &current_session, .south);
    switch (moved_status) {
        .last_move_accepted => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.south, value.direction);
            try std.testing.expectEqual(fixture_cell, value.origin_cell);
            try std.testing.expectEqual(locomotion.GridCell{ .x = 39, .z = 7 }, value.cell);
            try std.testing.expect(current_session.heroWorldPosition().z > seeded_position.z);
            try std.testing.expectEqual(current_session.heroWorldPosition(), value.hero_position);
            try expectMoveOptions(room, current_session.heroWorldPosition(), value.move_options);
            try expectLocalTopology(room, value.cell, value.local_topology);
            try expectZoneIndices(value.zone_membership, &.{});
        },
        else => return error.UnexpectedLocomotionStatus,
    }

    _ = try seedSessionToFixture(room, &current_session);
    const before_reject = current_session.heroWorldPosition();
    const rejected_status = try locomotion.applyStep(room, &current_session, .west);
    const query = runtime_query.init(room);
    const expected_target = query.evaluateHeroMoveTarget(steppedWorldPoint(before_reject, .west));

    switch (rejected_status) {
        .last_move_rejected => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.west, value.direction);
            try std.testing.expectEqual(locomotion.LocomotionRejectedStage.target_rejected, value.rejection_stage);
            try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_empty, value.reason);
            try std.testing.expectEqual(@as(?locomotion.GridCell, fixture_cell), value.current_cell);
            try std.testing.expectEqual(@as(?locomotion.GridCell, .{ .x = 38, .z = 6 }), value.target_cell);
            try std.testing.expectEqual(expected_target.occupied_coverage, value.target_occupied_coverage orelse return error.MissingTargetOccupiedCoverage);
            try std.testing.expect(value.move_options != null);
            try std.testing.expect(value.local_topology != null);
            try std.testing.expectEqual(before_reject, current_session.heroWorldPosition());
            try std.testing.expectEqual(before_reject, value.hero_position);
            try expectMoveOptions(room, before_reject, value.move_options.?);
            try expectLocalTopology(room, fixture_cell, value.local_topology.?);
            try expectZoneIndices(value.zone_membership, &.{});
        },
        else => return error.UnexpectedLocomotionStatus,
    }
}

test "runtime locomotion consumes pending hero intents through the runtime seam" {
    const room = try room_fixtures.guarded1919();

    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const seeded_position = try seedSessionToFixture(room, &current_session);
    try current_session.submitHeroIntent(.{ .move_cardinal = .south });

    const moved_status = try locomotion.applyPendingHeroIntent(room, &current_session);
    try std.testing.expectEqual(@as(?runtime_session.HeroIntent, null), current_session.pendingHeroIntent());

    switch (moved_status) {
        .last_move_accepted => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.south, value.direction);
            try std.testing.expectEqual(fixture_cell, value.origin_cell);
            try std.testing.expectEqual(locomotion.GridCell{ .x = 39, .z = 7 }, value.cell);
            try std.testing.expect(current_session.heroWorldPosition().z > seeded_position.z);
            try std.testing.expectEqual(current_session.heroWorldPosition(), value.hero_position);
        },
        else => return error.UnexpectedLocomotionStatus,
    }
}

test "runtime locomotion consumes pending held-forward gameplay intents through the runtime seam" {
    const room = try room_fixtures.guarded1919();

    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const seeded_position = try seedSessionToFixture(room, &current_session);
    try current_session.submitHeroIntent(.{ .move_forward_held_ms = 500 });

    const moved_status = try locomotion.applyPendingHeroIntent(room, &current_session);
    try std.testing.expectEqual(@as(?runtime_session.HeroIntent, null), current_session.pendingHeroIntent());

    switch (moved_status) {
        .last_move_accepted => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.north, value.direction);
            try std.testing.expectEqual(fixture_cell, value.origin_cell);
            try std.testing.expectEqual(seeded_position.z - 240, current_session.heroWorldPosition().z);
            try std.testing.expectEqual(current_session.heroWorldPosition(), value.hero_position);
        },
        else => return error.UnexpectedLocomotionStatus,
    }
}

test "runtime locomotion fails fast when asked to apply a missing pending hero intent" {
    const room = try room_fixtures.guarded1919();

    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    try std.testing.expectError(
        error.MissingPendingHeroIntent,
        locomotion.applyPendingHeroIntent(room, &current_session),
    );
}

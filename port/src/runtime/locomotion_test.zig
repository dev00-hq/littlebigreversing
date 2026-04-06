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

test "runtime locomotion reports the baked guarded 19/19 raw start as an invalid non-mutating origin" {
    const room = try room_fixtures.guarded1919();

    var current_session = runtime_session.Session.init(room_state.heroStartWorldPoint(room));
    const initial_status = try locomotion.inspectCurrentStatus(room, current_session);
    const rejected_status = try locomotion.applyStep(room, &current_session, .south);

    switch (initial_status) {
        .raw_invalid_start => |value| {
            try std.testing.expectEqual(runtime_query.HeroStartExactStatus.mapped_cell_empty, value.exact_status);
            try std.testing.expectEqual(@as(?locomotion.GridCell, .{ .x = 3, .z = 7 }), value.raw_cell);
            try std.testing.expectEqual(runtime_query.OccupiedCoverageRelation.outside_occupied_bounds, value.occupied_coverage);
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
            try std.testing.expectEqual(@as(?locomotion.MoveOptions, null), value.move_options);
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
            try expectZoneIndices(value.zone_membership, &.{});
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
            try std.testing.expectEqual(locomotion.GridCell{ .x = 39, .z = 7 }, value.cell);
            try std.testing.expect(current_session.heroWorldPosition().z > seeded_position.z);
            try std.testing.expectEqual(current_session.heroWorldPosition(), value.hero_position);
            try expectMoveOptions(room, current_session.heroWorldPosition(), value.move_options);
            try expectZoneIndices(value.zone_membership, &.{});
        },
        else => return error.UnexpectedLocomotionStatus,
    }

    _ = try seedSessionToFixture(room, &current_session);
    const before_reject = current_session.heroWorldPosition();
    const rejected_status = try locomotion.applyStep(room, &current_session, .west);

    switch (rejected_status) {
        .last_move_rejected => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.west, value.direction);
            try std.testing.expectEqual(locomotion.LocomotionRejectedStage.target_rejected, value.rejection_stage);
            try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_empty, value.reason);
            try std.testing.expectEqual(@as(?locomotion.GridCell, fixture_cell), value.current_cell);
            try std.testing.expectEqual(@as(?locomotion.GridCell, .{ .x = 38, .z = 6 }), value.target_cell);
            try std.testing.expect(value.move_options != null);
            try std.testing.expectEqual(before_reject, current_session.heroWorldPosition());
            try std.testing.expectEqual(before_reject, value.hero_position);
            try expectMoveOptions(room, before_reject, value.move_options.?);
            try expectZoneIndices(value.zone_membership, &.{});
        },
        else => return error.UnexpectedLocomotionStatus,
    }
}

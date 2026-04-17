const std = @import("std");
const reference_metadata = @import("../generated/reference_metadata.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const object_behavior = @import("object_behavior.zig");
const locomotion = @import("locomotion.zig");
const room_state = @import("room_state.zig");
const runtime_query = @import("world_query.zig");
const runtime_session = @import("session.zig");
const runtime_update = @import("update.zig");
const zone_effects = @import("zone_effects.zig");

const fixture_cell = locomotion.GridCell{ .x = 39, .z = 6 };
const sendell_ball_flag_index: u8 = reference_metadata.sendell_ball_flag.index;
const lightning_spell_flag_index: u8 = reference_metadata.lightning_spell_flag.index;

fn initSession(room: *const room_state.RoomSnapshot) !runtime_session.Session {
    return runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
}

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

fn zoneSetContainsIndex(
    membership: runtime_query.ContainingZoneSet,
    zone_index: usize,
) bool {
    for (membership.slice()) |zone| {
        if (zone.index == zone_index) return true;
    }
    return false;
}

test "runtime update tick advances frame ownership and supported object behavior even without hero intent" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    const tick_result = try runtime_update.tick(room, &current_session);

    try std.testing.expect(!tick_result.consumed_hero_intent);
    try std.testing.expect(!tick_result.triggered_room_transition);
    try std.testing.expectEqual(@as(usize, 1), current_session.frame_index);
    try std.testing.expectEqual(@as(usize, 1), tick_result.updated_object_count);
    try std.testing.expectEqual(@as(u8, 1), current_session.cubeVar(0));
    try std.testing.expectEqual(@as(i16, 138), current_session.objectBehaviorStateByIndex(2).?.current_sprite);
    switch (tick_result.locomotion_status) {
        .raw_invalid_start => {},
        else => return error.UnexpectedLocomotionStatus,
    }
}

test "runtime update tick consumes queued hero movement and advances the frame index" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    const seeded_position = try seedSessionToFixture(room, &current_session);
    try current_session.submitHeroIntent(.{ .move_cardinal = .south });

    const tick_result = try runtime_update.tick(room, &current_session);

    try std.testing.expect(tick_result.consumed_hero_intent);
    try std.testing.expect(!tick_result.triggered_room_transition);
    try std.testing.expectEqual(@as(?runtime_session.HeroIntent, null), current_session.pendingHeroIntent());
    try std.testing.expectEqual(@as(usize, 1), current_session.frame_index);
    try std.testing.expectEqual(@as(usize, 1), tick_result.updated_object_count);
    try std.testing.expectEqual(@as(u8, 1), current_session.cubeVar(0));
    try std.testing.expectEqual(@as(i16, 138), current_session.objectBehaviorStateByIndex(2).?.current_sprite);
    switch (tick_result.locomotion_status) {
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

test "runtime object behavior frame progression advances the later 19/19 object 2 reward loop and emits bounded magic bonus events" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{
        .x = 2500,
        .y = 1000,
        .z = 1000,
    });

    _ = try object_behavior.stepSupportedObjects(room, &current_session);
    current_session.advanceFrameIndex();
    const primed_state = current_session.objectBehaviorStateByIndexPtr(2) orelse return error.MissingRuntimeObjectBehaviorState;
    primed_state.last_hit_by = 1;

    var reward_tick: ?usize = null;
    var tick_index: usize = 1;
    while (tick_index < 16) : (tick_index += 1) {
        _ = try object_behavior.stepSupportedObjects(room, &current_session);
        current_session.advanceFrameIndex();
        if (current_session.bonusSpawnEvents().len != 0) {
            reward_tick = tick_index + 1;
            break;
        }
    }

    try std.testing.expectEqual(@as(?usize, 13), reward_tick);
    try std.testing.expectEqual(@as(u8, 1), current_session.cubeVar(1));
    try std.testing.expectEqual(@as(usize, 1), current_session.bonusSpawnEvents().len);

    const bonus_event = current_session.bonusSpawnEvents()[0];
    try std.testing.expectEqual(@as(usize, 12), bonus_event.frame_index);
    try std.testing.expectEqual(@as(usize, 2), bonus_event.source_object_index);
    try std.testing.expectEqual(runtime_session.RuntimeBonusKind.magic, bonus_event.kind);
    try std.testing.expectEqual(@as(i16, 5), bonus_event.sprite_index);
    try std.testing.expectEqual(@as(u8, 5), bonus_event.quantity);

    const rewarded_state = current_session.objectBehaviorStateByIndex(2) orelse return error.MissingRuntimeObjectBehaviorState;
    try std.testing.expectEqual(@as(u8, 1), rewarded_state.emitted_bonus_count);
    try std.testing.expectEqual(@as(u8, @intFromEnum(life_program.LifeOpcode.LM_SNIF)), rewarded_state.life_bytes[51]);

    _ = try object_behavior.stepSupportedObjects(room, &current_session);
    current_session.advanceFrameIndex();
    const recovered_state = current_session.objectBehaviorStateByIndex(2) orelse return error.MissingRuntimeObjectBehaviorState;
    try std.testing.expectEqual(@as(u8, @intFromEnum(life_program.LifeOpcode.LM_SWIF)), recovered_state.life_bytes[51]);
}

test "runtime zone effects record a generic change-cube transition from guarded 2/2 zone semantics" {
    const room = try room_fixtures.guarded22();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);

    var zone_membership: runtime_query.ContainingZoneSet = .{};
    try zone_membership.append(room.scene.zones[0]);
    const effect_summary = try zone_effects.applyContainingZoneEffects(&current_session, zone_membership.slice());

    try std.testing.expect(effect_summary.triggered_room_transition);
    const transition = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;
    const semantics = switch (room.scene.zones[0].semantics) {
        .change_cube => |value| value,
        else => return error.ExpectedChangeCubeZoneSemantics,
    };

    try std.testing.expectEqual(room.scene.zones[0].index, transition.source_zone_index);
    try std.testing.expectEqual(semantics.destination_cube, transition.destination_cube);
    try std.testing.expectEqual(semantics.destination_x, transition.destination_world_position.x);
    try std.testing.expectEqual(semantics.destination_y, transition.destination_world_position.y);
    try std.testing.expectEqual(semantics.destination_z, transition.destination_world_position.z);
    try std.testing.expectEqual(semantics.yaw, transition.yaw);
    try std.testing.expectEqual(semantics.test_brick, transition.test_brick);
    try std.testing.expectEqual(semantics.dont_readjust_twinsen, transition.dont_readjust_twinsen);
}

test "runtime zone effects fail fast when multiple change-cube transitions trigger in one step" {
    const room = try room_fixtures.guarded22();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);

    var zone_membership: runtime_query.ContainingZoneSet = .{};
    try zone_membership.append(room.scene.zones[0]);
    try zone_membership.append(room.scene.zones[0]);

    try std.testing.expectError(
        error.MultipleRoomTransitionsTriggered,
        zone_effects.applyContainingZoneEffects(&current_session, zone_membership.slice()),
    );
    try std.testing.expectEqual(@as(?runtime_session.PendingRoomTransition, null), current_session.pendingRoomTransition());
}

test "runtime update tick reaches guarded 2/2 change-cube from the baked raw start via a bounded zone-recovery nudge" {
    const room = try room_fixtures.guarded22();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    const raw_start = current_session.heroWorldPosition();
    try current_session.submitHeroIntent(.{ .move_cardinal = .east });

    const tick_result = try runtime_update.tick(room, &current_session);

    try std.testing.expect(tick_result.consumed_hero_intent);
    try std.testing.expect(tick_result.triggered_room_transition);
    try std.testing.expectEqual(@as(usize, 0), tick_result.updated_object_count);
    try std.testing.expectEqual(@as(usize, 0), current_session.frame_index);

    switch (tick_result.locomotion_status) {
        .last_zone_recovery_accepted => |value| {
            try std.testing.expectEqual(locomotion.CardinalDirection.east, value.direction);
            try std.testing.expectEqual(raw_start.x + locomotion.raw_invalid_zone_entry_step_xz, value.hero_position.x);
            try std.testing.expectEqual(raw_start.y, value.hero_position.y);
            try std.testing.expectEqual(raw_start.z, value.hero_position.z);
            try std.testing.expect(zoneSetContainsIndex(value.zone_membership, room.scene.zones[0].index));
            try std.testing.expectEqual(current_session.heroWorldPosition(), value.hero_position);
        },
        else => return error.UnexpectedLocomotionStatus,
    }

    const transition = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;
    const semantics = switch (room.scene.zones[0].semantics) {
        .change_cube => |value| value,
        else => return error.ExpectedChangeCubeZoneSemantics,
    };

    try std.testing.expectEqual(room.scene.zones[0].index, transition.source_zone_index);
    try std.testing.expectEqual(semantics.destination_cube, transition.destination_cube);
    try std.testing.expectEqual(semantics.destination_x, transition.destination_world_position.x);
    try std.testing.expectEqual(semantics.destination_y, transition.destination_world_position.y);
    try std.testing.expectEqual(semantics.destination_z, transition.destination_world_position.z);
    try std.testing.expectEqual(semantics.yaw, transition.yaw);
    try std.testing.expectEqual(semantics.test_brick, transition.test_brick);
    try std.testing.expectEqual(semantics.dont_readjust_twinsen, transition.dont_readjust_twinsen);
}

test "runtime update tick fails fast until a pending room transition is committed" {
    const room = try room_fixtures.guarded22();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    try current_session.submitHeroIntent(.{ .move_cardinal = .east });

    const first_tick = try runtime_update.tick(room, &current_session);
    try std.testing.expect(first_tick.triggered_room_transition);
    const expected_transition = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;

    try std.testing.expectError(
        error.PendingRoomTransitionRequiresCommit,
        runtime_update.tick(room, &current_session),
    );
    try std.testing.expectEqual(@as(usize, 0), current_session.frame_index);
    try std.testing.expectEqual(expected_transition, current_session.pendingRoomTransition().?);
}

test "runtime update tick advances the bounded Sendell room-36 story-state sequence" {
    const room = try room_fixtures.guarded3636();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setMagicLevelAndRefill(2);
    current_session.setGameVar(sendell_ball_flag_index, 0);
    current_session.setGameVar(lightning_spell_flag_index, 1);

    try current_session.submitHeroIntent(.cast_lightning);
    const cast_tick = try runtime_update.tick(room, &current_session);
    try std.testing.expect(cast_tick.consumed_hero_intent);
    try std.testing.expect(!cast_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(usize, 1), cast_tick.updated_object_count);
    try std.testing.expectEqual(@as(usize, 1), current_session.frame_index);
    try std.testing.expectEqual(@as(u8, 2), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 0), current_session.magicPoint());
    try std.testing.expectEqual(@as(?i16, 513), current_session.currentDialogId());
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_first_dialog_ack, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try current_session.submitHeroIntent(.advance_story);
    const first_dialog_tick = try runtime_update.tick(room, &current_session);
    try std.testing.expect(first_dialog_tick.consumed_hero_intent);
    try std.testing.expect(!first_dialog_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(usize, 2), current_session.frame_index);
    try std.testing.expectEqual(@as(u8, 3), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 60), current_session.magicPoint());
    try std.testing.expectEqual(@as(i16, 0), current_session.gameVar(sendell_ball_flag_index));
    try std.testing.expectEqual(@as(?i16, 514), current_session.currentDialogId());
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_second_dialog_ack, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try current_session.submitHeroIntent(.advance_story);
    const second_dialog_tick = try runtime_update.tick(room, &current_session);
    try std.testing.expect(second_dialog_tick.consumed_hero_intent);
    try std.testing.expect(!second_dialog_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(usize, 3), current_session.frame_index);
    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(sendell_ball_flag_index));
    try std.testing.expectEqual(@as(?i16, 287), current_session.currentDialogId());
    try std.testing.expectEqual(runtime_session.SendellBallPhase.completed, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);
}

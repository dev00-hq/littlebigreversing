const std = @import("std");
const paths = @import("../foundation/paths.zig");
const reference_metadata = @import("../generated/reference_metadata.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const object_behavior = @import("object_behavior.zig");
const locomotion = @import("locomotion.zig");
const room_state = @import("room_state.zig");
const runtime_query = @import("world_query.zig");
const runtime_session = @import("session.zig");
const runtime_transition = @import("transition.zig");
const runtime_update = @import("update.zig");
const zone_effects = @import("zone_effects.zig");

const fixture_cell = locomotion.GridCell{ .x = 39, .z = 6 };
const reward_origin_world_position = locomotion.WorldPointSnapshot{
    .x = 21760,
    .y = 6656,
    .z = 3584,
};
const reward_floor_top_y: i32 = 25 * runtime_query.world_grid_span_y;
const reward_staging_cell = locomotion.GridCell{ .x = 39, .z = 10 };
const reward_scatter_cells = [_]locomotion.GridCell{
    .{ .x = 39, .z = 6 },
    .{ .x = 40, .z = 6 },
    .{ .x = 41, .z = 6 },
    .{ .x = 42, .z = 6 },
    .{ .x = 43, .z = 6 },
    .{ .x = 39, .z = 7 },
    .{ .x = 40, .z = 7 },
    .{ .x = 41, .z = 7 },
    .{ .x = 42, .z = 7 },
    .{ .x = 43, .z = 7 },
};
const sendell_ball_flag_index: u8 = reference_metadata.sendell_ball_flag.index;
const lightning_spell_flag_index: u8 = reference_metadata.lightning_spell_flag.index;
const reward_quantity_per_instance: u8 = 5;

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

fn rewardLandingWorldPosition(cell: locomotion.GridCell) locomotion.WorldPointSnapshot {
    return .{
        .x = @as(i32, @intCast(cell.x)) * runtime_query.world_grid_span_xz + @divFloor(runtime_query.world_grid_span_xz, 2),
        .y = reward_floor_top_y,
        .z = @as(i32, @intCast(cell.z)) * runtime_query.world_grid_span_xz + @divFloor(runtime_query.world_grid_span_xz, 2),
    };
}

fn rewardStagingWorldPosition() locomotion.WorldPointSnapshot {
    return rewardLandingWorldPosition(reward_staging_cell);
}

fn standablePositionAtWorldXZ(
    room: *const room_state.RoomSnapshot,
    world_x: i32,
    world_z: i32,
) !locomotion.WorldPointSnapshot {
    const query = runtime_query.init(room);
    const cell = try query.gridCellAtWorldPoint(world_x, world_z);
    const surface = try query.cellTopSurface(cell.x, cell.z);
    if (runtime_query.standabilityForSurface(surface) != .standable) {
        return error.WorldPointNotStandable;
    }
    return .{
        .x = world_x,
        .y = surface.top_y,
        .z = world_z,
    };
}

fn primeScene1919RewardBurst(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !usize {
    _ = try object_behavior.stepSupportedObjects(room, current_session);
    current_session.advanceFrameIndex();
    const primed_state = current_session.objectBehaviorStateByIndexPtr(2) orelse return error.MissingRuntimeObjectBehaviorState;
    primed_state.last_hit_by = 1;

    var reward_tick: ?usize = null;
    var tick_index: usize = 1;
    while (tick_index < 16) : (tick_index += 1) {
        _ = try object_behavior.stepSupportedObjects(room, current_session);
        current_session.advanceFrameIndex();
        if (current_session.bonusSpawnEvents().len != 0) {
            reward_tick = tick_index + 1;
            break;
        }
    }

    return reward_tick orelse return error.MissingScene1919RewardBurst;
}

fn allRewardsSettled(current_session: runtime_session.Session) bool {
    for (current_session.rewardCollectibles()) |collectible| {
        if (!collectible.settled) return false;
    }
    return true;
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

    const reward_tick = try primeScene1919RewardBurst(room, &current_session);

    try std.testing.expectEqual(@as(usize, 13), reward_tick);
    try std.testing.expectEqual(@as(u8, 1), current_session.cubeVar(1));
    try std.testing.expectEqual(reward_scatter_cells.len, current_session.bonusSpawnEvents().len);
    try std.testing.expectEqual(reward_scatter_cells.len, current_session.rewardCollectibles().len);

    for (current_session.bonusSpawnEvents()) |bonus_event| {
        try std.testing.expectEqual(@as(usize, 12), bonus_event.frame_index);
        try std.testing.expectEqual(@as(usize, 2), bonus_event.source_object_index);
        try std.testing.expectEqual(runtime_session.RuntimeBonusKind.magic, bonus_event.kind);
        try std.testing.expectEqual(@as(i16, 5), bonus_event.sprite_index);
        try std.testing.expectEqual(reward_quantity_per_instance, bonus_event.quantity);
    }

    for (current_session.rewardCollectibles(), reward_scatter_cells, 0..) |reward_collectible, expected_cell, scatter_index| {
        const expected_landing_position = rewardLandingWorldPosition(expected_cell);
        try std.testing.expectEqual(@as(usize, 12), reward_collectible.spawn_frame_index);
        try std.testing.expectEqual(@as(usize, 2), reward_collectible.source_object_index);
        try std.testing.expectEqual(runtime_session.RuntimeBonusKind.magic, reward_collectible.kind);
        try std.testing.expectEqual(@as(i16, 5), reward_collectible.sprite_index);
        try std.testing.expectEqual(reward_quantity_per_instance, reward_collectible.quantity);
        try std.testing.expectEqual(expected_cell, reward_collectible.admitted_surface_cell);
        try std.testing.expectEqual(reward_floor_top_y, reward_collectible.admitted_surface_top_y);
        try std.testing.expectEqual(@as(u8, @intCast(scatter_index)), reward_collectible.scatter_slot);
        try std.testing.expectEqual(@as(u8, 0), reward_collectible.rebound_count);
        try std.testing.expect(!reward_collectible.settled);
        try std.testing.expectEqual(reward_origin_world_position, reward_collectible.world_position);
        try std.testing.expectEqual(reward_origin_world_position, reward_collectible.motion_start_world_position);
        try std.testing.expectEqual(expected_landing_position, reward_collectible.motion_target_world_position);
    }

    const rewarded_state = current_session.objectBehaviorStateByIndex(2) orelse return error.MissingRuntimeObjectBehaviorState;
    try std.testing.expectEqual(@as(u8, reward_scatter_cells.len), rewarded_state.emitted_bonus_count);
    try std.testing.expect(rewarded_state.bonus_exhausted);
    try std.testing.expectEqual(@as(u8, @intFromEnum(life_program.LifeOpcode.LM_SNIF)), rewarded_state.life_bytes[51]);

    _ = try object_behavior.stepSupportedObjects(room, &current_session);
    current_session.advanceFrameIndex();
    const recovered_state = current_session.objectBehaviorStateByIndex(2) orelse return error.MissingRuntimeObjectBehaviorState;
    try std.testing.expectEqual(@as(u8, @intFromEnum(life_program.LifeOpcode.LM_SWIF)), recovered_state.life_bytes[51]);
    try std.testing.expectEqual(reward_scatter_cells.len, current_session.bonusSpawnEvents().len);
}

test "runtime update tick keeps 19/19 sewer bonuses unpickable until their bounded scatter settles" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setMagicLevelAndRefill(3);
    current_session.setMagicPoint(10);
    current_session.setHeroWorldPosition(.{
        .x = 2500,
        .y = 1000,
        .z = 1000,
    });

    const reward_tick = try primeScene1919RewardBurst(room, &current_session);

    try std.testing.expectEqual(@as(usize, 13), reward_tick);
    try std.testing.expectEqual(@as(u8, 10), current_session.magicPoint());
    try std.testing.expectEqual(reward_scatter_cells.len, current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 0), current_session.rewardPickupEvents().len);

    const first_landing_position = rewardLandingWorldPosition(reward_scatter_cells[0]);
    current_session.setHeroWorldPosition(first_landing_position);
    const first_tick = try runtime_update.tick(room, &current_session);

    try std.testing.expect(!first_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(u8, 10), current_session.magicPoint());
    try std.testing.expectEqual(reward_scatter_cells.len, current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 0), current_session.rewardPickupEvents().len);
    try std.testing.expect(!current_session.rewardCollectibles()[0].settled);
    try std.testing.expect(!std.meta.eql(current_session.rewardCollectibles()[0].world_position, reward_origin_world_position));
    try std.testing.expect(!std.meta.eql(current_session.rewardCollectibles()[0].world_position, first_landing_position));
}

test "runtime update tick resolves the first settled 19/19 magic bonus into the observed capped +10 seam behavior" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setMagicLevelAndRefill(2);
    current_session.setMagicPoint(38);
    current_session.setHeroWorldPosition(.{
        .x = 2500,
        .y = 1000,
        .z = 1000,
    });

    _ = try primeScene1919RewardBurst(room, &current_session);
    while (!allRewardsSettled(current_session)) {
        current_session.setHeroWorldPosition(rewardStagingWorldPosition());
        _ = try runtime_update.tick(room, &current_session);
    }

    const first_landing_position = current_session.rewardCollectibles()[0].world_position;
    try std.testing.expectEqual(
        runtime_query.MoveTargetStatus.allowed,
        runtime_query.init(room).evaluateHeroMoveTarget(first_landing_position).status,
    );
    current_session.setHeroWorldPosition(first_landing_position);
    const pickup_tick = try runtime_update.tick(room, &current_session);

    try std.testing.expect(!pickup_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(u8, 40), current_session.magicPoint());
    try std.testing.expectEqual(reward_scatter_cells.len - 1, current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardPickupEvents().len);

    const pickup_event = current_session.rewardPickupEvents()[0];
    try std.testing.expectEqual(@as(usize, 16), pickup_event.pickup_frame_index);
    try std.testing.expectEqual(@as(usize, 2), pickup_event.source_object_index);
    try std.testing.expectEqual(runtime_session.RuntimeBonusKind.magic, pickup_event.kind);
    try std.testing.expectEqual(@as(i16, 5), pickup_event.sprite_index);
    try std.testing.expectEqual(reward_quantity_per_instance, pickup_event.quantity);
    try std.testing.expectEqual(first_landing_position, pickup_event.world_position);
}

test "runtime update tick resolves a settled little-key collectible into the key inventory counter" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);

    const key_position = rewardLandingWorldPosition(reward_scatter_cells[0]);
    try current_session.appendRewardCollectible(.{
        .spawn_frame_index = current_session.frame_index,
        .source_object_index = 7,
        .kind = .little_key,
        .sprite_index = 6,
        .quantity = 1,
        .admitted_surface_cell = reward_scatter_cells[0],
        .admitted_surface_top_y = reward_floor_top_y,
        .scatter_slot = 0,
        .rebound_count = 0,
        .settled = true,
        .motion_start_world_position = key_position,
        .motion_target_world_position = key_position,
        .motion_total_ticks = 0,
        .motion_ticks_remaining = 0,
        .motion_arc_height = 0,
        .world_position = key_position,
    });
    current_session.setHeroWorldPosition(key_position);

    const pickup_tick = try runtime_update.tick(room, &current_session);

    try std.testing.expect(!pickup_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(u8, 1), current_session.littleKeyCount());
    try std.testing.expectEqual(@as(usize, 0), current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardPickupEvents().len);

    const pickup_event = current_session.rewardPickupEvents()[0];
    try std.testing.expectEqual(@as(usize, 0), pickup_event.pickup_frame_index);
    try std.testing.expectEqual(@as(usize, 7), pickup_event.source_object_index);
    try std.testing.expectEqual(runtime_session.RuntimeBonusKind.little_key, pickup_event.kind);
    try std.testing.expectEqual(@as(i16, 6), pickup_event.sprite_index);
    try std.testing.expectEqual(@as(u8, 1), pickup_event.quantity);
    try std.testing.expectEqual(key_position, pickup_event.world_position);
}

test "runtime update tick denies the remaining settled 19/19 sewer bonuses after the first accepted cap-fill pickup" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setMagicLevelAndRefill(2);
    current_session.setMagicPoint(38);
    current_session.setHeroWorldPosition(.{
        .x = 2500,
        .y = 1000,
        .z = 1000,
    });

    _ = try primeScene1919RewardBurst(room, &current_session);
    while (!allRewardsSettled(current_session)) {
        current_session.setHeroWorldPosition(rewardStagingWorldPosition());
        _ = try runtime_update.tick(room, &current_session);
    }

    const accepted_landing_position = current_session.rewardCollectibles()[0].world_position;
    current_session.setHeroWorldPosition(accepted_landing_position);
    _ = try runtime_update.tick(room, &current_session);

    try std.testing.expectEqual(@as(u8, 40), current_session.magicPoint());
    try std.testing.expectEqual(reward_scatter_cells.len - 1, current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardPickupEvents().len);

    const denied_position = current_session.rewardCollectibles()[0].world_position;
    current_session.setHeroWorldPosition(denied_position);
    const denied_tick = try runtime_update.tick(room, &current_session);

    try std.testing.expect(!denied_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(u8, 40), current_session.magicPoint());
    try std.testing.expectEqual(reward_scatter_cells.len - 1, current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardPickupEvents().len);
    try std.testing.expect(!current_session.rewardCollectibles()[0].settled);
    try std.testing.expect(!std.meta.eql(current_session.rewardCollectibles()[0].motion_target_world_position, denied_position));

    current_session.setHeroWorldPosition(rewardStagingWorldPosition());
    _ = try runtime_update.tick(room, &current_session);
    try std.testing.expect(!std.meta.eql(current_session.rewardCollectibles()[0].world_position, denied_position));
    try std.testing.expectEqual(@as(u8, 40), current_session.magicPoint());
}

test "runtime zone effects record a generic change-cube transition from guarded 2/2 zone semantics" {
    const room = try room_fixtures.guarded22();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{
        .x = 9756,
        .y = 1024,
        .z = 782,
    });

    var zone_membership: runtime_query.ContainingZoneSet = .{};
    try zone_membership.append(room.scene.zones[0]);
    const effect_summary = try zone_effects.applyContainingZoneEffects(room, &current_session, zone_membership.slice());

    try std.testing.expect(effect_summary.triggered_room_transition);
    const transition = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;
    const semantics = switch (room.scene.zones[0].semantics) {
        .change_cube => |value| value,
        else => return error.ExpectedChangeCubeZoneSemantics,
    };

    try std.testing.expectEqual(room.scene.zones[0].index, transition.source_zone_index);
    try std.testing.expectEqual(semantics.destination_cube, transition.destination_cube);
    try std.testing.expectEqual(runtime_session.PendingRoomTransitionDestinationPositionKind.provisional_zone_relative, transition.destination_world_position_kind);
    try std.testing.expectEqual(@as(i32, 2588), transition.destination_world_position.x);
    try std.testing.expectEqual(@as(i32, 2048), transition.destination_world_position.y);
    try std.testing.expectEqual(@as(i32, 3342), transition.destination_world_position.z);
    try std.testing.expectEqual(semantics.yaw, transition.yaw);
    try std.testing.expectEqual(semantics.test_brick, transition.test_brick);
    try std.testing.expectEqual(semantics.dont_readjust_twinsen, transition.dont_readjust_twinsen);
}

test "runtime zone effects consume one key and preserve source offset on the scene-2 house-to-cellar door" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    const door_zone = room.scene.zones[0];
    const semantics = switch (door_zone.semantics) {
        .change_cube => |value| value,
        else => return error.ExpectedChangeCubeZoneSemantics,
    };
    try std.testing.expectEqual(@as(i32, 9728), door_zone.x0);
    try std.testing.expectEqual(@as(i32, 1024), door_zone.y0);
    try std.testing.expectEqual(@as(i32, 512), door_zone.z0);
    try std.testing.expectEqual(@as(i32, 2560), semantics.destination_x);
    try std.testing.expectEqual(@as(i32, 2048), semantics.destination_y);
    try std.testing.expectEqual(@as(i32, 3072), semantics.destination_z);

    const samples = [_]struct {
        source: locomotion.WorldPointSnapshot,
        expected_destination: locomotion.WorldPointSnapshot,
    }{
        .{
            .source = .{ .x = 9730, .y = 1025, .z = 762 },
            .expected_destination = .{ .x = 2562, .y = 2049, .z = 3322 },
        },
        .{
            .source = .{ .x = 9731, .y = 1025, .z = 1189 },
            .expected_destination = .{ .x = 2563, .y = 2049, .z = 3749 },
        },
    };

    for (samples) |sample| {
        var current_session = try initSession(&room);
        defer current_session.deinit(std.testing.allocator);
        current_session.setHeroWorldPosition(sample.source);
        current_session.setLittleKeyCount(1);

        var zone_membership: runtime_query.ContainingZoneSet = .{};
        try zone_membership.append(door_zone);
        const effect_summary = try zone_effects.applyContainingZoneEffects(&room, &current_session, zone_membership.slice());

        try std.testing.expect(effect_summary.triggered_room_transition);
        try std.testing.expectEqual(@as(?zone_effects.SecretRoomDoorEvent, .house_consumed_key), effect_summary.secret_room_door_event);
        try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
        const transition = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;
        try std.testing.expectEqual(door_zone.index, transition.source_zone_index);
        try std.testing.expectEqual(@as(i16, 0), transition.destination_cube);
        try std.testing.expectEqual(runtime_session.PendingRoomTransitionDestinationPositionKind.provisional_zone_relative, transition.destination_world_position_kind);
        try std.testing.expectEqual(sample.expected_destination, transition.destination_world_position);
        try std.testing.expectEqual(semantics.yaw, transition.yaw);
        try std.testing.expectEqual(semantics.test_brick, transition.test_brick);
        try std.testing.expectEqual(semantics.dont_readjust_twinsen, transition.dont_readjust_twinsen);
    }

    var locked_session = try initSession(&room);
    defer locked_session.deinit(std.testing.allocator);
    locked_session.setHeroWorldPosition(samples[0].source);
    var zone_membership: runtime_query.ContainingZoneSet = .{};
    try zone_membership.append(door_zone);
    const locked_effect = try zone_effects.applyContainingZoneEffects(&room, &locked_session, zone_membership.slice());
    try std.testing.expect(!locked_effect.triggered_room_transition);
    try std.testing.expectEqual(@as(?zone_effects.SecretRoomDoorEvent, .house_locked_no_key), locked_effect.secret_room_door_event);
    try std.testing.expectEqual(@as(?runtime_session.PendingRoomTransition, null), locked_session.pendingRoomTransition());
}

test "runtime zone effects return from cellar to house without consuming a key" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{ .x = 3056, .y = 2048, .z = 3659 });

    const without_key = try zone_effects.applyContainingZoneEffects(&room, &current_session, &.{});
    try std.testing.expect(without_key.triggered_room_transition);
    try std.testing.expectEqual(@as(?zone_effects.SecretRoomDoorEvent, .cellar_return_free), without_key.secret_room_door_event);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    current_session.clearPendingRoomTransition();

    current_session.setHeroWorldPosition(.{ .x = 3056, .y = 2048, .z = 3659 });
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());

    current_session.setLittleKeyCount(1);
    const with_key = try zone_effects.applyContainingZoneEffects(&room, &current_session, &.{});

    try std.testing.expect(with_key.triggered_room_transition);
    try std.testing.expectEqual(@as(?zone_effects.SecretRoomDoorEvent, .cellar_return_free), with_key.secret_room_door_event);
    try std.testing.expectEqual(@as(u8, 1), current_session.littleKeyCount());
    const transition = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;
    try std.testing.expectEqual(@as(usize, 0), transition.source_zone_index);
    try std.testing.expectEqual(@as(i16, 1), transition.destination_cube);
    try std.testing.expectEqual(runtime_session.PendingRoomTransitionDestinationPositionKind.provisional_zone_relative, transition.destination_world_position_kind);
    try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 9725, .y = 1278, .z = 1098 }, transition.destination_world_position);
    try std.testing.expectEqual(@as(i32, 0), transition.yaw);
    try std.testing.expect(!transition.test_brick);
    try std.testing.expect(!transition.dont_readjust_twinsen);
}

test "runtime 0013 key seam carries through update-owned pickup, keyed cellar entry, and free return" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);

    current_session.setHeroWorldPosition(.{ .x = 1280, .y = 2048, .z = 5376 });
    try current_session.submitHeroIntent(.default_action);
    const spawn_tick = try runtime_update.tick(&room, &current_session);
    try std.testing.expect(spawn_tick.consumed_hero_intent);
    try std.testing.expect(!spawn_tick.triggered_room_transition);
    switch (spawn_tick.locomotion_status) {
        .raw_invalid_current => |value| {
            try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_height_mismatch, value.reason);
            try std.testing.expectEqual(@as(usize, 1), value.zone_membership.slice().len);
            try std.testing.expectEqual(.scenario, value.zone_membership.slice()[0].kind);
            try std.testing.expectEqual(@as(i16, 0), value.zone_membership.slice()[0].num);
        },
        else => return error.UnexpectedLocomotionStatus,
    }

    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(0));
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardCollectibles().len);

    current_session.setHeroWorldPosition(try standablePositionAtWorldXZ(&room, 3826, 4366));
    var pickup_attempts: usize = 0;
    while (current_session.littleKeyCount() == 0 and pickup_attempts < 6) : (pickup_attempts += 1) {
        const pickup_tick = try runtime_update.tick(&room, &current_session);
        try std.testing.expect(!pickup_tick.triggered_room_transition);
    }

    try std.testing.expectEqual(@as(u8, 1), current_session.littleKeyCount());
    try std.testing.expectEqual(@as(usize, 0), current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardPickupEvents().len);
    try std.testing.expectEqual(runtime_session.RuntimeBonusKind.little_key, current_session.rewardPickupEvents()[0].kind);

    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    current_session.setHeroWorldPosition(.{ .x = 9730, .y = 1025, .z = 762 });
    var door_zone_membership: runtime_query.ContainingZoneSet = .{};
    try door_zone_membership.append(room.scene.zones[0]);
    const forward_effect = try zone_effects.applyContainingZoneEffects(&room, &current_session, door_zone_membership.slice());
    try std.testing.expect(forward_effect.triggered_room_transition);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());

    const forward_transition = try runtime_transition.applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        locomotion_status,
    );
    switch (forward_transition) {
        .committed => |value| {
            try std.testing.expectEqual(@as(usize, 2), value.destination_scene_entry_index);
            try std.testing.expectEqual(@as(usize, 0), value.destination_background_entry_index);
            try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 2562, .y = 2048, .z = 3322 }, value.hero_position);
        },
        .rejected => return error.UnexpectedRejectedRoomTransition,
    }
    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 0), room.background.entry_index);

    locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    current_session.setHeroWorldPosition(.{ .x = 3056, .y = 2048, .z = 3659 });
    const reverse_effect = try zone_effects.applyContainingZoneEffects(&room, &current_session, &.{});
    try std.testing.expect(reverse_effect.triggered_room_transition);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());

    const reverse_transition = try runtime_transition.applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        locomotion_status,
    );
    switch (reverse_transition) {
        .committed => |value| {
            try std.testing.expectEqual(@as(usize, 2), value.destination_scene_entry_index);
            try std.testing.expectEqual(@as(usize, 1), value.destination_background_entry_index);
            try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 9725, .y = 1024, .z = 1098 }, value.hero_position);
        },
        .rejected => return error.UnexpectedRejectedRoomTransition,
    }
    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 1), room.background.entry_index);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
}

test "guarded 2/2 has one enabled cube-0 change-cube seam and it is zone 0" {
    const room = try room_fixtures.guarded22();

    var matching_zone_count: usize = 0;
    var matching_zone_index: ?usize = null;
    for (room.scene.zones) |zone| {
        const semantics = switch (zone.semantics) {
            .change_cube => |value| value,
            else => continue,
        };
        if (!semantics.initially_on) continue;
        if (semantics.destination_cube != 0) continue;
        matching_zone_count += 1;
        matching_zone_index = zone.index;
    }

    try std.testing.expectEqual(@as(usize, 1), matching_zone_count);
    try std.testing.expectEqual(@as(?usize, room.scene.zones[0].index), matching_zone_index);
    try std.testing.expectEqual(@as(usize, 0), room.scene.zones[0].index);
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
        zone_effects.applyContainingZoneEffects(room, &current_session, zone_membership.slice()),
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
    try std.testing.expectEqual(runtime_session.PendingRoomTransitionDestinationPositionKind.provisional_zone_relative, transition.destination_world_position_kind);
    try std.testing.expectEqual(@as(i32, 2588), transition.destination_world_position.x);
    try std.testing.expectEqual(@as(i32, 2048), transition.destination_world_position.y);
    try std.testing.expectEqual(@as(i32, 3342), transition.destination_world_position.z);
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
    try std.testing.expectEqual(@as(u8, 3), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 60), current_session.magicPoint());
    try std.testing.expectEqual(@as(?i16, 3), current_session.currentDialogId());
    const first_slice = object_behavior.currentSendellDialogSlice(current_session).?;
    try std.testing.expectEqual(@as(u8, 1), first_slice.page_number);
    try std.testing.expectEqualStrings(
        "You just found Sendell's Ball. Now you have reached a new level of magic: Red Ball. It will also enable ",
        first_slice.visible_text,
    );
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_first_dialog_ack, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try current_session.submitHeroIntent(.advance_story);
    const first_dialog_tick = try runtime_update.tick(room, &current_session);
    try std.testing.expect(first_dialog_tick.consumed_hero_intent);
    try std.testing.expect(!first_dialog_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(usize, 2), current_session.frame_index);
    try std.testing.expectEqual(@as(u8, 3), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 60), current_session.magicPoint());
    try std.testing.expectEqual(@as(i16, 0), current_session.gameVar(sendell_ball_flag_index));
    try std.testing.expectEqual(@as(?i16, 3), current_session.currentDialogId());
    const second_slice = object_behavior.currentSendellDialogSlice(current_session).?;
    try std.testing.expectEqual(@as(u8, 2), second_slice.page_number);
    try std.testing.expectEqualStrings("Sendell to contact you in case of danger.", second_slice.visible_text);
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_second_dialog_ack, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try current_session.submitHeroIntent(.advance_story);
    const second_dialog_tick = try runtime_update.tick(room, &current_session);
    try std.testing.expect(second_dialog_tick.consumed_hero_intent);
    try std.testing.expect(!second_dialog_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(usize, 3), current_session.frame_index);
    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(sendell_ball_flag_index));
    try std.testing.expectEqual(@as(?i16, null), current_session.currentDialogId());
    try std.testing.expectEqual(@as(?object_behavior.SendellDialogSlice, null), object_behavior.currentSendellDialogSlice(current_session));
    try std.testing.expectEqual(runtime_session.SendellBallPhase.completed, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);
}

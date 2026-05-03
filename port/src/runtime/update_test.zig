const std = @import("std");
const paths = @import("../foundation/paths.zig");
const reference_metadata = @import("../generated/reference_metadata.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const track_program = @import("../game_data/scene/track_program.zig");
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

fn emptyBehaviorSeed(
    object_index: usize,
    sprite: i16,
    gen_anim: i16,
) runtime_session.ObjectBehaviorSeedState {
    return .{
        .index = object_index,
        .sprite = sprite,
        .gen_anim = gen_anim,
        .track_bytes = &.{},
        .track_instructions = &[_]track_program.TrackInstruction{},
        .life_bytes = &.{},
        .life_instructions = &[_]life_program.LifeInstruction{},
    };
}

fn magicBallProjectileWithScript(script: runtime_session.MagicBallProjectileScript) runtime_session.MagicBallProjectile {
    return .{
        .launch_frame_index = 0,
        .mode = .normal,
        .script = script,
        .world_position = .{ .x = 100, .y = 200, .z = 300 },
        .origin_world_position = .{ .x = 90, .y = 190, .z = 290 },
        .sprite_index = 8,
        .vx = -55,
        .vy = 18,
        .vz = 81,
        .flags = 33038,
        .timeout = 0,
        .divers = 0,
    };
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

fn requireJsonField(value: std.json.Value, field: []const u8) !std.json.Value {
    return switch (value) {
        .object => |object| object.get(field) orelse error.MissingJsonField,
        else => error.ExpectedJsonObject,
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

fn jsonInteger(value: std.json.Value) !i32 {
    return switch (value) {
        .integer => |actual| std.math.cast(i32, actual) orelse error.JsonIntegerOutOfRange,
        else => error.ExpectedJsonInteger,
    };
}

fn expectJsonPoint(value: std.json.Value, expected: locomotion.WorldPointSnapshot) !void {
    try std.testing.expectEqual(expected.x, try jsonInteger(try requireJsonField(value, "x")));
    try std.testing.expectEqual(expected.y, try jsonInteger(try requireJsonField(value, "y")));
    try std.testing.expectEqual(expected.z, try jsonInteger(try requireJsonField(value, "z")));
}

fn jsonPoint(value: std.json.Value) !locomotion.WorldPointSnapshot {
    return .{
        .x = try jsonInteger(try requireJsonField(value, "x")),
        .y = try jsonInteger(try requireJsonField(value, "y")),
        .z = try jsonInteger(try requireJsonField(value, "z")),
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

test "runtime update tick keeps settled 19/19 rewards gated to their admitted landing cell" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setMagicLevelAndRefill(2);
    current_session.setMagicPoint(30);

    const reward_position = rewardLandingWorldPosition(reward_scatter_cells[0]);
    try current_session.appendRewardCollectible(.{
        .spawn_frame_index = current_session.frame_index,
        .source_object_index = 2,
        .kind = .magic,
        .sprite_index = 5,
        .quantity = reward_quantity_per_instance,
        .admitted_surface_cell = reward_scatter_cells[0],
        .admitted_surface_top_y = reward_floor_top_y,
        .scatter_slot = 0,
        .rebound_count = 0,
        .settled = true,
        .motion_start_world_position = reward_position,
        .motion_target_world_position = reward_position,
        .motion_total_ticks = 0,
        .motion_ticks_remaining = 0,
        .motion_arc_height = 0,
        .world_position = reward_position,
    });

    const adjacent_cell = locomotion.GridCell{
        .x = reward_scatter_cells[0].x + 1,
        .z = reward_scatter_cells[0].z,
    };
    const adjacent_surface = try runtime_query.init(room).cellTopSurface(adjacent_cell.x, adjacent_cell.z);
    try std.testing.expectEqual(reward_floor_top_y, adjacent_surface.top_y);
    current_session.setHeroWorldPosition(.{
        .x = reward_position.x + 256,
        .y = adjacent_surface.top_y,
        .z = reward_position.z,
    });

    const adjacent_tick = try runtime_update.tick(room, &current_session);
    try std.testing.expect(!adjacent_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(u8, 30), current_session.magicPoint());
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 0), current_session.rewardPickupEvents().len);

    current_session.setHeroWorldPosition(reward_position);
    _ = try runtime_update.tick(room, &current_session);

    try std.testing.expectEqual(@as(u8, 40), current_session.magicPoint());
    try std.testing.expectEqual(@as(usize, 0), current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardPickupEvents().len);
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

test "runtime zone effects consume one key at the scene-2 house door unlock before the cellar transition" {
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

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{ .x = 3050, .y = 2048, .z = 4034 });
    current_session.setLittleKeyCount(1);

    const unlock_effect = try zone_effects.applyContainingZoneEffects(&room, &current_session, &.{});
    try std.testing.expect(!unlock_effect.triggered_room_transition);
    try std.testing.expectEqual(@as(?zone_effects.SecretRoomDoorEvent, .house_consumed_key), unlock_effect.secret_room_door_event);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    try std.testing.expect(current_session.secretRoomHouseDoorUnlocked());
    try std.testing.expectEqual(@as(?runtime_session.PendingRoomTransition, null), current_session.pendingRoomTransition());

    current_session.setHeroWorldPosition(.{ .x = 9730, .y = 1025, .z = 762 });
    var zone_membership: runtime_query.ContainingZoneSet = .{};
    try zone_membership.append(door_zone);
    const transition_effect = try zone_effects.applyContainingZoneEffects(&room, &current_session, zone_membership.slice());

    try std.testing.expect(transition_effect.triggered_room_transition);
    try std.testing.expectEqual(@as(?zone_effects.SecretRoomDoorEvent, null), transition_effect.secret_room_door_event);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    const transition = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;
    try std.testing.expectEqual(door_zone.index, transition.source_zone_index);
    try std.testing.expectEqual(@as(i16, 0), transition.destination_cube);
    try std.testing.expectEqual(runtime_session.PendingRoomTransitionDestinationPositionKind.final_landing, transition.destination_world_position_kind);
    try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 9724, .y = 1024, .z = 782 }, transition.destination_world_position);
    try std.testing.expectEqual(@as(?locomotion.WorldPointSnapshot, locomotion.WorldPointSnapshot{ .x = 9723, .y = 1277, .z = 762 }), transition.runtime_new_position);
    try std.testing.expectEqual(semantics.yaw, transition.yaw);
    try std.testing.expectEqual(semantics.test_brick, transition.test_brick);
    try std.testing.expectEqual(semantics.dont_readjust_twinsen, transition.dont_readjust_twinsen);

    var locked_session = try initSession(&room);
    defer locked_session.deinit(std.testing.allocator);
    locked_session.setHeroWorldPosition(.{ .x = 3050, .y = 2048, .z = 4034 });
    const locked_effect = try zone_effects.applyContainingZoneEffects(&room, &locked_session, &.{});
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
    current_session.setHeroWorldPosition(.{ .x = 9730, .y = 1025, .z = 1126 });

    const without_key = try zone_effects.applyContainingZoneEffects(&room, &current_session, &.{});
    try std.testing.expect(without_key.triggered_room_transition);
    try std.testing.expectEqual(@as(?zone_effects.SecretRoomDoorEvent, .cellar_return_free), without_key.secret_room_door_event);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    current_session.clearPendingRoomTransition();

    current_session.setHeroWorldPosition(.{ .x = 9730, .y = 1025, .z = 1126 });
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
    try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 2562, .y = 2049, .z = 3686 }, transition.destination_world_position);
    try std.testing.expectEqual(@as(i32, 0), transition.yaw);
    try std.testing.expect(!transition.test_brick);
    try std.testing.expect(!transition.dont_readjust_twinsen);
}

test "runtime 0013 key seam carries through update-owned pickup, keyed cellar entry, and free return" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const fixture_path = try std.fs.path.join(allocator, &.{ resolved.repo_root, "tools/fixtures/phase5_0013_runtime_proof.json" });
    defer allocator.free(fixture_path);
    const fixture_json = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        fixture_path,
        allocator,
        .limited(64 * 1024),
    );
    defer allocator.free(fixture_json);
    var parsed_fixture = try std.json.parseFromSlice(std.json.Value, allocator, fixture_json, .{});
    defer parsed_fixture.deinit();

    const fixture = parsed_fixture.value;
    try expectJsonString(try requireJsonField(fixture, "schema_version"), "phase5-0013-runtime-proof-v1");
    const generated_save = try requireJsonField(fixture, "generated_save");
    try expectJsonString(
        try requireJsonField(generated_save, "game_pathname"),
        "SAVE\\scene2-bg1-key-midpoint-facing-key.LBA",
    );
    try expectJsonString(
        try requireJsonField(generated_save, "player_name"),
        "scene2-bg1-key-midpoint-facing-key",
    );
    try expectJsonInteger(try requireJsonField(generated_save, "num_version"), 0xA4);
    const start_pose = try requireJsonField(generated_save, "start_pose");
    try expectJsonInteger(try requireJsonField(start_pose, "active_cube"), 0);

    const key = try requireJsonField(fixture, "key");
    const key_spawn_extra = try requireJsonField(key, "spawn_extra");
    const key_landing = try jsonPoint(try requireJsonField(key, "landing"));
    const key_pickup = try requireJsonField(key, "pickup");
    const door = try requireJsonField(fixture, "door");
    const door_source = try requireJsonField(door, "source");
    const door_target = try requireJsonField(door, "target");
    const door_key_consumed = try requireJsonField(door, "key_consumed");
    const door_key_consumed_hero = try requireJsonField(door_key_consumed, "hero");
    const cellar_transition = try requireJsonField(door, "cellar_transition");
    const cellar_transition_new_pos = try jsonPoint(try requireJsonField(cellar_transition, "new_pos"));
    const ret = try requireJsonField(fixture, "return");
    const return_transition = try requireJsonField(ret, "transition");
    const return_probe_position = try jsonPoint(try requireJsonField(return_transition, "hero_before_commit"));
    const return_new_pos = try jsonPoint(try requireJsonField(return_transition, "new_pos"));
    const return_final_house = try requireJsonField(ret, "final_house");
    const return_final_house_hero = try jsonPoint(try requireJsonField(return_final_house, "hero"));

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);
    try expectJsonInteger(try requireJsonField(door_source, "scene"), @intCast(room.scene.entry_index));
    try expectJsonInteger(try requireJsonField(door_source, "background"), @intCast(room.background.entry_index));

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);

    current_session.setHeroWorldPosition(try jsonPoint(start_pose));
    try current_session.submitHeroIntent(.default_action);
    const spawn_tick = try runtime_update.tick(&room, &current_session);
    try std.testing.expect(spawn_tick.consumed_hero_intent);
    try std.testing.expect(!spawn_tick.triggered_room_transition);
    switch (spawn_tick.locomotion_status) {
        .raw_invalid_current => |value| {
            try std.testing.expectEqual(runtime_query.MoveTargetStatus.target_height_mismatch, value.reason);
            try std.testing.expectEqual(@as(usize, 0), value.zone_membership.slice().len);
        },
        else => return error.UnexpectedLocomotionStatus,
    }

    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(0));
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardCollectibles().len);
    try expectJsonInteger(try requireJsonField(key_spawn_extra, "sprite"), current_session.rewardCollectibles()[0].sprite_index);
    try expectJsonInteger(try requireJsonField(key_spawn_extra, "divers"), current_session.rewardCollectibles()[0].quantity);
    try expectJsonPoint(try requireJsonField(key_spawn_extra, "origin"), current_session.rewardCollectibles()[0].motion_start_world_position);

    current_session.setHeroWorldPosition(try standablePositionAtWorldXZ(&room, key_landing.x, key_landing.z));
    var pickup_attempts: usize = 0;
    while (current_session.littleKeyCount() == 0 and pickup_attempts < 6) : (pickup_attempts += 1) {
        const pickup_tick = try runtime_update.tick(&room, &current_session);
        try std.testing.expect(!pickup_tick.triggered_room_transition);
    }

    try std.testing.expectEqual(@as(u8, 1), current_session.littleKeyCount());
    try std.testing.expectEqual(@as(usize, 0), current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardPickupEvents().len);
    try std.testing.expectEqual(runtime_session.RuntimeBonusKind.little_key, current_session.rewardPickupEvents()[0].kind);
    try expectJsonInteger(try requireJsonField(key_pickup, "nb_little_keys_after"), current_session.littleKeyCount());
    try expectJsonInteger(try requireJsonField(key_pickup, "key_extras_after"), @intCast(current_session.rewardCollectibles().len));

    current_session.setHeroWorldPosition(try jsonPoint(door_key_consumed_hero));
    const unlock_effect = try zone_effects.applyContainingZoneEffects(&room, &current_session, &.{});
    try std.testing.expect(!unlock_effect.triggered_room_transition);
    try std.testing.expectEqual(@as(?zone_effects.SecretRoomDoorEvent, .house_consumed_key), unlock_effect.secret_room_door_event);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    try expectJsonInteger(try requireJsonField(door_key_consumed, "nb_little_keys_after"), current_session.littleKeyCount());
    try std.testing.expect(current_session.secretRoomHouseDoorUnlocked());

    current_session.setHeroWorldPosition(.{ .x = 9730, .y = 1025, .z = 762 });
    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    var door_zone_membership: runtime_query.ContainingZoneSet = .{};
    try door_zone_membership.append(room.scene.zones[0]);
    const forward_effect = try zone_effects.applyContainingZoneEffects(&room, &current_session, door_zone_membership.slice());
    try std.testing.expect(forward_effect.triggered_room_transition);
    try std.testing.expectEqual(@as(?zone_effects.SecretRoomDoorEvent, null), forward_effect.secret_room_door_event);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    const pending_forward = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;
    try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 9724, .y = 1024, .z = 782 }, pending_forward.destination_world_position);
    try std.testing.expectEqual(@as(?locomotion.WorldPointSnapshot, cellar_transition_new_pos), pending_forward.runtime_new_position);

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
            try expectJsonInteger(try requireJsonField(door_target, "scene"), @intCast(value.destination_scene_entry_index));
            try expectJsonInteger(try requireJsonField(door_target, "background"), @intCast(value.destination_background_entry_index));
            try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 9724, .y = 1024, .z = 782 }, value.provisional_world_position);
            try std.testing.expectEqual(@as(?locomotion.WorldPointSnapshot, cellar_transition_new_pos), value.runtime_new_position);
            try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = 9724, .y = 1024, .z = 782 }, value.hero_position);
        },
        .rejected => return error.UnexpectedRejectedRoomTransition,
    }
    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(usize, 0), room.background.entry_index);

    locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    current_session.setHeroWorldPosition(return_probe_position);
    const reverse_effect = try zone_effects.applyContainingZoneEffects(&room, &current_session, &.{});
    try std.testing.expect(reverse_effect.triggered_room_transition);
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    const pending_reverse = current_session.pendingRoomTransition() orelse return error.MissingPendingRoomTransition;
    try std.testing.expectEqual(return_new_pos, pending_reverse.destination_world_position);
    try std.testing.expectEqual(@as(?locomotion.WorldPointSnapshot, null), pending_reverse.runtime_new_position);

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
            try std.testing.expectEqual(locomotion.WorldPointSnapshot{ .x = return_final_house_hero.x, .y = 1024, .z = return_final_house_hero.z }, value.hero_position);
            try std.testing.expectEqual(@as(?locomotion.WorldPointSnapshot, null), value.runtime_new_position);
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

test "runtime update tick consumes a scene-2 cellar magic-ball throw intent" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{ .x = 5071, .y = 1024, .z = 1820 });
    current_session.setGameVar(1, 1);

    try current_session.submitHeroIntent(.select_magic_ball);
    const select_tick = try runtime_update.tick(&room, &current_session);
    try std.testing.expect(select_tick.consumed_hero_intent);
    try std.testing.expectEqual(runtime_session.SelectedWeapon.magic_ball, current_session.selectedWeapon());

    try current_session.submitHeroIntent(.{ .throw_magic_ball = .normal });
    const throw_tick = try runtime_update.tick(&room, &current_session);

    try std.testing.expect(throw_tick.consumed_hero_intent);
    try std.testing.expect(!throw_tick.triggered_room_transition);
    try std.testing.expectEqual(@as(usize, 2), current_session.frame_index);
    try std.testing.expectEqual(@as(?runtime_session.HeroIntent, null), current_session.pendingHeroIntent());
    try std.testing.expectEqual(@as(usize, 1), current_session.magicBallProjectiles().len);
    const projectile = current_session.magicBallProjectiles()[0];
    try std.testing.expectEqual(runtime_session.MagicBallThrowMode.normal, projectile.mode);
    try std.testing.expectEqual(@as(i16, -55), projectile.vx);
    try std.testing.expectEqual(@as(i16, 18), projectile.vy);
    try std.testing.expectEqual(@as(i16, 81), projectile.vz);
}

test "runtime update tick advances the live-backed level-1 wall Magic Ball bounce and return sequence" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    try current_session.appendMagicBallProjectile(.{
        .launch_frame_index = 0,
        .mode = .normal,
        .script = .level1_wall_normal,
        .world_position = .{ .x = 2831, .y = 2301, .z = 6912 },
        .origin_world_position = .{ .x = 3510, .y = 2224, .z = 7003 },
        .sprite_index = 8,
        .vx = -97,
        .vy = 18,
        .vz = -13,
        .flags = 33038,
        .timeout = 0,
        .divers = 0,
    });

    const expected_axes = [_]runtime_session.MagicBallAxis{ .x, .y, .y, .x };
    for (expected_axes, 0..) |axis, event_index| {
        _ = try runtime_update.tick(room, &current_session);
        const event = current_session.magicBallProjectileEvents()[event_index];
        try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.bounce, event.kind);
        try std.testing.expectEqual(runtime_session.MagicBallProjectileScript.level1_wall_normal, event.script);
        try std.testing.expectEqual(@as(?runtime_session.MagicBallAxis, axis), event.sign_flip_axis);
        try std.testing.expectEqual(@as(i16, 8), event.sprite_index);
        try std.testing.expectEqual(@as(usize, 1), current_session.magicBallProjectiles().len);
    }

    _ = try runtime_update.tick(room, &current_session);
    const return_event = current_session.magicBallProjectileEvents()[4];
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.return_started, return_event.kind);
    try std.testing.expectEqual(@as(i16, 12), return_event.sprite_index);
    try std.testing.expectEqual(runtime_session.MagicBallProjectilePhase.returning, current_session.magicBallProjectiles()[0].phase);

    _ = try runtime_update.tick(room, &current_session);
    const clear_event = current_session.magicBallProjectileEvents()[5];
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.cleared, clear_event.kind);
    try std.testing.expectEqual(@as(usize, 0), current_session.magicBallProjectiles().len);
}

test "runtime update tick advances the live-backed fire wall Magic Ball bounce sequence" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    try current_session.appendMagicBallProjectile(.{
        .launch_frame_index = 0,
        .mode = .normal,
        .script = .fire_wall_normal,
        .world_position = .{ .x = 4001, .y = 1533, .z = 4575 },
        .origin_world_position = .{ .x = 4393, .y = 1456, .z = 5135 },
        .sprite_index = 11,
        .vx = -56,
        .vy = 18,
        .vz = -80,
        .flags = 8421646,
        .timeout = 100,
        .divers = 0,
    });

    const expected_axes = [_]runtime_session.MagicBallAxis{ .y, .y, .z, .x };
    for (expected_axes, 0..) |axis, event_index| {
        _ = try runtime_update.tick(room, &current_session);
        const event = current_session.magicBallProjectileEvents()[event_index];
        try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.bounce, event.kind);
        try std.testing.expectEqual(runtime_session.MagicBallProjectileScript.fire_wall_normal, event.script);
        try std.testing.expectEqual(@as(?runtime_session.MagicBallAxis, axis), event.sign_flip_axis);
        try std.testing.expectEqual(@as(i16, 11), event.sprite_index);
    }

    _ = try runtime_update.tick(room, &current_session);
    const clear_event = current_session.magicBallProjectileEvents()[4];
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.cleared, clear_event.kind);
    try std.testing.expectEqual(@as(usize, 0), current_session.magicBallProjectiles().len);
}

test "runtime update tick applies the promoted Tralu level-1 Magic Ball damage script" {
    const room = try room_fixtures.guarded22();
    var objects = [_]runtime_session.ObjectState{
        .{ .index = 3, .x = 0, .y = 0, .z = 0, .life_points = 72 },
    };
    var current_session = try runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(room),
        objects[0..],
        &.{},
    );
    defer current_session.deinit(std.testing.allocator);

    try current_session.appendMagicBallProjectile(magicBallProjectileWithScript(.tralu_level1_damage));
    _ = try runtime_update.tick(room, &current_session);

    try std.testing.expectEqual(@as(u8, 63), current_session.objectSnapshotByIndex(3).?.life_points);
    try std.testing.expectEqual(@as(usize, 0), current_session.magicBallProjectiles().len);
    const damage_event = current_session.magicBallProjectileEvents()[0];
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.damage_applied, damage_event.kind);
    try std.testing.expectEqual(runtime_session.MagicBallProjectileScript.tralu_level1_damage, damage_event.script);
    try std.testing.expectEqual(@as(?usize, 3), damage_event.target_object_index);
    try std.testing.expectEqual(@as(?i16, 72), damage_event.value_before);
    try std.testing.expectEqual(@as(?i16, 63), damage_event.value_after);
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.cleared, current_session.magicBallProjectileEvents()[1].kind);
}

test "runtime update tick applies promoted Emerald Moon Magic Ball switch scripts only for objects 3 and 4" {
    const room = try room_fixtures.guarded22();
    const switch3_seed = emptyBehaviorSeed(3, 0, 0);
    const switch4_seed = emptyBehaviorSeed(4, 0, 0);
    var seeds = [_]runtime_session.ObjectBehaviorSeedState{ switch3_seed, switch4_seed };
    var current_session = try runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(room),
        &.{},
        seeds[0..],
    );
    defer current_session.deinit(std.testing.allocator);
    current_session.objectBehaviorStateByIndexPtr(3).?.current_track_label = 4;
    current_session.objectBehaviorStateByIndexPtr(4).?.current_track_label = 2;

    try current_session.appendMagicBallProjectile(magicBallProjectileWithScript(.emerald_moon_switch_object3));
    _ = try runtime_update.tick(room, &current_session);
    try std.testing.expectEqual(@as(?u8, 2), current_session.objectBehaviorStateByIndex(3).?.current_track_label);
    const switch3_event = current_session.magicBallProjectileEvents()[0];
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.switch_activated, switch3_event.kind);
    try std.testing.expectEqual(@as(?usize, 3), switch3_event.target_object_index);
    try std.testing.expectEqual(@as(?i16, 4), switch3_event.value_before);
    try std.testing.expectEqual(@as(?i16, 2), switch3_event.value_after);

    try current_session.appendMagicBallProjectile(magicBallProjectileWithScript(.emerald_moon_switch_object4));
    _ = try runtime_update.tick(room, &current_session);
    try std.testing.expectEqual(@as(?u8, 4), current_session.objectBehaviorStateByIndex(4).?.current_track_label);
    const switch4_event = current_session.magicBallProjectileEvents()[2];
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.switch_activated, switch4_event.kind);
    try std.testing.expectEqual(@as(?usize, 4), switch4_event.target_object_index);
    try std.testing.expectEqual(@as(?i16, 2), switch4_event.value_before);
    try std.testing.expectEqual(@as(?i16, 4), switch4_event.value_after);
}

test "runtime update tick applies promoted Emerald Moon switch impacts using real room 31 behavior seeds" {
    const room = try room_fixtures.guarded3131();
    try std.testing.expectEqual(@as(usize, 2), room.scene.object_behavior_seeds.len);
    try std.testing.expect(room.scene.object_behavior_seeds[0].index == 3 or room.scene.object_behavior_seeds[1].index == 3);
    try std.testing.expect(room.scene.object_behavior_seeds[0].index == 4 or room.scene.object_behavior_seeds[1].index == 4);

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?runtime_session.ObjectBehaviorState, null), current_session.objectBehaviorStateByIndex(2));
    try std.testing.expect(current_session.objectBehaviorStateByIndex(3) != null);
    try std.testing.expect(current_session.objectBehaviorStateByIndex(4) != null);

    try current_session.appendMagicBallProjectile(magicBallProjectileWithScript(.emerald_moon_switch_object3));
    const switch3_tick = try runtime_update.tick(room, &current_session);
    try std.testing.expectEqual(@as(usize, 2), switch3_tick.updated_object_count);
    try std.testing.expectEqual(@as(?u8, 2), current_session.objectBehaviorStateByIndex(3).?.current_track_label);
    const switch3_event = current_session.magicBallProjectileEvents()[0];
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.switch_activated, switch3_event.kind);
    try std.testing.expectEqual(@as(?usize, 3), switch3_event.target_object_index);
    try std.testing.expectEqual(@as(?i16, 2), switch3_event.value_after);

    try current_session.appendMagicBallProjectile(magicBallProjectileWithScript(.emerald_moon_switch_object4));
    const switch4_tick = try runtime_update.tick(room, &current_session);
    try std.testing.expectEqual(@as(usize, 2), switch4_tick.updated_object_count);
    try std.testing.expectEqual(@as(?u8, 4), current_session.objectBehaviorStateByIndex(4).?.current_track_label);
    const switch4_event = current_session.magicBallProjectileEvents()[2];
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.switch_activated, switch4_event.kind);
    try std.testing.expectEqual(@as(?usize, 4), switch4_event.target_object_index);
    try std.testing.expectEqual(@as(?i16, 4), switch4_event.value_after);
}

test "runtime update tick applies promoted Magic Ball lever activation scripts through object behavior state" {
    const room = try room_fixtures.guarded22();
    var objects = [_]runtime_session.ObjectState{
        .{ .index = 3, .x = 10, .y = 20, .z = 30, .life_points = 0 },
    };
    const radar_target = emptyBehaviorSeed(19, 0, 242);
    const radar_linked = emptyBehaviorSeed(21, 0, 0);
    const wizard_target = emptyBehaviorSeed(2, 0, 155);
    var seeds = [_]runtime_session.ObjectBehaviorSeedState{ radar_target, radar_linked, wizard_target };
    var current_session = try runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(room),
        objects[0..],
        seeds[0..],
    );
    defer current_session.deinit(std.testing.allocator);
    current_session.objectBehaviorStateByIndexPtr(21).?.current_track_label = 3;
    current_session.objectBehaviorStateByIndexPtr(2).?.current_track_label = 6;

    try current_session.appendMagicBallProjectile(magicBallProjectileWithScript(.radar_room_lever_primary));
    _ = try runtime_update.tick(room, &current_session);
    const radar_state = current_session.objectBehaviorStateByIndex(19).?;
    try std.testing.expectEqual(@as(i16, 244), radar_state.current_gen_anim);
    try std.testing.expectEqual(@as(i16, 244), radar_state.next_gen_anim);
    try std.testing.expectEqual(@as(?u8, 0), current_session.objectBehaviorStateByIndex(21).?.current_track_label);
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.lever_activated, current_session.magicBallProjectileEvents()[0].kind);

    try current_session.appendMagicBallProjectile(magicBallProjectileWithScript(.wizard_tent_lever_primary));
    _ = try runtime_update.tick(room, &current_session);
    const wizard_state = current_session.objectBehaviorStateByIndex(2).?;
    try std.testing.expectEqual(@as(?u8, 9), wizard_state.current_track_label);
    try std.testing.expectEqual(@as(i16, 0), wizard_state.current_gen_anim);
    try std.testing.expectEqual(@as(i32, 10), current_session.objectSnapshotByIndex(3).?.x);
    try std.testing.expectEqual(@as(i32, 20), current_session.objectSnapshotByIndex(3).?.y);
    try std.testing.expectEqual(@as(i32, 5632), current_session.objectSnapshotByIndex(3).?.z);
    const wizard_event = current_session.magicBallProjectileEvents()[2];
    try std.testing.expectEqual(runtime_session.MagicBallProjectileEventKind.lever_activated, wizard_event.kind);
    try std.testing.expectEqual(@as(?usize, 2), wizard_event.target_object_index);
    try std.testing.expectEqual(@as(?i16, 6), wizard_event.value_before);
    try std.testing.expectEqual(@as(?i16, 9), wizard_event.value_after);
}

const locomotion = @import("locomotion.zig");
const room_state = @import("room_state.zig");
const runtime_session = @import("session.zig");
const world_geometry = @import("world_geometry.zig");

pub const EffectSummary = struct {
    triggered_room_transition: bool = false,
    secret_room_door_event: ?SecretRoomDoorEvent = null,
};

pub const SecretRoomDoorEvent = enum {
    house_locked_no_key,
    house_consumed_key,
    cellar_return_free,
};

const secret_room_scene_entry_index: usize = 2;
const secret_room_house_background_entry_index: usize = 1;
const secret_room_cellar_background_entry_index: usize = 0;
const secret_room_house_to_cellar_zone_index: usize = 0;
const secret_room_cellar_to_house_destination_cube: i16 = 1;
const secret_room_cellar_to_house_source_zone_index: usize = 0;
const secret_room_cellar_to_house_trigger_min_x: i32 = 3000;
const secret_room_cellar_to_house_trigger_max_x: i32 = 3128;
const secret_room_cellar_to_house_trigger_min_y: i32 = 2048;
const secret_room_cellar_to_house_trigger_max_y: i32 = 2048;
const secret_room_cellar_to_house_trigger_min_z: i32 = 3600;
const secret_room_cellar_to_house_trigger_max_z: i32 = 3712;
const secret_room_cellar_to_house_provisional_destination = world_geometry.WorldPointSnapshot{
    .x = 9725,
    .y = 1278,
    .z = 1098,
};
const secret_room_cellar_to_house_probe_position = world_geometry.WorldPointSnapshot{
    .x = 3056,
    .y = 2048,
    .z = 3659,
};

pub fn applyPostLocomotionEffects(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
    locomotion_status: locomotion.LocomotionStatus,
) !EffectSummary {
    return switch (locomotion_status) {
        .last_move_accepted => |value| applyContainingZoneEffects(room, current_session, value.zone_membership.slice()),
        .last_zone_recovery_accepted => |value| applyContainingZoneEffects(room, current_session, value.zone_membership.slice()),
        else => applyContainingZoneEffects(room, current_session, &.{}),
    };
}

pub fn applyContainingZoneEffects(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
    zones: []const room_state.ZoneBoundsSnapshot,
) !EffectSummary {
    var pending_transition: ?runtime_session.PendingRoomTransition = null;
    var consumes_little_key = false;
    var secret_room_door_event: ?SecretRoomDoorEvent = null;
    const hero_world_position = current_session.heroWorldPosition();

    if (secretRoomCellarToHouseDoorTransition(room, current_session.*)) |transition| {
        pending_transition = transition;
        secret_room_door_event = .cellar_return_free;
    }

    for (zones) |zone| {
        switch (zone.semantics) {
            .change_cube => |semantics| {
                if (!semantics.initially_on) continue;
                if (pending_transition != null) return error.MultipleRoomTransitionsTriggered;
                if (secretRoomHouseToCellarDoorConsumesKey(room, current_session.*, zone)) |has_key| {
                    if (!has_key) {
                        secret_room_door_event = .house_locked_no_key;
                        continue;
                    }
                    consumes_little_key = true;
                    secret_room_door_event = .house_consumed_key;
                }

                pending_transition = .{
                    .source_zone_index = zone.index,
                    .destination_cube = semantics.destination_cube,
                    .destination_world_position_kind = .provisional_zone_relative,
                    .destination_world_position = classicZoneChangeCubeDestinationWorldPosition(
                        zone,
                        hero_world_position,
                    ),
                    .yaw = semantics.yaw,
                    .test_brick = semantics.test_brick,
                    .dont_readjust_twinsen = semantics.dont_readjust_twinsen,
                };
            },
            else => {},
        }
    }

    if (pending_transition) |transition| {
        try current_session.setPendingRoomTransition(transition);
        if (consumes_little_key and !current_session.consumeLittleKey()) return error.MissingLittleKeyForSecretRoomDoor;
        return .{
            .triggered_room_transition = true,
            .secret_room_door_event = secret_room_door_event,
        };
    }

    return .{ .secret_room_door_event = secret_room_door_event };
}

fn secretRoomHouseToCellarDoorConsumesKey(
    room: *const room_state.RoomSnapshot,
    current_session: runtime_session.Session,
    zone: room_state.ZoneBoundsSnapshot,
) ?bool {
    if (room.scene.entry_index != secret_room_scene_entry_index or
        room.background.entry_index != secret_room_house_background_entry_index or
        zone.index != secret_room_house_to_cellar_zone_index)
    {
        return null;
    }

    return current_session.littleKeyCount() != 0;
}

fn secretRoomCellarToHouseDoorTransition(
    room: *const room_state.RoomSnapshot,
    current_session: runtime_session.Session,
) ?runtime_session.PendingRoomTransition {
    if (room.scene.entry_index != secret_room_scene_entry_index or
        room.background.entry_index != secret_room_cellar_background_entry_index)
    {
        return null;
    }

    const hero_world_position = current_session.heroWorldPosition();
    if (hero_world_position.x < secret_room_cellar_to_house_trigger_min_x or
        hero_world_position.x > secret_room_cellar_to_house_trigger_max_x or
        hero_world_position.y < secret_room_cellar_to_house_trigger_min_y or
        hero_world_position.y > secret_room_cellar_to_house_trigger_max_y or
        hero_world_position.z < secret_room_cellar_to_house_trigger_min_z or
        hero_world_position.z > secret_room_cellar_to_house_trigger_max_z)
    {
        return null;
    }

    return .{
        .source_zone_index = secret_room_cellar_to_house_source_zone_index,
        .destination_cube = secret_room_cellar_to_house_destination_cube,
        .destination_world_position_kind = .provisional_zone_relative,
        .destination_world_position = secret_room_cellar_to_house_provisional_destination,
        .yaw = 0,
        .test_brick = false,
        .dont_readjust_twinsen = false,
    };
}

pub fn secretRoomCellarReturnProbePosition(
    scene_entry_index: usize,
    background_entry_index: usize,
) ?world_geometry.WorldPointSnapshot {
    if (scene_entry_index != secret_room_scene_entry_index or
        background_entry_index != secret_room_cellar_background_entry_index)
    {
        return null;
    }

    return secret_room_cellar_to_house_probe_position;
}

pub fn secretRoomHouseDoorProbePosition(
    scene_entry_index: usize,
    background_entry_index: usize,
    zone: room_state.ZoneBoundsSnapshot,
) ?world_geometry.WorldPointSnapshot {
    if (scene_entry_index != secret_room_scene_entry_index or
        background_entry_index != secret_room_house_background_entry_index or
        zone.index != secret_room_house_to_cellar_zone_index)
    {
        return null;
    }

    return .{
        .x = zone.x0,
        .y = zone.y0,
        .z = zone.z0,
    };
}

fn classicZoneChangeCubeDestinationWorldPosition(
    zone: room_state.ZoneBoundsSnapshot,
    hero_world_position: world_geometry.WorldPointSnapshot,
) world_geometry.WorldPointSnapshot {
    const semantics = switch (zone.semantics) {
        .change_cube => |value| value,
        else => unreachable,
    };
    const local_x = hero_world_position.x - zone.x0;
    const local_z = hero_world_position.z - zone.z0;
    const rotated = rotateQuarterTurns(local_x, local_z, semantics.yaw);
    return .{
        .x = semantics.destination_x + rotated.x,
        .y = hero_world_position.y - zone.y0 + semantics.destination_y,
        .z = semantics.destination_z + rotated.z,
    };
}

fn rotateQuarterTurns(local_x: i32, local_z: i32, yaw: i32) struct { x: i32, z: i32 } {
    const normalized_turns = @mod(-yaw, 4);
    return switch (normalized_turns) {
        0 => .{ .x = local_x, .z = local_z },
        1 => .{ .x = -local_z, .z = local_x },
        2 => .{ .x = -local_x, .z = -local_z },
        3 => .{ .x = local_z, .z = -local_x },
        else => unreachable,
    };
}

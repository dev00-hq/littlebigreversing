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
const secret_room_house_unlock_trigger_min_x: i32 = 3000;
const secret_room_house_unlock_trigger_max_x: i32 = 3128;
const secret_room_house_unlock_trigger_min_y: i32 = 2048;
const secret_room_house_unlock_trigger_max_y: i32 = 2048;
const secret_room_house_unlock_trigger_min_z: i32 = 3984;
const secret_room_house_unlock_trigger_max_z: i32 = 4096;
const secret_room_house_to_cellar_trigger_min_x: i32 = 9600;
const secret_room_house_to_cellar_trigger_max_x: i32 = 9820;
const secret_room_house_to_cellar_trigger_min_y: i32 = 1024;
const secret_room_house_to_cellar_trigger_max_y: i32 = 1025;
const secret_room_house_to_cellar_trigger_min_z: i32 = 700;
const secret_room_house_to_cellar_trigger_max_z: i32 = 1200;
const secret_room_house_to_cellar_provisional_destination = world_geometry.WorldPointSnapshot{
    .x = 9723,
    .y = 1277,
    .z = 762,
};
// Runtime NewPos is retained as proof data, but it is not a decoded footing
// coordinate in cube 0. Gameplay commits through this validated landing.
const secret_room_house_to_cellar_port_landing = world_geometry.WorldPointSnapshot{
    .x = 9724,
    .y = 1024,
    .z = 782,
};
const secret_room_house_to_cellar_probe_position = world_geometry.WorldPointSnapshot{
    .x = 9730,
    .y = 1025,
    .z = 762,
};
const secret_room_cellar_to_house_trigger_min_x: i32 = 9680;
const secret_room_cellar_to_house_trigger_max_x: i32 = 9780;
const secret_room_cellar_to_house_trigger_min_y: i32 = 1024;
const secret_room_cellar_to_house_trigger_max_y: i32 = 1025;
const secret_room_cellar_to_house_trigger_min_z: i32 = 1040;
const secret_room_cellar_to_house_trigger_max_z: i32 = 1180;
const secret_room_cellar_to_house_provisional_destination = world_geometry.WorldPointSnapshot{
    .x = 2562,
    .y = 2049,
    .z = 3686,
};
const secret_room_cellar_to_house_probe_position = world_geometry.WorldPointSnapshot{
    .x = 9730,
    .y = 1025,
    .z = 1126,
};
const secret_room_house_unlock_probe_position = world_geometry.WorldPointSnapshot{
    .x = 3050,
    .y = 2048,
    .z = 4034,
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
    var secret_room_door_event: ?SecretRoomDoorEvent = null;
    const hero_world_position = current_session.heroWorldPosition();

    if (secretRoomHouseDoorUnlockEvent(room, current_session, hero_world_position)) |event| {
        secret_room_door_event = event;
    }

    if (secretRoomCellarToHouseDoorTransition(room, current_session.*)) |transition| {
        pending_transition = transition;
        secret_room_door_event = .cellar_return_free;
    }

    for (zones) |zone| {
        switch (zone.semantics) {
            .change_cube => |semantics| {
                if (!semantics.initially_on) continue;
                if (pending_transition != null) {
                    if (secretRoomCellarToHouseZone(room, zone)) continue;
                    return error.MultipleRoomTransitionsTriggered;
                }

                if (secretRoomHouseToCellarZone(room, zone)) {
                    if (!current_session.secretRoomHouseDoorUnlocked()) {
                        secret_room_door_event = .house_locked_no_key;
                        continue;
                    }
                    if (!worldPointInBounds(
                        hero_world_position,
                        secret_room_house_to_cellar_trigger_min_x,
                        secret_room_house_to_cellar_trigger_max_x,
                        secret_room_house_to_cellar_trigger_min_y,
                        secret_room_house_to_cellar_trigger_max_y,
                        secret_room_house_to_cellar_trigger_min_z,
                        secret_room_house_to_cellar_trigger_max_z,
                    )) continue;

                    pending_transition = .{
                        .source_zone_index = zone.index,
                        .destination_cube = semantics.destination_cube,
                        .destination_world_position_kind = .final_landing,
                        .destination_world_position = secret_room_house_to_cellar_port_landing,
                        .runtime_new_position = secret_room_house_to_cellar_provisional_destination,
                        .yaw = semantics.yaw,
                        .test_brick = semantics.test_brick,
                        .dont_readjust_twinsen = semantics.dont_readjust_twinsen,
                    };
                    continue;
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
        return .{
            .triggered_room_transition = true,
            .secret_room_door_event = secret_room_door_event,
        };
    }

    return .{ .secret_room_door_event = secret_room_door_event };
}

fn secretRoomHouseDoorUnlockEvent(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
    hero_world_position: world_geometry.WorldPointSnapshot,
) ?SecretRoomDoorEvent {
    if (room.scene.entry_index != secret_room_scene_entry_index or
        room.background.entry_index != secret_room_house_background_entry_index)
    {
        return null;
    }
    if (!worldPointInBounds(
        hero_world_position,
        secret_room_house_unlock_trigger_min_x,
        secret_room_house_unlock_trigger_max_x,
        secret_room_house_unlock_trigger_min_y,
        secret_room_house_unlock_trigger_max_y,
        secret_room_house_unlock_trigger_min_z,
        secret_room_house_unlock_trigger_max_z,
    )) {
        return null;
    }
    if (current_session.secretRoomHouseDoorUnlocked()) return null;

    if (!current_session.consumeLittleKey()) return .house_locked_no_key;
    current_session.setSecretRoomHouseDoorUnlocked(true);
    return .house_consumed_key;
}

fn secretRoomHouseToCellarZone(
    room: *const room_state.RoomSnapshot,
    zone: room_state.ZoneBoundsSnapshot,
) bool {
    if (room.scene.entry_index != secret_room_scene_entry_index or
        room.background.entry_index != secret_room_house_background_entry_index or
        zone.index != secret_room_house_to_cellar_zone_index)
    {
        return false;
    }

    return true;
}

fn secretRoomCellarToHouseZone(
    room: *const room_state.RoomSnapshot,
    zone: room_state.ZoneBoundsSnapshot,
) bool {
    if (room.scene.entry_index != secret_room_scene_entry_index or
        room.background.entry_index != secret_room_cellar_background_entry_index or
        zone.index != secret_room_cellar_to_house_source_zone_index)
    {
        return false;
    }

    return true;
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
    if (!worldPointInBounds(
        hero_world_position,
        secret_room_cellar_to_house_trigger_min_x,
        secret_room_cellar_to_house_trigger_max_x,
        secret_room_cellar_to_house_trigger_min_y,
        secret_room_cellar_to_house_trigger_max_y,
        secret_room_cellar_to_house_trigger_min_z,
        secret_room_cellar_to_house_trigger_max_z,
    )) {
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

pub fn secretRoomHouseUnlockProbePosition(
    scene_entry_index: usize,
    background_entry_index: usize,
) ?world_geometry.WorldPointSnapshot {
    if (scene_entry_index != secret_room_scene_entry_index or
        background_entry_index != secret_room_house_background_entry_index)
    {
        return null;
    }

    return secret_room_house_unlock_probe_position;
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

    return secret_room_house_unlock_probe_position;
}

pub fn secretRoomHouseToCellarProbePosition(
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

    return secret_room_house_to_cellar_probe_position;
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

fn worldPointInBounds(
    position: world_geometry.WorldPointSnapshot,
    min_x: i32,
    max_x: i32,
    min_y: i32,
    max_y: i32,
    min_z: i32,
    max_z: i32,
) bool {
    return position.x >= min_x and
        position.x <= max_x and
        position.y >= min_y and
        position.y <= max_y and
        position.z >= min_z and
        position.z <= max_z;
}

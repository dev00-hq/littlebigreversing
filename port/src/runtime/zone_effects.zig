const locomotion = @import("locomotion.zig");
const room_state = @import("room_state.zig");
const runtime_session = @import("session.zig");
const world_geometry = @import("world_geometry.zig");

pub const EffectSummary = struct {
    triggered_room_transition: bool = false,
};

pub fn applyPostLocomotionEffects(
    current_session: *runtime_session.Session,
    locomotion_status: locomotion.LocomotionStatus,
) !EffectSummary {
    return switch (locomotion_status) {
        .last_move_accepted => |value| applyContainingZoneEffects(current_session, value.zone_membership.slice()),
        .last_zone_recovery_accepted => |value| applyContainingZoneEffects(current_session, value.zone_membership.slice()),
        else => .{},
    };
}

pub fn applyContainingZoneEffects(
    current_session: *runtime_session.Session,
    zones: []const room_state.ZoneBoundsSnapshot,
) !EffectSummary {
    var pending_transition: ?runtime_session.PendingRoomTransition = null;
    const hero_world_position = current_session.heroWorldPosition();

    for (zones) |zone| {
        switch (zone.semantics) {
            .change_cube => |semantics| {
                if (!semantics.initially_on) continue;
                if (pending_transition != null) return error.MultipleRoomTransitionsTriggered;

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
        return .{ .triggered_room_transition = true };
    }

    return .{};
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

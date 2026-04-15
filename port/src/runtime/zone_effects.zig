const locomotion = @import("locomotion.zig");
const room_state = @import("room_state.zig");
const runtime_session = @import("session.zig");

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

    for (zones) |zone| {
        switch (zone.semantics) {
            .change_cube => |semantics| {
                if (!semantics.initially_on) continue;
                if (pending_transition != null) return error.MultipleRoomTransitionsTriggered;

                pending_transition = .{
                    .source_zone_index = zone.index,
                    .destination_cube = semantics.destination_cube,
                    .destination_world_position = .{
                        .x = semantics.destination_x,
                        .y = semantics.destination_y,
                        .z = semantics.destination_z,
                    },
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

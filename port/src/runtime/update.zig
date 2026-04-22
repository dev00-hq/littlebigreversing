const locomotion = @import("locomotion.zig");
const object_behavior = @import("object_behavior.zig");
const reward_collectibles = @import("reward_collectibles.zig");
const room_state = @import("room_state.zig");
const runtime_session = @import("session.zig");
const zone_effects = @import("zone_effects.zig");

pub const TickResult = struct {
    locomotion_status: locomotion.LocomotionStatus,
    consumed_hero_intent: bool,
    triggered_room_transition: bool,
    secret_room_door_event: ?zone_effects.SecretRoomDoorEvent = null,
    updated_object_count: usize,
};

pub fn tick(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !TickResult {
    if (current_session.pendingRoomTransition() != null) {
        return error.PendingRoomTransitionRequiresCommit;
    }

    const pending_hero_intent = current_session.pendingHeroIntent();
    const consumed_hero_intent = pending_hero_intent != null;
    const locomotion_status: locomotion.LocomotionStatus = if (pending_hero_intent) |intent| switch (intent) {
        .move_cardinal => try locomotion.applyPendingHeroIntent(room, current_session),
        .cast_lightning,
        .default_action,
        .advance_story,
        => blk: {
            _ = current_session.consumeHeroIntent() orelse return error.MissingPendingHeroIntent;
            try object_behavior.applyHeroIntent(room, current_session, intent);
            break :blk try locomotion.inspectCurrentStatus(room, current_session.*);
        },
    } else try locomotion.inspectCurrentStatus(room, current_session.*);
    const zone_effect_summary = try zone_effects.applyPostLocomotionEffects(room, current_session, locomotion_status);
    if (zone_effect_summary.triggered_room_transition) {
        return .{
            .locomotion_status = locomotion_status,
            .consumed_hero_intent = consumed_hero_intent,
            .triggered_room_transition = true,
            .secret_room_door_event = zone_effect_summary.secret_room_door_event,
            .updated_object_count = 0,
        };
    }

    try reward_collectibles.resolveHeroRewardPickups(room, current_session);
    const behavior_summary = try object_behavior.stepSupportedObjects(room, current_session);
    current_session.advanceFrameIndex();

    return .{
        .locomotion_status = locomotion_status,
        .consumed_hero_intent = consumed_hero_intent,
        .triggered_room_transition = false,
        .secret_room_door_event = zone_effect_summary.secret_room_door_event,
        .updated_object_count = behavior_summary.updated_object_count,
    };
}

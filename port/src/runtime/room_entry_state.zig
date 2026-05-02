const std = @import("std");
const reference_metadata = @import("../generated/reference_metadata.zig");
const room_state = @import("room_state.zig");
const runtime_session = @import("session.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");

const sendell_scene_entry: usize = 36;
const sendell_background_entry: usize = 36;
const sendell_ball_flag_index: u8 = reference_metadata.sendell_ball_flag.index;
const lightning_spell_flag_index: u8 = reference_metadata.lightning_spell_flag.index;
const sendell_seed_magic_level: u8 = 2;
const sendell_seed_magic_point: u8 = sendell_seed_magic_level * 20;
const sendell_red_ball_magic_level: u8 = 3;
const sendell_red_ball_magic_point: u8 = sendell_red_ball_magic_level * 20;
const sendell_object_index: usize = 2;
const sendell_dialog_id: i16 = 3;

pub fn applyRoomEntryState(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) void {
    if (room.scene.entry_index != sendell_scene_entry or room.background.entry_index != sendell_background_entry) {
        return;
    }

    const object_behavior = current_session.objectBehaviorStateByIndexPtr(sendell_object_index) orelse return;
    object_behavior.sendell_ball_phase = .idle;
    current_session.clearCurrentDialogId();
    current_session.setGameVar(lightning_spell_flag_index, 1);
    current_session.setGameVar(sendell_ball_flag_index, 0);
    current_session.setMagicLevelAndRefill(sendell_seed_magic_level);
}

pub fn reconstructLoadedRoomState(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) void {
    if (room.scene.entry_index != sendell_scene_entry or room.background.entry_index != sendell_background_entry) {
        return;
    }

    const object_behavior = current_session.objectBehaviorStateByIndexPtr(sendell_object_index) orelse return;
    current_session.clearCurrentDialogId();

    if (current_session.gameVar(sendell_ball_flag_index) > 0) {
        object_behavior.sendell_ball_phase = .completed;
        if (current_session.magicLevel() < sendell_red_ball_magic_level) {
            current_session.setMagicLevelAndRefill(sendell_red_ball_magic_level);
        }
        return;
    }

    if (current_session.magicLevel() == 0 and current_session.magicPoint() == 0) {
        current_session.setMagicLevelAndRefill(sendell_seed_magic_level);
        current_session.setGameVar(sendell_ball_flag_index, 0);
        object_behavior.sendell_ball_phase = .idle;
        return;
    }

    if (current_session.magicLevel() == sendell_seed_magic_level and current_session.magicPoint() == 0) {
        object_behavior.sendell_ball_phase = .awaiting_dialog_open;
        return;
    }

    if (current_session.magicLevel() >= sendell_red_ball_magic_level and current_session.magicPoint() == sendell_red_ball_magic_point) {
        current_session.openTextRecord(.scripted_event_text, sendell_dialog_id, null) catch unreachable;
        object_behavior.sendell_ball_phase = .awaiting_first_dialog_ack;
        return;
    }

    object_behavior.sendell_ball_phase = .idle;
}

test "room entry seeds fresh Sendell room state" {
    const room = try room_fixtures.guarded3636();
    var current_session = try runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
    defer current_session.deinit(std.testing.allocator);

    applyRoomEntryState(room, &current_session);

    try std.testing.expectEqual(@as(u8, sendell_seed_magic_level), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, sendell_seed_magic_point), current_session.magicPoint());
    try std.testing.expectEqual(@as(i16, 0), current_session.gameVar(sendell_ball_flag_index));
    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(lightning_spell_flag_index));
    try std.testing.expectEqual(@as(?i16, null), current_session.currentDialogId());
    try std.testing.expectEqual(runtime_session.SendellBallPhase.idle, current_session.objectBehaviorStateByIndex(sendell_object_index).?.sendell_ball_phase);
}

test "room entry reconstructs completed Sendell room state from durable vars" {
    const room = try room_fixtures.guarded3636();
    var current_session = try runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
    defer current_session.deinit(std.testing.allocator);
    current_session.setMagicLevelAndRefill(sendell_red_ball_magic_level);
    current_session.setGameVar(sendell_ball_flag_index, 1);

    reconstructLoadedRoomState(room, &current_session);

    try std.testing.expectEqual(@as(u8, sendell_red_ball_magic_level), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, sendell_red_ball_magic_point), current_session.magicPoint());
    try std.testing.expectEqual(@as(?i16, null), current_session.currentDialogId());
    try std.testing.expectEqual(runtime_session.SendellBallPhase.completed, current_session.objectBehaviorStateByIndex(sendell_object_index).?.sendell_ball_phase);
}

test "room entry reconstructs pending Sendell dialog state from durable magic state" {
    const room = try room_fixtures.guarded3636();
    var current_session = try runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
    defer current_session.deinit(std.testing.allocator);
    current_session.setMagicLevelAndRefill(sendell_red_ball_magic_level);

    reconstructLoadedRoomState(room, &current_session);

    try std.testing.expectEqual(@as(?i16, sendell_dialog_id), current_session.currentDialogId());
    try std.testing.expectEqual(runtime_session.text_interactions.TextInteractionOwner.scripted_event_text, current_session.textUiState().owner.?);
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_first_dialog_ack, current_session.objectBehaviorStateByIndex(sendell_object_index).?.sendell_ball_phase);
}

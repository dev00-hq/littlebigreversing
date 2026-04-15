const std = @import("std");
const life_program = @import("../game_data/scene/life_program.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");
const room_state = @import("room_state.zig");
const object_behavior = @import("object_behavior.zig");
const runtime_session = @import("session.zig");

const sendell_flag_index: u8 = 3;
const lightning_flag_index: u8 = 19;

fn initSession(room: *const room_state.RoomSnapshot) !runtime_session.Session {
    return runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
}

test "runtime object behavior executes the supported 19/19 object 2 life window and track slice" {
    const room = try room_fixtures.guarded1919();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);

    const first_summary = try object_behavior.stepSupportedObjects(room, &current_session);
    try std.testing.expectEqual(@as(usize, 1), first_summary.updated_object_count);
    try std.testing.expectEqual(@as(u8, 1), current_session.cubeVar(0));

    const first_state = current_session.objectBehaviorStateByIndex(2) orelse return error.MissingRuntimeObjectBehaviorState;
    try std.testing.expectEqual(@as(?i16, 1), first_state.current_track_offset);
    try std.testing.expectEqual(@as(?u8, 4), first_state.current_track_label);
    try std.testing.expectEqual(@as(i16, 138), first_state.current_sprite);
    try std.testing.expectEqual(@as(u8, 0), first_state.emitted_bonus_count);
    try std.testing.expectEqual(@as(u8, @intFromEnum(life_program.LifeOpcode.LM_SWIF)), first_state.life_bytes[28]);
    try std.testing.expectEqual(@as(usize, 0), current_session.bonusSpawnEvents().len);

    const second_summary = try object_behavior.stepSupportedObjects(room, &current_session);
    try std.testing.expectEqual(@as(usize, 1), second_summary.updated_object_count);
    try std.testing.expectEqual(@as(u8, 0), current_session.cubeVar(0));

    const second_state = current_session.objectBehaviorStateByIndex(2) orelse return error.MissingRuntimeObjectBehaviorState;
    try std.testing.expectEqual(@as(?i16, 23), second_state.current_track_offset);
    try std.testing.expectEqual(@as(?u8, 2), second_state.current_track_label);
    try std.testing.expectEqual(@as(i16, 138), second_state.current_sprite);
    try std.testing.expectEqual(@as(u8, 10), second_state.wait_ticks_remaining);
    try std.testing.expectEqual(@as(u8, @intFromEnum(life_program.LifeOpcode.LM_SNIF)), second_state.life_bytes[28]);
    try std.testing.expectEqual(@as(usize, 0), current_session.bonusSpawnEvents().len);
}

test "runtime object behavior applies the supported Sendell room-36 story sequence through lightning and dialog advances" {
    const room = try room_fixtures.guarded3636();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setMagicLevelAndRefill(2);
    current_session.setGameVar(sendell_flag_index, 0);
    current_session.setGameVar(lightning_flag_index, 1);

    const idle_summary = try object_behavior.stepSupportedObjects(room, &current_session);
    try std.testing.expectEqual(@as(usize, 1), idle_summary.updated_object_count);
    try std.testing.expectEqual(runtime_session.SendellBallPhase.idle, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try object_behavior.applyHeroIntent(room, &current_session, .cast_lightning);
    try std.testing.expectEqual(@as(u8, 2), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 0), current_session.magicPoint());
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_first_dialog_ack, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try object_behavior.applyHeroIntent(room, &current_session, .advance_story);
    try std.testing.expectEqual(@as(u8, 3), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 60), current_session.magicPoint());
    try std.testing.expectEqual(@as(i16, 0), current_session.gameVar(sendell_flag_index));
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_second_dialog_ack, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try object_behavior.applyHeroIntent(room, &current_session, .advance_story);
    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(sendell_flag_index));
    try std.testing.expectEqual(runtime_session.SendellBallPhase.completed, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);
}

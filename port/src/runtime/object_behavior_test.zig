const std = @import("std");
const reference_metadata = @import("../generated/reference_metadata.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const track_program = @import("../game_data/scene/track_program.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");
const room_state = @import("room_state.zig");
const object_behavior = @import("object_behavior.zig");
const dialog_pagination = @import("dialog_pagination.zig");
const runtime_session = @import("session.zig");

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
    var message_zone_count: usize = 0;
    for (room.scene.zones) |zone| switch (zone.semantics) {
        .message => message_zone_count += 1,
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 0), message_zone_count);

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setMagicLevelAndRefill(2);
    current_session.setGameVar(sendell_ball_flag_index, 0);
    current_session.setGameVar(lightning_spell_flag_index, 1);

    const idle_summary = try object_behavior.stepSupportedObjects(room, &current_session);
    try std.testing.expectEqual(@as(usize, 1), idle_summary.updated_object_count);
    try std.testing.expectEqual(runtime_session.SendellBallPhase.idle, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try object_behavior.applyHeroIntent(room, &current_session, .cast_lightning);
    try std.testing.expectEqual(@as(u8, 2), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 0), current_session.magicPoint());
    try std.testing.expectEqual(@as(?i16, null), current_session.currentDialogId());
    try std.testing.expectEqual(@as(?object_behavior.SendellDialogSlice, null), object_behavior.currentSendellDialogSlice(current_session));
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_dialog_open, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    _ = try object_behavior.stepSupportedObjects(room, &current_session);
    try std.testing.expectEqual(@as(u8, 3), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 60), current_session.magicPoint());
    try std.testing.expectEqual(@as(?i16, 3), current_session.currentDialogId());
    const first_slice = object_behavior.currentSendellDialogSlice(current_session).?;
    try std.testing.expectEqual(@as(u8, 1), first_slice.page_number);
    try std.testing.expectEqualStrings(
        "You just found Sendell's Ball. Now you have reached a new level of magic: Red Ball. It will also enable ",
        first_slice.visible_text,
    );
    try std.testing.expectEqualStrings("Sendell to contact you in case of danger.", first_slice.next_text);
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_first_dialog_ack, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try object_behavior.applyHeroIntent(room, &current_session, .advance_story);
    try std.testing.expectEqual(@as(u8, 3), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 60), current_session.magicPoint());
    try std.testing.expectEqual(@as(i16, 0), current_session.gameVar(sendell_ball_flag_index));
    try std.testing.expectEqual(@as(?i16, 3), current_session.currentDialogId());
    const second_slice = object_behavior.currentSendellDialogSlice(current_session).?;
    try std.testing.expectEqual(@as(u8, 2), second_slice.page_number);
    try std.testing.expectEqualStrings("Sendell to contact you in case of danger.", second_slice.visible_text);
    try std.testing.expectEqualStrings("", second_slice.next_text);
    try std.testing.expectEqual(runtime_session.SendellBallPhase.awaiting_second_dialog_ack, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);

    try object_behavior.applyHeroIntent(room, &current_session, .advance_story);
    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(sendell_ball_flag_index));
    try std.testing.expectEqual(@as(?i16, null), current_session.currentDialogId());
    try std.testing.expectEqual(@as(?object_behavior.SendellDialogSlice, null), object_behavior.currentSendellDialogSlice(current_session));
    try std.testing.expectEqual(runtime_session.SendellBallPhase.completed, current_session.objectBehaviorStateByIndex(2).?.sendell_ball_phase);
}

test "runtime dialog pagination derives the same boundary on the newgame pharmacy warning record" {
    const full_text =
        "Twinsen, rush to the downtown pharmacy and find a cure for the Dino-Fly ! " ++
        "He has just crashed in the garden and looks injured.";
    const split = dialog_pagination.splitTextAtCursor(
        full_text,
        ("Twinsen, rush to the downtown pharmacy and find a cure for the Dino-Fly ! " ++
            "He has just crashed in the ").len,
    );

    try std.testing.expectEqualStrings(
        "Twinsen, rush to the downtown pharmacy and find a cure for the Dino-Fly ! He has just crashed in the ",
        split.text_before_cursor,
    );
    try std.testing.expectEqualStrings("garden and looks injured.", split.text_from_cursor);
    try std.testing.expect(split.cursor_is_next_page_boundary);
}

test "runtime object behavior supports LM_OR_IF control flow on guarded 19/19 object 2" {
    const room = try room_fixtures.guarded1919();

    var life_bytes = [_]u8{
        @intFromEnum(life_program.LifeOpcode.LM_OR_IF),
        0,
        0,
        0,
        0,
        0,
        0,
        @intFromEnum(life_program.LifeOpcode.LM_SET_VAR_CUBE),
        0,
        0,
        @intFromEnum(life_program.LifeOpcode.LM_END),
        @intFromEnum(life_program.LifeOpcode.LM_SET_VAR_CUBE),
        0,
        0,
        @intFromEnum(life_program.LifeOpcode.LM_END),
    };
    var track_bytes = [_]u8{
        @intFromEnum(track_program.TrackOpcode.end),
    };
    var life_instructions = [_]life_program.LifeInstruction{
        .{
            .offset = 0,
            .opcode = .LM_OR_IF,
            .byte_length = 7,
            .operands = .{ .condition = .{
                .function = .{
                    .offset = 1,
                    .function = .LF_VAR_CUBE,
                    .byte_length = 2,
                    .return_type = .RET_U8,
                    .operands = .{ .u8_value = 0 },
                },
                .comparison = .{
                    .offset = 3,
                    .comparator = .LT_EQUAL,
                    .byte_length = 2,
                    .return_type = .RET_U8,
                    .literal = .{ .u8_value = 1 },
                },
                .jump_offset = 11,
            } },
        },
        .{
            .offset = 7,
            .opcode = .LM_SET_VAR_CUBE,
            .byte_length = 3,
            .operands = .{ .u8_pair = .{
                .first = 1,
                .second = 3,
            } },
        },
        .{
            .offset = 10,
            .opcode = .LM_END,
            .byte_length = 1,
            .operands = .{ .none = {} },
        },
        .{
            .offset = 11,
            .opcode = .LM_SET_VAR_CUBE,
            .byte_length = 3,
            .operands = .{ .u8_pair = .{
                .first = 1,
                .second = 9,
            } },
        },
        .{
            .offset = 14,
            .opcode = .LM_END,
            .byte_length = 1,
            .operands = .{ .none = {} },
        },
    };
    var track_instructions = [_]track_program.TrackInstruction{
        .{
            .offset = 0,
            .opcode = .end,
            .byte_length = 1,
            .operands = .{ .none = {} },
        },
    };
    var synthetic_seeds = [_]room_state.ObjectBehaviorSeedSnapshot{
        .{
            .index = 2,
            .sprite = room.scene.object_behavior_seeds[0].sprite,
            .track_bytes = track_bytes[0..],
            .track_instructions = track_instructions[0..],
            .life_bytes = life_bytes[0..],
            .life_instructions = life_instructions[0..],
        },
    };
    var synthetic_room = room.*;
    synthetic_room.scene.object_behavior_seeds = synthetic_seeds[0..];

    var false_session = try runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(&synthetic_room),
        synthetic_room.scene.objects,
        synthetic_room.scene.object_behavior_seeds,
    );
    defer false_session.deinit(std.testing.allocator);

    _ = try object_behavior.stepSupportedObjects(&synthetic_room, &false_session);
    try std.testing.expectEqual(@as(u8, 3), false_session.cubeVar(1));

    var true_session = try runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(&synthetic_room),
        synthetic_room.scene.objects,
        synthetic_room.scene.object_behavior_seeds,
    );
    defer true_session.deinit(std.testing.allocator);
    true_session.setCubeVar(0, 1);

    _ = try object_behavior.stepSupportedObjects(&synthetic_room, &true_session);
    try std.testing.expectEqual(@as(u8, 9), true_session.cubeVar(1));
}

test "runtime object behavior treats TM_SAMPLE_STOP as a non-blocking guarded 19/19 track opcode" {
    const room = try room_fixtures.guarded1919();

    var life_bytes = [_]u8{
        @intFromEnum(life_program.LifeOpcode.LM_SET_TRACK),
        0,
        0,
        @intFromEnum(life_program.LifeOpcode.LM_END),
    };
    var track_bytes = [_]u8{
        @intFromEnum(track_program.TrackOpcode.label),
        1,
        @intFromEnum(track_program.TrackOpcode.sample_stop),
        0,
        0,
        @intFromEnum(track_program.TrackOpcode.sprite),
        144,
        0,
        @intFromEnum(track_program.TrackOpcode.stop),
    };
    var life_instructions = [_]life_program.LifeInstruction{
        .{
            .offset = 0,
            .opcode = .LM_SET_TRACK,
            .byte_length = 3,
            .operands = .{ .i16_value = 0 },
        },
        .{
            .offset = 3,
            .opcode = .LM_END,
            .byte_length = 1,
            .operands = .{ .none = {} },
        },
    };
    var track_instructions = [_]track_program.TrackInstruction{
        .{
            .offset = 0,
            .opcode = .label,
            .byte_length = 2,
            .operands = .{ .label = .{ .label = 1 } },
        },
        .{
            .offset = 2,
            .opcode = .sample_stop,
            .byte_length = 3,
            .operands = .{ .i16_value = 0 },
        },
        .{
            .offset = 5,
            .opcode = .sprite,
            .byte_length = 3,
            .operands = .{ .i16_value = 144 },
        },
        .{
            .offset = 8,
            .opcode = .stop,
            .byte_length = 1,
            .operands = .{ .none = {} },
        },
    };
    var synthetic_seeds = [_]room_state.ObjectBehaviorSeedSnapshot{
        .{
            .index = 2,
            .sprite = room.scene.object_behavior_seeds[0].sprite,
            .track_bytes = track_bytes[0..],
            .track_instructions = track_instructions[0..],
            .life_bytes = life_bytes[0..],
            .life_instructions = life_instructions[0..],
        },
    };
    var synthetic_room = room.*;
    synthetic_room.scene.object_behavior_seeds = synthetic_seeds[0..];

    var current_session = try runtime_session.Session.initWithObjects(
        std.testing.allocator,
        room_state.heroStartWorldPoint(&synthetic_room),
        synthetic_room.scene.objects,
        synthetic_room.scene.object_behavior_seeds,
    );
    defer current_session.deinit(std.testing.allocator);

    _ = try object_behavior.stepSupportedObjects(&synthetic_room, &current_session);

    const state = current_session.objectBehaviorStateByIndex(2) orelse return error.MissingRuntimeObjectBehaviorState;
    try std.testing.expectEqual(@as(?i16, 0), state.current_track_offset);
    try std.testing.expectEqual(@as(?u8, 1), state.current_track_label);
    try std.testing.expectEqual(@as(i16, 144), state.current_sprite);
    try std.testing.expectEqual(@as(?i16, null), state.current_track_resume_offset);
}

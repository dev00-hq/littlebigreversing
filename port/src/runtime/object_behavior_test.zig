const std = @import("std");
const reference_metadata = @import("../generated/reference_metadata.zig");
const paths = @import("../foundation/paths.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const track_program = @import("../game_data/scene/track_program.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");
const room_state = @import("room_state.zig");
const object_behavior = @import("object_behavior.zig");
const dialog_pagination = @import("dialog_pagination.zig");
const runtime_query = @import("world_query.zig");
const runtime_session = @import("session.zig");

const sendell_ball_flag_index: u8 = reference_metadata.sendell_ball_flag.index;
const lightning_spell_flag_index: u8 = reference_metadata.lightning_spell_flag.index;
const magic_ball_flag_index: u8 = 1;

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
    try std.testing.expectEqual(runtime_session.text_interactions.TextInteractionOwner.scripted_event_text, current_session.textUiState().owner.?);
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

test "runtime object behavior applies guarded 2/1 default action to spawn the live-backed secret-room key" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 1);
    defer room.deinit(allocator);

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{ .x = 1280, .y = 2048, .z = 5376 });

    try object_behavior.applyHeroIntent(&room, &current_session, .default_action);

    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(0));
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    try std.testing.expectEqual(@as(usize, 1), current_session.bonusSpawnEvents().len);
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardCollectibles().len);

    const spawn_event = current_session.bonusSpawnEvents()[0];
    try std.testing.expectEqual(@as(usize, 7), spawn_event.source_object_index);
    try std.testing.expectEqual(runtime_session.RuntimeBonusKind.little_key, spawn_event.kind);
    try std.testing.expectEqual(@as(i16, 6), spawn_event.sprite_index);
    try std.testing.expectEqual(@as(u8, 1), spawn_event.quantity);

    const key = current_session.rewardCollectibles()[0];
    const key_landing_cell = try runtime_query.init(&room).gridCellAtWorldPoint(3768, 4366);
    const key_landing_surface = try runtime_query.init(&room).cellTopSurface(key_landing_cell.x, key_landing_cell.z);
    try std.testing.expectEqual(@as(usize, 7), key.source_object_index);
    try std.testing.expectEqual(runtime_session.RuntimeBonusKind.little_key, key.kind);
    try std.testing.expectEqual(@as(i16, 6), key.sprite_index);
    try std.testing.expectEqual(@as(u8, 1), key.quantity);
    try std.testing.expectEqual(key_landing_cell, key.admitted_surface_cell);
    try std.testing.expectEqual(key_landing_surface.top_y, key.admitted_surface_top_y);
    try std.testing.expectEqual(@as(i32, 3072), key.motion_start_world_position.x);
    try std.testing.expectEqual(@as(i32, 3072), key.motion_start_world_position.y);
    try std.testing.expectEqual(@as(i32, 5120), key.motion_start_world_position.z);
    try std.testing.expectEqual(@as(i32, 3768), key.motion_target_world_position.x);
    try std.testing.expectEqual(@as(i32, 2144), key.motion_target_world_position.y);
    try std.testing.expectEqual(@as(i32, 4366), key.motion_target_world_position.z);
    try std.testing.expect(!key.settled);

    try object_behavior.applyHeroIntent(&room, &current_session, .default_action);
    try std.testing.expectEqual(@as(usize, 1), current_session.rewardCollectibles().len);
    try std.testing.expectEqual(@as(usize, 1), current_session.bonusSpawnEvents().len);
}

test "runtime object behavior opens and clears scene-2 cellar message zones" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{ .x = 7680, .y = 2048, .z = 768 });

    try object_behavior.applyHeroIntent(&room, &current_session, .default_action);
    try std.testing.expectEqual(@as(?i16, 284), current_session.currentDialogId());
    try std.testing.expectEqual(runtime_session.text_interactions.TextInteractionOwner.room_message_zone, current_session.textUiState().owner.?);
    try std.testing.expect(object_behavior.cellarMessageAwaitsAdvance(&room, current_session));

    try object_behavior.applyHeroIntent(&room, &current_session, .default_action);
    try std.testing.expectEqual(@as(?i16, 284), current_session.currentDialogId());

    try object_behavior.applyHeroIntent(&room, &current_session, .advance_story);
    try std.testing.expectEqual(@as(?i16, null), current_session.currentDialogId());
    try std.testing.expect(!object_behavior.cellarMessageAwaitsAdvance(&room, current_session));
}

test "runtime object behavior applies the live-backed scene-2 cellar magic-ball pickup" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{ .x = 5293, .y = 1024, .z = 1786 });
    current_session.setGameVar(magic_ball_flag_index, 0);

    try object_behavior.applyHeroIntent(&room, &current_session, .default_action);

    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(magic_ball_flag_index));
    try std.testing.expectEqual(@as(u8, 0), current_session.magicLevel());
    try std.testing.expectEqual(@as(u8, 0), current_session.magicPoint());
    try std.testing.expectEqual(@as(?i16, null), current_session.currentDialogId());

    try object_behavior.applyHeroIntent(&room, &current_session, .default_action);
    try std.testing.expectEqual(@as(i16, 1), current_session.gameVar(magic_ball_flag_index));
}

test "runtime object behavior applies the live-backed scene-2 cellar magic-ball throw launch by mode" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    const Case = struct {
        mode: runtime_session.MagicBallThrowMode,
        pos_x: i32,
        pos_y: i32,
        pos_z: i32,
        vx: i16,
        vy: i16,
        vz: i16,
    };
    const cases = [_]Case{
        .{ .mode = .normal, .pos_x = 5016, .pos_y = 2241, .pos_z = 1901, .vx = -55, .vy = 18, .vz = 81 },
        .{ .mode = .sporty, .pos_x = 5013, .pos_y = 2237, .pos_z = 1906, .vx = -58, .vy = 13, .vz = 86 },
        .{ .mode = .aggressive, .pos_x = 5071, .pos_y = 2224, .pos_z = 1820, .vx = -62, .vy = 7, .vz = 91 },
        .{ .mode = .discreet, .pos_x = 5035, .pos_y = 2299, .pos_z = 1873, .vx = -36, .vy = 77, .vz = 53 },
    };

    for (cases) |case| {
        var current_session = try initSession(&room);
        defer current_session.deinit(std.testing.allocator);
        current_session.setHeroWorldPosition(.{ .x = 5071, .y = 1024, .z = 1820 });
        current_session.setGameVar(magic_ball_flag_index, 1);
        current_session.setMagicPoint(18);

        try object_behavior.applyHeroIntent(&room, &current_session, .{ .select_behavior_mode = case.mode });
        try object_behavior.applyHeroIntent(&room, &current_session, .select_magic_ball);
        try object_behavior.applyHeroIntent(&room, &current_session, .{ .throw_magic_ball = current_session.magicBallThrowMode() });

        try std.testing.expectEqual(@as(u8, 17), current_session.magicPoint());
        try std.testing.expectEqual(@as(usize, 1), current_session.magicBallProjectiles().len);
        const projectile = current_session.magicBallProjectiles()[0];
        try std.testing.expectEqual(case.mode, projectile.mode);
        try std.testing.expectEqual(@as(usize, 0), projectile.launch_frame_index);
        try std.testing.expectEqual(@as(i32, case.pos_x), projectile.world_position.x);
        try std.testing.expectEqual(@as(i32, case.pos_y), projectile.world_position.y);
        try std.testing.expectEqual(@as(i32, case.pos_z), projectile.world_position.z);
        try std.testing.expectEqual(@as(i32, 5071), projectile.origin_world_position.x);
        try std.testing.expectEqual(@as(i32, 2224), projectile.origin_world_position.y);
        try std.testing.expectEqual(@as(i32, 1820), projectile.origin_world_position.z);
        try std.testing.expectEqual(@as(i16, 8), projectile.sprite_index);
        try std.testing.expectEqual(case.vx, projectile.vx);
        try std.testing.expectEqual(case.vy, projectile.vy);
        try std.testing.expectEqual(case.vz, projectile.vz);
        try std.testing.expectEqual(@as(u32, 33038), projectile.flags);
        try std.testing.expectEqual(@as(i16, 0), projectile.timeout);
        try std.testing.expectEqual(@as(i16, 0), projectile.divers);
    }
}

test "runtime object behavior requires explicit Magic Ball selection before throw" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{ .x = 5071, .y = 1024, .z = 1820 });
    current_session.setGameVar(magic_ball_flag_index, 1);

    try std.testing.expectError(
        error.MagicBallNotSelected,
        object_behavior.applyHeroIntent(&room, &current_session, .{ .throw_magic_ball = .normal }),
    );
    try std.testing.expectEqual(@as(usize, 0), current_session.magicBallProjectiles().len);

    try object_behavior.applyHeroIntent(&room, &current_session, .select_magic_ball);
    try std.testing.expectEqual(runtime_session.SelectedWeapon.magic_ball, current_session.selectedWeapon());

    try object_behavior.applyHeroIntent(&room, &current_session, .{ .throw_magic_ball = .normal });
    try std.testing.expectEqual(@as(usize, 1), current_session.magicBallProjectiles().len);
}

test "runtime object behavior rejects scene-2 cellar magic-ball throw without the pickup flag" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{ .x = 5071, .y = 1024, .z = 1820 });
    current_session.setGameVar(magic_ball_flag_index, 0);

    try std.testing.expectError(
        error.MagicBallUnavailable,
        object_behavior.applyHeroIntent(&room, &current_session, .select_magic_ball),
    );
    try std.testing.expectEqual(runtime_session.SelectedWeapon.none, current_session.selectedWeapon());

    try std.testing.expectError(
        error.MagicBallUnavailable,
        object_behavior.applyHeroIntent(&room, &current_session, .{ .throw_magic_ball = .normal }),
    );
    try std.testing.expectEqual(@as(usize, 0), current_session.magicBallProjectiles().len);
}

test "runtime object behavior ignores scene-2 cellar default action outside message zones" {
    const allocator = std.testing.allocator;
    const resolved = try paths.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    var room = try room_state.loadRoomSnapshot(allocator, resolved, 2, 0);
    defer room.deinit(allocator);

    var current_session = try initSession(&room);
    defer current_session.deinit(std.testing.allocator);
    current_session.setHeroWorldPosition(.{ .x = 2562, .y = 2048, .z = 3322 });

    try object_behavior.applyHeroIntent(&room, &current_session, .default_action);
    try std.testing.expectEqual(@as(?i16, null), current_session.currentDialogId());
}

test "runtime object behavior ignores default action outside implemented key-source rooms" {
    const room = try room_fixtures.guarded22();

    var current_session = try initSession(room);
    defer current_session.deinit(std.testing.allocator);

    try object_behavior.applyHeroIntent(room, &current_session, .default_action);

    try std.testing.expectEqual(@as(i16, 0), current_session.gameVar(0));
    try std.testing.expectEqual(@as(u8, 0), current_session.littleKeyCount());
    try std.testing.expectEqual(@as(usize, 0), current_session.bonusSpawnEvents().len);
    try std.testing.expectEqual(@as(usize, 0), current_session.rewardCollectibles().len);
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
            .gen_anim = room.scene.object_behavior_seeds[0].gen_anim,
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
            .gen_anim = room.scene.object_behavior_seeds[0].gen_anim,
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

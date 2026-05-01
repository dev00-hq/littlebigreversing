const std = @import("std");
const reference_metadata = @import("../generated/reference_metadata.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const track_program = @import("../game_data/scene/track_program.zig");
const dialog_pagination = @import("dialog_pagination.zig");
const room_state = @import("room_state.zig");
const runtime_session = @import("session.zig");
const world_geometry = @import("world_geometry.zig");
const runtime_query = @import("world_query.zig");

pub const UpdateSummary = struct {
    updated_object_count: usize = 0,
};

const supported_scene_entry_index: usize = 19;
const supported_background_entry_index: usize = 19;
const supported_object_index: usize = 2;
const secret_room_scene_entry_index: usize = 2;
const secret_room_background_entry_index: usize = 1;
const secret_room_cellar_background_entry_index: usize = 0;
const secret_room_key_source_index: usize = 7;
const secret_room_key_scenario_zone_num: i16 = 0;
const secret_room_key_var_game_index: u8 = 0;
const secret_room_key_sprite_index: i16 = 6;
const secret_room_key_quantity: u8 = 1;
const secret_room_magic_ball_object_index: usize = 3;
const magic_ball_flag_index: u8 = 1;
const magic_ball_pickup_distance: i32 = 1024;
const magic_ball_projectile_sprite_index: i16 = 8;
const magic_ball_projectile_flags: u32 = 33038;
const magic_ball_projectile_origin_y_offset: i32 = 1200;
const sendell_scene_entry_index: usize = 36;
const sendell_background_entry_index: usize = 36;
const sendell_object_index: usize = 2;
const sendell_first_dialog_id: i16 = 3;
const sendell_dialog_record_text =
    "You just found Sendell's Ball. Now you have reached a new level of magic: Red Ball. It will also enable " ++
    "Sendell to contact you in case of danger.";
const sendell_page_boundary_offset = ("You just found Sendell's Ball. Now you have reached a new level of magic: Red Ball. It will also enable ").len;
const sendell_ball_flag_index: u8 = reference_metadata.sendell_ball_flag.index;
const lightning_spell_flag_index: u8 = reference_metadata.lightning_spell_flag.index;
const sendell_red_ball_magic_level: u8 = 3;
const supported_magic_bonus_option_flag: i16 = 64;
const supported_magic_bonus_sprite_index: i16 = 5;
const supported_magic_bonus_instance_count: usize = 10;
// Live guarded 19/19 seam captures show each emitted magic extra carries Divers=5.
const supported_magic_bonus_quantity_per_instance: u8 = 5;
const supported_reward_motion_ticks: u8 = 3;
const supported_reward_motion_arc_height: i32 = 160;
const track_wait_ticks_per_second: u8 = 10;

const supported_reward_origin_world_position = world_geometry.WorldPointSnapshot{
    .x = 21760,
    .y = 6656,
    .z = 3584,
};

const supported_reward_scatter_cells = [_]world_geometry.GridCell{
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

const secret_room_key_motion_start_world_position = world_geometry.WorldPointSnapshot{
    .x = 3072,
    .y = 3072,
    .z = 5120,
};

const secret_room_key_motion_target_world_position = world_geometry.WorldPointSnapshot{
    .x = 3768,
    .y = 2144,
    .z = 4366,
};
const secret_room_generated_save_key_source_position = world_geometry.WorldPointSnapshot{
    .x = 3478,
    .y = 2048,
    .z = 4772,
};
const secret_room_generated_save_key_source_tolerance_xz: i32 = 96;
const secret_room_generated_save_key_source_tolerance_y: i32 = 0;

const RuntimeFunctionValue = union(enum) {
    s8_value: i8,
    u8_value: u8,
    s16_value: i16,
};

pub const SendellDialogSlice = struct {
    page_number: u8,
    visible_text: []const u8,
    next_text: []const u8,
};

pub fn stepSupportedObjects(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !UpdateSummary {
    var updated_object_count: usize = 0;

    for (room.scene.object_behavior_seeds) |seed| {
        try stepSupportedObjectSeed(room, seed, current_session);
        updated_object_count += 1;
    }

    return .{ .updated_object_count = updated_object_count };
}

fn stepSupportedObjectSeed(
    room: *const room_state.RoomSnapshot,
    seed: room_state.ObjectBehaviorSeedSnapshot,
    current_session: *runtime_session.Session,
) !void {
    if (room.scene.entry_index == supported_scene_entry_index and
        room.background.entry_index == supported_background_entry_index and
        seed.index == supported_object_index)
    {
        try stepScene1919Object2(room, seed, current_session);
        return;
    }
    if (room.scene.entry_index == sendell_scene_entry_index and
        room.background.entry_index == sendell_background_entry_index and
        seed.index == sendell_object_index)
    {
        try stepScene3636Object2(seed, current_session);
        return;
    }
    if (room.scene.entry_index == 31 and room.background.entry_index == 31 and
        (seed.index == 3 or seed.index == 4))
    {
        return;
    }

    return error.UnsupportedObjectBehaviorSeed;
}

pub fn applyHeroIntent(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
    intent: runtime_session.HeroIntent,
) !void {
    switch (intent) {
        .cast_lightning => try applyScene3636CastLightning(room, current_session),
        .default_action => try applySecretRoomDefaultAction(room, current_session),
        .advance_story => try applyAdvanceStory(room, current_session),
        .throw_magic_ball => |mode| try applyScene2CellarMagicBallThrow(room, current_session, mode),
        .move_cardinal => return error.UnsupportedObjectBehaviorHeroIntent,
    }
}

pub fn sendellStoryAwaitsAdvance(
    room: *const room_state.RoomSnapshot,
    current_session: runtime_session.Session,
) bool {
    if (room.scene.entry_index != sendell_scene_entry_index or room.background.entry_index != sendell_background_entry_index) {
        return false;
    }
    const object_behavior = current_session.objectBehaviorStateByIndex(sendell_object_index) orelse return false;
    return switch (object_behavior.sendell_ball_phase) {
        .awaiting_first_dialog_ack,
        .awaiting_second_dialog_ack,
        => true,
        else => false,
    };
}

pub fn cellarMessageAwaitsAdvance(
    room: *const room_state.RoomSnapshot,
    current_session: runtime_session.Session,
) bool {
    if (room.scene.entry_index != secret_room_scene_entry_index or
        room.background.entry_index != secret_room_cellar_background_entry_index)
    {
        return false;
    }
    const dialog_id = current_session.currentDialogId() orelse return false;
    return isScene2CellarMessageDialog(dialog_id);
}

pub fn currentSendellDialogSlice(current_session: runtime_session.Session) ?SendellDialogSlice {
    const dialog_id = current_session.currentDialogId() orelse return null;
    if (dialog_id != sendell_first_dialog_id) return null;
    const object_behavior = current_session.objectBehaviorStateByIndex(sendell_object_index) orelse return null;
    const split = dialog_pagination.splitTextAtCursor(sendell_dialog_record_text, sendell_page_boundary_offset);
    return switch (object_behavior.sendell_ball_phase) {
        .awaiting_dialog_open, .awaiting_first_dialog_ack => .{
            .page_number = 1,
            .visible_text = split.text_before_cursor,
            .next_text = split.text_from_cursor,
        },
        .awaiting_second_dialog_ack => .{
            .page_number = 2,
            .visible_text = split.text_from_cursor,
            .next_text = "",
        },
        else => null,
    };
}

fn stepScene1919Object2(
    room: *const room_state.RoomSnapshot,
    seed: room_state.ObjectBehaviorSeedSnapshot,
    current_session: *runtime_session.Session,
) !void {
    const object_behavior = current_session.objectBehaviorStateByIndexPtr(seed.index) orelse return error.MissingRuntimeObjectBehaviorState;
    try executeScene1919Object2Life(room, seed, current_session, object_behavior);
    try executeScene1919Object2Track(seed.track_instructions, object_behavior);
}

fn stepScene3636Object2(
    seed: room_state.ObjectBehaviorSeedSnapshot,
    current_session: *runtime_session.Session,
) !void {
    const object_behavior = current_session.objectBehaviorStateByIndexPtr(seed.index) orelse return error.MissingRuntimeObjectBehaviorState;
    object_behavior.current_sprite = seed.sprite;
    if (object_behavior.sendell_ball_phase == .awaiting_dialog_open) {
        current_session.setMagicLevelAndRefill(sendell_red_ball_magic_level);
        try setCurrentDialogId(current_session, sendell_first_dialog_id);
        object_behavior.sendell_ball_phase = .awaiting_first_dialog_ack;
    }
}

fn applyScene3636CastLightning(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !void {
    if (room.scene.entry_index != sendell_scene_entry_index or room.background.entry_index != sendell_background_entry_index) {
        return error.UnsupportedObjectBehaviorHeroIntent;
    }

    const object_behavior = current_session.objectBehaviorStateByIndexPtr(sendell_object_index) orelse return error.MissingRuntimeObjectBehaviorState;
    if (current_session.gameVar(lightning_spell_flag_index) <= 0) return error.SendellLightningSpellUnavailable;
    if (current_session.gameVar(sendell_ball_flag_index) != 0 or object_behavior.sendell_ball_phase != .idle) {
        return error.SendellSequenceAlreadyConsumed;
    }

    const current_magic_level = current_session.magicLevel();
    if (current_magic_level == 0) return error.SendellRequiresMagicLevel;
    const expected_full_magic = current_magic_level * 20;
    if (current_session.magicPoint() != expected_full_magic) return error.SendellRequiresFullMagic;

    current_session.setMagicPoint(0);
    object_behavior.sendell_ball_phase = .awaiting_dialog_open;
}

fn applySecretRoomDefaultAction(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !void {
    if (room.scene.entry_index != secret_room_scene_entry_index) {
        return;
    }
    if (room.background.entry_index == secret_room_cellar_background_entry_index) {
        if (try applyScene2CellarMagicBallPickup(current_session)) return;
        try applyScene2CellarMessageAction(room, current_session);
        return;
    }
    if (room.background.entry_index != secret_room_background_entry_index) return;

    const query = runtime_query.init(room);
    if (current_session.gameVar(secret_room_key_var_game_index) != 0 or hasSecretRoomKeyCollectible(current_session.*)) return;
    const hero_position = current_session.heroWorldPosition();
    if (!try heroInsideSecretRoomKeyScenarioZone(query, hero_position) and
        !heroAtGeneratedSaveKeySource(hero_position))
    {
        return;
    }

    const key_landing_cell = try query.gridCellAtWorldPoint(
        secret_room_key_motion_target_world_position.x,
        secret_room_key_motion_target_world_position.z,
    );
    const key_landing_surface = try query.cellTopSurface(key_landing_cell.x, key_landing_cell.z);

    try current_session.appendBonusSpawnEvent(.{
        .frame_index = current_session.frame_index,
        .source_object_index = secret_room_key_source_index,
        .kind = .little_key,
        .sprite_index = secret_room_key_sprite_index,
        .quantity = secret_room_key_quantity,
    });
    try current_session.appendRewardCollectible(.{
        .spawn_frame_index = current_session.frame_index,
        .source_object_index = secret_room_key_source_index,
        .kind = .little_key,
        .sprite_index = secret_room_key_sprite_index,
        .quantity = secret_room_key_quantity,
        .admitted_surface_cell = key_landing_cell,
        .admitted_surface_top_y = key_landing_surface.top_y,
        .scatter_slot = 0,
        .rebound_count = 0,
        .settled = false,
        .motion_start_world_position = secret_room_key_motion_start_world_position,
        .motion_target_world_position = secret_room_key_motion_target_world_position,
        .motion_total_ticks = supported_reward_motion_ticks,
        .motion_ticks_remaining = supported_reward_motion_ticks,
        .motion_arc_height = supported_reward_motion_arc_height,
        .world_position = secret_room_key_motion_start_world_position,
    });
    current_session.setGameVar(secret_room_key_var_game_index, 1);
}

fn applyScene2CellarMagicBallPickup(
    current_session: *runtime_session.Session,
) !bool {
    if (current_session.gameVar(magic_ball_flag_index) != 0) return false;
    const magic_ball = current_session.objectSnapshotByIndex(secret_room_magic_ball_object_index) orelse return false;
    if (!heroWithinMagicBallPickupDistance(current_session.heroWorldPosition(), magic_ball)) return false;

    current_session.setGameVar(magic_ball_flag_index, 1);
    return true;
}

fn applyScene2CellarMagicBallThrow(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
    mode: runtime_session.MagicBallThrowMode,
) !void {
    if (room.scene.entry_index != secret_room_scene_entry_index or
        room.background.entry_index != secret_room_cellar_background_entry_index)
    {
        return error.UnsupportedObjectBehaviorHeroIntent;
    }
    if (current_session.gameVar(magic_ball_flag_index) <= 0) return error.MagicBallUnavailable;

    const hero_position = current_session.heroWorldPosition();
    const launch = magicBallLaunchForMode(mode, hero_position);
    if (current_session.magicPoint() > 0) current_session.setMagicPoint(current_session.magicPoint() - 1);
    try current_session.appendMagicBallProjectile(.{
        .launch_frame_index = current_session.frame_index,
        .mode = mode,
        .world_position = launch.world_position,
        .origin_world_position = launch.origin_world_position,
        .sprite_index = magic_ball_projectile_sprite_index,
        .vx = launch.vx,
        .vy = launch.vy,
        .vz = launch.vz,
        .flags = magic_ball_projectile_flags,
        .timeout = 0,
        .divers = 0,
    });
}

const MagicBallLaunchSnapshot = struct {
    world_position: world_geometry.WorldPointSnapshot,
    origin_world_position: world_geometry.WorldPointSnapshot,
    vx: i16,
    vy: i16,
    vz: i16,
};

fn magicBallLaunchForMode(
    mode: runtime_session.MagicBallThrowMode,
    hero_position: world_geometry.WorldPointSnapshot,
) MagicBallLaunchSnapshot {
    const origin = world_geometry.WorldPointSnapshot{
        .x = hero_position.x,
        .y = hero_position.y + magic_ball_projectile_origin_y_offset,
        .z = hero_position.z,
    };
    return switch (mode) {
        .normal => .{
            .origin_world_position = origin,
            .world_position = .{ .x = origin.x - 55, .y = origin.y + 17, .z = origin.z + 81 },
            .vx = -55,
            .vy = 18,
            .vz = 81,
        },
        .sporty => .{
            .origin_world_position = origin,
            .world_position = .{ .x = origin.x - 58, .y = origin.y + 13, .z = origin.z + 86 },
            .vx = -58,
            .vy = 13,
            .vz = 86,
        },
        .aggressive => .{
            .origin_world_position = origin,
            .world_position = origin,
            .vx = -62,
            .vy = 7,
            .vz = 91,
        },
        .discreet => .{
            .origin_world_position = origin,
            .world_position = .{ .x = origin.x - 36, .y = origin.y + 75, .z = origin.z + 53 },
            .vx = -36,
            .vy = 77,
            .vz = 53,
        },
    };
}

fn applyScene2CellarMessageAction(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !void {
    if (current_session.currentDialogId() != null) return;

    const zones = try runtime_query.init(room).containingZonesAtWorldPoint(current_session.heroWorldPosition());
    for (zones.slice()) |zone| switch (zone.semantics) {
        .message => |message| {
            if (!isScene2CellarMessageDialog(message.dialog_id)) continue;
            try setCurrentDialogId(current_session, message.dialog_id);
            return;
        },
        else => {},
    };
}

fn hasSecretRoomKeyCollectible(current_session: runtime_session.Session) bool {
    for (current_session.rewardCollectibles()) |collectible| {
        if (collectible.kind == .little_key and collectible.sprite_index == secret_room_key_sprite_index) return true;
    }
    return false;
}

fn heroInsideSecretRoomKeyScenarioZone(
    query: runtime_query.WorldQuery,
    hero_position: world_geometry.WorldPointSnapshot,
) !bool {
    const zones = try query.containingZonesAtWorldPoint(hero_position);
    for (zones.slice()) |zone| {
        if (zone.kind == .scenario and zone.num == secret_room_key_scenario_zone_num) return true;
    }
    return false;
}

fn heroAtGeneratedSaveKeySource(hero_position: world_geometry.WorldPointSnapshot) bool {
    return absDiff(hero_position.x, secret_room_generated_save_key_source_position.x) <= secret_room_generated_save_key_source_tolerance_xz and
        absDiff(hero_position.y, secret_room_generated_save_key_source_position.y) <= secret_room_generated_save_key_source_tolerance_y and
        absDiff(hero_position.z, secret_room_generated_save_key_source_position.z) <= secret_room_generated_save_key_source_tolerance_xz;
}

fn heroWithinMagicBallPickupDistance(
    hero_position: world_geometry.WorldPointSnapshot,
    magic_ball: runtime_session.ObjectState,
) bool {
    const dx: i64 = hero_position.x - magic_ball.x;
    const dz: i64 = hero_position.z - magic_ball.z;
    const threshold: i64 = magic_ball_pickup_distance;
    return (dx * dx) + (dz * dz) < threshold * threshold;
}

fn absDiff(lhs: i32, rhs: i32) i32 {
    return if (lhs >= rhs) lhs - rhs else rhs - lhs;
}

fn applyScene3636AdvanceStory(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !void {
    if (room.scene.entry_index != sendell_scene_entry_index or room.background.entry_index != sendell_background_entry_index) {
        return error.UnsupportedObjectBehaviorHeroIntent;
    }

    const object_behavior = current_session.objectBehaviorStateByIndexPtr(sendell_object_index) orelse return error.MissingRuntimeObjectBehaviorState;
    switch (object_behavior.sendell_ball_phase) {
        .awaiting_first_dialog_ack => {
            try setCurrentDialogId(current_session, sendell_first_dialog_id);
            object_behavior.sendell_ball_phase = .awaiting_second_dialog_ack;
        },
        .awaiting_second_dialog_ack => {
            current_session.clearCurrentDialogId();
            current_session.setGameVar(sendell_ball_flag_index, 1);
            object_behavior.sendell_ball_phase = .completed;
        },
        else => return error.SendellStoryAdvanceUnavailable,
    }
}

fn applyAdvanceStory(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
) !void {
    if (cellarMessageAwaitsAdvance(room, current_session.*)) {
        current_session.clearCurrentDialogId();
        return;
    }
    try applyScene3636AdvanceStory(room, current_session);
}

fn setCurrentDialogId(current_session: *runtime_session.Session, dialog_id: i16) !void {
    current_session.clearCurrentDialogId();
    try current_session.setCurrentDialogId(dialog_id);
}

fn isScene2CellarMessageDialog(dialog_id: i16) bool {
    return switch (dialog_id) {
        33, 283, 284 => true,
        else => false,
    };
}

fn executeScene1919Object2Life(
    room: *const room_state.RoomSnapshot,
    seed: room_state.ObjectBehaviorSeedSnapshot,
    current_session: *runtime_session.Session,
    object_behavior: *runtime_session.ObjectBehaviorState,
) !void {
    var instruction_index: usize = 0;
    var pending_track_offset: ?i16 = null;
    while (instruction_index < seed.life_instructions.len) {
        const instruction = seed.life_instructions[instruction_index];
        const runtime_opcode = try currentLifeOpcode(object_behavior.*, instruction);

        switch (runtime_opcode) {
            .LM_IF,
            .LM_AND_IF,
            => {
                const condition = switch (instruction.operands) {
                    .condition => |value| value,
                    else => return error.UnsupportedObjectBehaviorLifeOperands,
                };
                if (!try evaluateScene1919Object2Condition(room, condition, current_session, object_behavior.*)) {
                    instruction_index = instructionIndexForOffset(
                        life_program.LifeInstruction,
                        seed.life_instructions,
                        try resolveAbsoluteOffset(condition.jump_offset),
                    ) orelse return error.UnsupportedObjectBehaviorLifeJumpTarget;
                    continue;
                }
            },
            .LM_OR_IF => {
                const condition = switch (instruction.operands) {
                    .condition => |value| value,
                    else => return error.UnsupportedObjectBehaviorLifeOperands,
                };
                if (try evaluateScene1919Object2Condition(room, condition, current_session, object_behavior.*)) {
                    instruction_index = instructionIndexForOffset(
                        life_program.LifeInstruction,
                        seed.life_instructions,
                        try resolveAbsoluteOffset(condition.jump_offset),
                    ) orelse return error.UnsupportedObjectBehaviorLifeJumpTarget;
                    continue;
                }
            },
            .LM_ELSE => {
                const target_offset = switch (instruction.operands) {
                    .i16_value => |value| value,
                    else => return error.UnsupportedObjectBehaviorLifeOperands,
                };
                instruction_index = instructionIndexForOffset(
                    life_program.LifeInstruction,
                    seed.life_instructions,
                    try resolveAbsoluteOffset(target_offset),
                ) orelse return error.UnsupportedObjectBehaviorLifeJumpTarget;
                continue;
            },
            .LM_SET_TRACK => {
                const track_offset = switch (instruction.operands) {
                    .i16_value => |value| value,
                    else => return error.UnsupportedObjectBehaviorLifeOperands,
                };
                pending_track_offset = track_offset;
            },
            .LM_SET_VAR_CUBE => {
                const operands = switch (instruction.operands) {
                    .u8_pair => |value| value,
                    else => return error.UnsupportedObjectBehaviorLifeOperands,
                };
                current_session.setCubeVar(operands.first, operands.second);
            },
            .LM_ADD_VAR_CUBE => {
                const operands = switch (instruction.operands) {
                    .u8_pair => |value| value,
                    else => return error.UnsupportedObjectBehaviorLifeOperands,
                };
                current_session.addCubeVarSaturating(operands.first, operands.second);
            },
            .LM_SWIF => {
                const condition = switch (instruction.operands) {
                    .condition => |value| value,
                    else => return error.UnsupportedObjectBehaviorLifeOperands,
                };
                if (!try evaluateScene1919Object2Condition(room, condition, current_session, object_behavior.*)) {
                    instruction_index = instructionIndexForOffset(
                        life_program.LifeInstruction,
                        seed.life_instructions,
                        try resolveAbsoluteOffset(condition.jump_offset),
                    ) orelse return error.UnsupportedObjectBehaviorLifeJumpTarget;
                    continue;
                }

                try mutateLifeOpcodeByte(object_behavior, instruction.offset, .LM_SNIF);
            },
            .LM_SNIF => {
                const condition = switch (instruction.operands) {
                    .condition => |value| value,
                    else => return error.UnsupportedObjectBehaviorLifeOperands,
                };
                if (!try evaluateScene1919Object2Condition(room, condition, current_session, object_behavior.*)) {
                    try mutateLifeOpcodeByte(object_behavior, instruction.offset, .LM_SWIF);
                }

                instruction_index = instructionIndexForOffset(
                    life_program.LifeInstruction,
                    seed.life_instructions,
                    try resolveAbsoluteOffset(condition.jump_offset),
                ) orelse return error.UnsupportedObjectBehaviorLifeJumpTarget;
                continue;
            },
            .LM_GIVE_BONUS => {
                const exhaust_after_use = switch (instruction.operands) {
                    .u8_value => |value| value == 0,
                    else => return error.UnsupportedObjectBehaviorLifeOperands,
                };
                try appendSupportedBonusSpawn(room, seed, current_session, object_behavior, exhaust_after_use);
            },
            .LM_END_COMPORTEMENT,
            .LM_END,
            => break,
            else => return error.UnsupportedScene1919Object2LifeOpcode,
        }

        instruction_index += 1;
    }

    if (pending_track_offset) |track_offset| {
        try setTrackState(seed.track_instructions, object_behavior, track_offset);
    }
}

fn executeScene1919Object2Track(
    instructions: []const track_program.TrackInstruction,
    object_behavior: *runtime_session.ObjectBehaviorState,
) !void {
    const start_offset = object_behavior.current_track_resume_offset orelse object_behavior.current_track_offset orelse return;
    var instruction_index = instructionIndexForOffset(
        track_program.TrackInstruction,
        instructions,
        try resolveAbsoluteOffset(start_offset),
    ) orelse return error.UnsupportedObjectBehaviorTrackStartOffset;

    if (object_behavior.wait_ticks_remaining > 0) {
        object_behavior.wait_ticks_remaining -= 1;
        if (object_behavior.wait_ticks_remaining > 0) return;
    }

    while (instruction_index < instructions.len) {
        const instruction = instructions[instruction_index];
        switch (instruction.opcode) {
            .rem => {},
            .label => {
                const operands = switch (instruction.operands) {
                    .label => |value| value,
                    else => return error.UnsupportedObjectBehaviorTrackOperands,
                };
                object_behavior.current_track_label = operands.label;
            },
            .sample,
            .sample_stop,
            .sample_always,
            .speed,
            .frequence,
            => {
                _ = try expectTrackI16Operand(instruction);
            },
            .volume => {
                _ = try expectTrackU8Operand(instruction);
            },
            .sprite => {
                const sprite = switch (instruction.operands) {
                    .i16_value => |value| value,
                    else => return error.UnsupportedObjectBehaviorTrackOperands,
                };
                object_behavior.current_sprite = sprite;
            },
            .wait_nb_second, .wait_nb_dizieme => {
                object_behavior.current_track_resume_offset = nextInstructionOffset(
                    track_program.TrackInstruction,
                    instructions,
                    instruction_index,
                );
                object_behavior.wait_ticks_remaining = try trackWaitTicks(instruction);
                return;
            },
            .stop,
            .end,
            => {
                object_behavior.current_track_resume_offset = null;
                return;
            },
            else => return error.UnsupportedScene1919Object2TrackOpcode,
        }

        instruction_index += 1;
    }

    object_behavior.current_track_resume_offset = null;
}

fn evaluateScene1919Object2Condition(
    room: *const room_state.RoomSnapshot,
    condition: life_program.LifeCondition,
    current_session: *runtime_session.Session,
    object_behavior: runtime_session.ObjectBehaviorState,
) !bool {
    const lhs = try evaluateScene1919Object2Function(room, condition.function, current_session, object_behavior);
    return compareFunctionValue(lhs, condition.comparison);
}

fn evaluateScene1919Object2Function(
    room: *const room_state.RoomSnapshot,
    function_call: life_program.LifeFunctionCall,
    current_session: *runtime_session.Session,
    object_behavior: runtime_session.ObjectBehaviorState,
) !RuntimeFunctionValue {
    return switch (function_call.function) {
        .LF_HIT_BY => switch (function_call.operands) {
            .none => .{ .s8_value = object_behavior.last_hit_by },
            else => error.UnsupportedObjectBehaviorLifeFunctionOperands,
        },
        .LF_VAR_CUBE => .{ .u8_value = current_session.cubeVar(try expectFunctionU8Operand(function_call)) },
        .LF_L_TRACK => switch (function_call.operands) {
            .none => .{ .u8_value = object_behavior.current_track_label orelse std.math.maxInt(u8) },
            else => error.UnsupportedObjectBehaviorLifeFunctionOperands,
        },
        .LF_ZONE_OBJ => .{
            .s8_value = try zoneFunctionValue(room, current_session, function_call),
        },
        else => error.UnsupportedScene1919Object2LifeFunction,
    };
}

fn expectFunctionU8Operand(function_call: life_program.LifeFunctionCall) !u8 {
    return switch (function_call.operands) {
        .u8_value => |value| value,
        else => error.UnsupportedObjectBehaviorLifeFunctionOperands,
    };
}

fn compareFunctionValue(
    lhs: RuntimeFunctionValue,
    comparison: life_program.LifeTest,
) !bool {
    return switch (lhs) {
        .s8_value => |value| switch (comparison.literal) {
            .s8_value => |literal| compareValues(comparison.comparator, value, literal),
            else => error.UnsupportedObjectBehaviorLifeLiteral,
        },
        .u8_value => |value| switch (comparison.literal) {
            .u8_value => |literal| compareValues(comparison.comparator, value, literal),
            else => error.UnsupportedObjectBehaviorLifeLiteral,
        },
        .s16_value => |value| switch (comparison.literal) {
            .s16_value => |literal| compareValues(comparison.comparator, value, literal),
            else => error.UnsupportedObjectBehaviorLifeLiteral,
        },
    };
}

fn compareValues(
    comparator: life_program.LifeComparator,
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool {
    return switch (comparator) {
        .LT_EQUAL => lhs == rhs,
        .LT_SUP => lhs > rhs,
        .LT_LESS => lhs < rhs,
        .LT_SUP_EQUAL => lhs >= rhs,
        .LT_LESS_EQUAL => lhs <= rhs,
        .LT_DIFFERENT => lhs != rhs,
    };
}

fn currentLifeOpcode(
    object_behavior: runtime_session.ObjectBehaviorState,
    instruction: life_program.LifeInstruction,
) !life_program.LifeOpcode {
    if (instruction.offset >= object_behavior.life_bytes.len) return error.UnsupportedObjectBehaviorLifeOpcodeOffset;
    return enumFromInt(life_program.LifeOpcode, object_behavior.life_bytes[instruction.offset]) orelse return error.UnsupportedObjectBehaviorLifeOpcodeByte;
}

fn enumFromInt(comptime T: type, raw_value: anytype) ?T {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        if (raw_value == field.value) return @enumFromInt(field.value);
    }
    return null;
}

fn mutateLifeOpcodeByte(
    object_behavior: *runtime_session.ObjectBehaviorState,
    offset: usize,
    opcode: life_program.LifeOpcode,
) !void {
    if (offset >= object_behavior.life_bytes.len) return error.UnsupportedObjectBehaviorLifeOpcodeOffset;
    object_behavior.life_bytes[offset] = @intFromEnum(opcode);
}

fn zoneFunctionValue(
    room: *const room_state.RoomSnapshot,
    current_session: *runtime_session.Session,
    function_call: life_program.LifeFunctionCall,
) !i8 {
    const object_index = try expectFunctionU8Operand(function_call);
    if (object_index != 0) return error.UnsupportedScene1919Object2LifeFunctionObjectIndex;
    return currentHeroScenarioZone(room, current_session.heroWorldPosition());
}

fn currentHeroScenarioZone(
    room: *const room_state.RoomSnapshot,
    hero_position: world_geometry.WorldPointSnapshot,
) !i8 {
    var current_zone: i8 = -1;
    for (room.scene.zones) |zone| {
        if (zone.kind != .scenario) continue;
        if (!runtime_query.runtimeSceneZoneContainsWorldPoint(zone, hero_position)) continue;
        current_zone = std.math.cast(i8, zone.num) orelse return error.UnsupportedScene1919Object2ZoneNumberRange;
    }
    return current_zone;
}

fn expectTrackI16Operand(instruction: track_program.TrackInstruction) !i16 {
    return switch (instruction.operands) {
        .i16_value => |value| value,
        else => error.UnsupportedObjectBehaviorTrackOperands,
    };
}

fn expectTrackU8Operand(instruction: track_program.TrackInstruction) !u8 {
    return switch (instruction.operands) {
        .u8_value => |value| value,
        else => error.UnsupportedObjectBehaviorTrackOperands,
    };
}

fn trackWaitTicks(instruction: track_program.TrackInstruction) !u8 {
    const operands = switch (instruction.operands) {
        .wait_timer => |value| value,
        else => return error.UnsupportedObjectBehaviorTrackOperands,
    };

    return switch (instruction.opcode) {
        .wait_nb_dizieme => operands.raw_count,
        .wait_nb_second => {
            const ticks: u16 = @as(u16, operands.raw_count) * track_wait_ticks_per_second;
            return std.math.cast(u8, ticks) orelse error.UnsupportedObjectBehaviorTrackWaitRange;
        },
        else => error.UnsupportedScene1919Object2TrackOpcode,
    };
}

fn setTrackState(
    instructions: []const track_program.TrackInstruction,
    object_behavior: *runtime_session.ObjectBehaviorState,
    track_offset: i16,
) !void {
    object_behavior.current_track_offset = track_offset;
    object_behavior.current_track_resume_offset = track_offset;
    object_behavior.current_track_label = try trackLabelAtOffset(instructions, track_offset);
    object_behavior.wait_ticks_remaining = 0;
}

fn trackLabelAtOffset(
    instructions: []const track_program.TrackInstruction,
    target_offset: i16,
) !?u8 {
    var instruction_index = instructionIndexForOffset(
        track_program.TrackInstruction,
        instructions,
        try resolveAbsoluteOffset(target_offset),
    ) orelse return error.UnsupportedObjectBehaviorTrackStartOffset;

    while (instruction_index < instructions.len) {
        const instruction = instructions[instruction_index];
        switch (instruction.opcode) {
            .label => {
                return switch (instruction.operands) {
                    .label => |value| value.label,
                    else => return error.UnsupportedObjectBehaviorTrackOperands,
                };
            },
            .stop, .end => return null,
            else => instruction_index += 1,
        }
    }

    return null;
}

fn nextInstructionOffset(
    comptime Instruction: type,
    instructions: []const Instruction,
    instruction_index: usize,
) ?i16 {
    if (instruction_index + 1 >= instructions.len) return null;
    return std.math.cast(i16, instructions[instruction_index + 1].offset);
}

fn appendSupportedBonusSpawn(
    room: *const room_state.RoomSnapshot,
    seed: room_state.ObjectBehaviorSeedSnapshot,
    current_session: *runtime_session.Session,
    object_behavior: *runtime_session.ObjectBehaviorState,
    exhaust_after_use: bool,
) !void {
    if (object_behavior.bonus_exhausted) return;
    if ((seed.option_flags & supported_magic_bonus_option_flag) == 0) {
        return error.UnsupportedScene1919Object2BonusFlags;
    }

    if (supported_reward_scatter_cells.len != supported_magic_bonus_instance_count) {
        return error.UnsupportedScene1919Object2RewardScatterLayout;
    }

    var total_emitted_count: u16 = object_behavior.emitted_bonus_count;
    for (supported_reward_scatter_cells, 0..) |cell, scatter_index| {
        const surface = try runtime_query.init(room).cellTopSurface(cell.x, cell.z);
        const landing_world_position = runtime_query.gridCellCenterWorldPosition(
            cell.x,
            cell.z,
            surface.top_y,
        );

        try current_session.appendBonusSpawnEvent(.{
            .frame_index = current_session.frame_index,
            .source_object_index = seed.index,
            .kind = .magic,
            .sprite_index = supported_magic_bonus_sprite_index,
            .quantity = supported_magic_bonus_quantity_per_instance,
        });
        try current_session.appendRewardCollectible(.{
            .spawn_frame_index = current_session.frame_index,
            .source_object_index = seed.index,
            .kind = .magic,
            .sprite_index = supported_magic_bonus_sprite_index,
            .quantity = supported_magic_bonus_quantity_per_instance,
            .admitted_surface_cell = cell,
            .admitted_surface_top_y = surface.top_y,
            .scatter_slot = std.math.cast(u8, scatter_index) orelse return error.UnsupportedScene1919Object2RewardScatterLayout,
            .rebound_count = 0,
            .settled = false,
            .motion_start_world_position = supported_reward_origin_world_position,
            .motion_target_world_position = landing_world_position,
            .motion_total_ticks = supported_reward_motion_ticks,
            .motion_ticks_remaining = supported_reward_motion_ticks,
            .motion_arc_height = supported_reward_motion_arc_height,
            .world_position = supported_reward_origin_world_position,
        });
        total_emitted_count = @min(total_emitted_count + 1, std.math.maxInt(u8));
    }
    object_behavior.emitted_bonus_count = @intCast(total_emitted_count);
    object_behavior.bonus_exhausted = true;
    if (exhaust_after_use) object_behavior.bonus_exhausted = true;
}

fn resolveAbsoluteOffset(offset: i16) !usize {
    if (offset < 0) return error.UnsupportedNegativeObjectBehaviorOffset;
    return std.math.cast(usize, offset) orelse return error.UnsupportedObjectBehaviorOffsetRange;
}

fn instructionIndexForOffset(
    comptime Instruction: type,
    instructions: []const Instruction,
    target_offset: usize,
) ?usize {
    for (instructions, 0..) |instruction, instruction_index| {
        if (instruction.offset == target_offset) return instruction_index;
    }
    return null;
}

test "runtime object behavior track interpreter accepts bounded audio-control no-ops and second waits" {
    var object_state = runtime_session.ObjectBehaviorState{
        .index = 2,
        .current_track_offset = 0,
        .current_track_resume_offset = 0,
        .current_track_label = null,
        .current_sprite = 137,
        .current_gen_anim = 0,
        .next_gen_anim = 0,
        .wait_ticks_remaining = 0,
        .last_hit_by = 0,
        .sendell_ball_phase = .idle,
        .emitted_bonus_count = 0,
        .bonus_exhausted = false,
        .life_bytes = try std.testing.allocator.dupe(u8, &.{}),
    };
    defer std.testing.allocator.free(object_state.life_bytes);

    const instructions = [_]track_program.TrackInstruction{
        .{ .offset = 0, .opcode = .label, .byte_length = 2, .operands = .{ .label = .{ .label = 4 } } },
        .{ .offset = 2, .opcode = .sample_stop, .byte_length = 3, .operands = .{ .i16_value = 446 } },
        .{ .offset = 5, .opcode = .speed, .byte_length = 3, .operands = .{ .i16_value = 1500 } },
        .{ .offset = 8, .opcode = .volume, .byte_length = 2, .operands = .{ .u8_value = 20 } },
        .{ .offset = 10, .opcode = .frequence, .byte_length = 3, .operands = .{ .i16_value = 700 } },
        .{ .offset = 13, .opcode = .sample_always, .byte_length = 3, .operands = .{ .i16_value = 446 } },
        .{ .offset = 16, .opcode = .wait_nb_second, .byte_length = 6, .operands = .{ .wait_timer = .{ .raw_count = 2, .deadline_timestamp = 0 } } },
        .{ .offset = 22, .opcode = .sprite, .byte_length = 3, .operands = .{ .i16_value = 144 } },
        .{ .offset = 25, .opcode = .end, .byte_length = 1, .operands = .{ .none = {} } },
    };

    try executeScene1919Object2Track(&instructions, &object_state);
    try std.testing.expectEqual(@as(?u8, 4), object_state.current_track_label);
    try std.testing.expectEqual(@as(i16, 137), object_state.current_sprite);
    try std.testing.expectEqual(@as(?i16, 22), object_state.current_track_resume_offset);
    try std.testing.expectEqual(@as(u8, 20), object_state.wait_ticks_remaining);

    for (0..20) |_| {
        try executeScene1919Object2Track(&instructions, &object_state);
    }

    try std.testing.expectEqual(@as(i16, 144), object_state.current_sprite);
    try std.testing.expectEqual(@as(?i16, null), object_state.current_track_resume_offset);
    try std.testing.expectEqual(@as(u8, 0), object_state.wait_ticks_remaining);
}

test "runtime object behavior track interpreter fails fast on overflowing second waits" {
    var object_state = runtime_session.ObjectBehaviorState{
        .index = 2,
        .current_track_offset = 0,
        .current_track_resume_offset = 0,
        .current_track_label = null,
        .current_sprite = 137,
        .current_gen_anim = 0,
        .next_gen_anim = 0,
        .wait_ticks_remaining = 0,
        .last_hit_by = 0,
        .sendell_ball_phase = .idle,
        .emitted_bonus_count = 0,
        .bonus_exhausted = false,
        .life_bytes = try std.testing.allocator.dupe(u8, &.{}),
    };
    defer std.testing.allocator.free(object_state.life_bytes);

    const instructions = [_]track_program.TrackInstruction{
        .{ .offset = 0, .opcode = .wait_nb_second, .byte_length = 6, .operands = .{ .wait_timer = .{ .raw_count = 26, .deadline_timestamp = 0 } } },
    };

    try std.testing.expectError(
        error.UnsupportedObjectBehaviorTrackWaitRange,
        executeScene1919Object2Track(&instructions, &object_state),
    );
}

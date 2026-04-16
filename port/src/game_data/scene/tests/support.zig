const std = @import("std");
const asset_fixtures = @import("../../../assets/fixtures.zig");
const paths_mod = @import("../../../foundation/paths.zig");
const life_program = @import("../life_program.zig");
const track_program = @import("../track_program.zig");
const zones = @import("../zones.zig");

pub fn stringifyJsonAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(value);
    return allocator.dupe(u8, out.written());
}

fn appendInt(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
    const T = @TypeOf(value);
    var buffer: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buffer, value, .little);
    try list.appendSlice(allocator, &buffer);
}

pub fn buildSyntheticScenePayload(allocator: std.mem.Allocator) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    try bytes.appendSlice(allocator, &.{ 0, 1, 2, 12, 0, 0, 0 });
    try appendInt(&bytes, allocator, @as(i16, 414));
    try appendInt(&bytes, allocator, @as(i16, 136));
    for (0..4) |_| {
        try appendInt(&bytes, allocator, @as(i16, -1));
        try appendInt(&bytes, allocator, @as(i16, 1));
        try appendInt(&bytes, allocator, @as(i16, 1));
        try appendInt(&bytes, allocator, @as(i16, 4096));
        try appendInt(&bytes, allocator, @as(i16, 110));
    }
    try appendInt(&bytes, allocator, @as(i16, 10));
    try appendInt(&bytes, allocator, @as(i16, 10));
    try bytes.append(allocator, 21);

    try appendInt(&bytes, allocator, @as(i16, 100));
    try appendInt(&bytes, allocator, @as(i16, 200));
    try appendInt(&bytes, allocator, @as(i16, 300));
    try appendInt(&bytes, allocator, @as(u16, 1));
    try bytes.append(allocator, 0x00);
    try appendInt(&bytes, allocator, @as(u16, 2));
    try bytes.appendSlice(allocator, &.{ 0xAA, 0xBB });

    try appendInt(&bytes, allocator, @as(u16, 2));
    try appendInt(&bytes, allocator, @as(u32, 0x00001200));
    try appendInt(&bytes, allocator, @as(i16, 16));
    try bytes.append(allocator, 4);
    try appendInt(&bytes, allocator, @as(i16, 5));
    try appendInt(&bytes, allocator, @as(i16, 6));
    try appendInt(&bytes, allocator, @as(i16, 700));
    try appendInt(&bytes, allocator, @as(i16, 800));
    try appendInt(&bytes, allocator, @as(i16, 900));
    try bytes.append(allocator, 3);
    try appendInt(&bytes, allocator, @as(i16, 10));
    try appendInt(&bytes, allocator, @as(i16, 1024));
    try appendInt(&bytes, allocator, @as(i16, 40));
    try bytes.append(allocator, 7);
    try appendInt(&bytes, allocator, @as(i16, 11));
    try appendInt(&bytes, allocator, @as(i16, 12));
    try appendInt(&bytes, allocator, @as(i16, 13));
    try appendInt(&bytes, allocator, @as(i16, 14));
    try appendInt(&bytes, allocator, @as(i16, 15));
    try bytes.append(allocator, 9);
    try bytes.append(allocator, 2);
    try bytes.append(allocator, 100);
    try appendInt(&bytes, allocator, @as(u16, 1));
    try bytes.append(allocator, 0x01);
    try appendInt(&bytes, allocator, @as(u16, 1));
    try bytes.append(allocator, 0x02);

    try appendInt(&bytes, allocator, @as(u32, 0x12345678));
    try appendInt(&bytes, allocator, @as(u16, 1));
    try appendInt(&bytes, allocator, @as(i32, 10));
    try appendInt(&bytes, allocator, @as(i32, 20));
    try appendInt(&bytes, allocator, @as(i32, 30));
    try appendInt(&bytes, allocator, @as(i32, 40));
    try appendInt(&bytes, allocator, @as(i32, 50));
    try appendInt(&bytes, allocator, @as(i32, 60));
    try appendInt(&bytes, allocator, @as(i32, 70));
    try appendInt(&bytes, allocator, @as(i32, 71));
    try appendInt(&bytes, allocator, @as(i32, 1));
    try appendInt(&bytes, allocator, @as(i32, 73));
    try appendInt(&bytes, allocator, @as(i32, 74));
    try appendInt(&bytes, allocator, @as(i32, 75));
    try appendInt(&bytes, allocator, @as(i32, 76));
    try appendInt(&bytes, allocator, @as(i32, 77));
    try appendInt(&bytes, allocator, @as(i16, 5));
    try appendInt(&bytes, allocator, @as(i16, 6));

    try appendInt(&bytes, allocator, @as(u16, 2));
    try appendInt(&bytes, allocator, @as(i32, 1000));
    try appendInt(&bytes, allocator, @as(i32, 2000));
    try appendInt(&bytes, allocator, @as(i32, 3000));
    try appendInt(&bytes, allocator, @as(i32, 4000));
    try appendInt(&bytes, allocator, @as(i32, 5000));
    try appendInt(&bytes, allocator, @as(i32, 6000));

    try appendInt(&bytes, allocator, @as(u32, 1));
    try appendInt(&bytes, allocator, @as(i16, 2));
    try appendInt(&bytes, allocator, @as(i16, 99));

    return bytes.toOwnedSlice(allocator);
}

pub fn fixtureTargetById(target_id: []const u8) !asset_fixtures.FixtureTarget {
    for (asset_fixtures.fixture_targets) |target| {
        if (std.mem.eql(u8, target.target_id, target_id)) return target;
    }
    return error.MissingFixtureTarget;
}

pub fn resolveSceneArchivePathForTests(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    return std.fs.path.join(allocator, &.{ resolved.asset_root, relative_path });
}

pub fn makeRawZone(zone_type: i16, num: i16, raw_info: [8]i32) zones.RawSceneZone {
    return .{
        .x0 = 10,
        .y0 = 20,
        .z0 = 30,
        .x1 = 40,
        .y1 = 50,
        .z1 = 60,
        .raw_info = raw_info,
        .type_id = zone_type,
        .num = num,
    };
}

pub fn instructionStreamByteLength(instructions: []const track_program.TrackInstruction) !usize {
    var total: usize = 0;
    for (instructions) |instruction| {
        try std.testing.expectEqual(total, instruction.offset);
        total += instruction.byte_length;
    }
    return total;
}

pub fn lifeInstructionStreamByteLength(instructions: []const life_program.LifeInstruction) !usize {
    var total: usize = 0;
    for (instructions) |instruction| {
        try std.testing.expectEqual(total, instruction.offset);
        total += instruction.byte_length;
    }
    return total;
}

pub fn buildInstructionSample(allocator: std.mem.Allocator, opcode: track_program.TrackOpcode) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    try bytes.append(allocator, @intFromEnum(opcode));
    switch (opcode) {
        .end,
        .nop,
        .wait_anim,
        .stop,
        .no_body,
        .close,
        .wait_door,
        .rem,
        .do,
        .aff_timer,
        .stop_anim_3ds,
        .wait_anim_3ds,
        => {},
        .body,
        .goto_point,
        .goto_point_3d,
        .goto_sym_point,
        .pos_point,
        .set_frame,
        .set_frame_3ds,
        .set_start_3ds,
        .set_end_3ds,
        .start_anim_3ds,
        .wait_frame_3ds,
        .volume,
        => try bytes.append(allocator, 7),
        .anim => try appendInt(&bytes, allocator, @as(u16, 513)),
        .sample,
        .sample_rnd,
        .sample_always,
        .sample_stop,
        .repeat_sample,
        .simple_sample,
        .speed,
        .beta,
        .open_left,
        .open_right,
        .open_up,
        .open_down,
        .goto,
        .sprite,
        .decalage,
        .frequence,
        => try appendInt(&bytes, allocator, @as(i16, -1234)),
        .background => try bytes.append(allocator, 1),
        .label => try bytes.append(allocator, 42),
        .wait_nb_anim => try bytes.appendSlice(allocator, &.{ 4, 1 }),
        .wait_nb_second,
        .wait_nb_second_rnd,
        .wait_nb_dizieme,
        .wait_nb_dizieme_rnd,
        => {
            try bytes.append(allocator, 9);
            try appendInt(&bytes, allocator, @as(u32, 0x12345678));
        },
        .loop => {
            try bytes.appendSlice(allocator, &.{ 5, 3 });
            try appendInt(&bytes, allocator, @as(i16, 300));
        },
        .angle => try appendInt(&bytes, allocator, @as(u16, 0x8123)),
        .face_twinsen => try appendInt(&bytes, allocator, @as(i16, -1)),
        .angle_rnd => {
            try appendInt(&bytes, allocator, @as(i16, 120));
            try appendInt(&bytes, allocator, @as(i16, -1));
        },
        .play_acf => try bytes.appendSlice(allocator, &.{ 'I', 'N', 'T', 'R', 'O', 0 }),
    }

    return bytes.toOwnedSlice(allocator);
}

pub fn expectedTrackInstructionByteLengthIndependent(opcode: track_program.TrackOpcode) usize {
    return switch (opcode) {
        .end,
        .nop,
        .wait_anim,
        .stop,
        .no_body,
        .close,
        .wait_door,
        .rem,
        .do,
        .aff_timer,
        .stop_anim_3ds,
        .wait_anim_3ds,
        => 1,

        .body,
        .goto_point,
        .goto_point_3d,
        .goto_sym_point,
        .pos_point,
        .set_frame,
        .set_frame_3ds,
        .set_start_3ds,
        .set_end_3ds,
        .start_anim_3ds,
        .wait_frame_3ds,
        .volume,
        .background,
        .label,
        => 2,

        .anim,
        .sample,
        .sample_rnd,
        .sample_always,
        .sample_stop,
        .repeat_sample,
        .simple_sample,
        .speed,
        .beta,
        .open_left,
        .open_right,
        .open_up,
        .open_down,
        .goto,
        .sprite,
        .decalage,
        .frequence,
        .wait_nb_anim,
        .angle,
        .face_twinsen,
        => 3,

        .loop => 5,
        .angle_rnd => 5,

        .wait_nb_second,
        .wait_nb_second_rnd,
        .wait_nb_dizieme,
        .wait_nb_dizieme_rnd,
        => 6,

        .play_acf => 7,
    };
}

fn appendLifeFunctionSample(list: *std.ArrayList(u8), allocator: std.mem.Allocator, function: life_program.LifeFunction) !void {
    try list.append(allocator, @intFromEnum(function));
    switch (function) {
        .LF_VAR_CUBE => try list.append(allocator, 7),
        .LF_VAR_GAME => try list.append(allocator, 3),
        else => {},
    }
}

fn appendLifeTestSample(
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    comparator: life_program.LifeComparator,
    return_type: life_program.LifeReturnType,
) !void {
    try list.append(allocator, @intFromEnum(comparator));
    switch (return_type) {
        .RET_S8 => try list.append(allocator, @bitCast(@as(i8, -4))),
        .RET_U8 => try list.append(allocator, 4),
        .RET_S16 => try appendInt(list, allocator, @as(i16, -321)),
        .RET_STRING => try list.appendSlice(allocator, &.{ 'Z', 'O', 'E', 0 }),
    }
}

pub fn buildLifeInstructionSample(allocator: std.mem.Allocator, opcode: life_program.LifeOpcode) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    switch (opcode) {
        .LM_CASE,
        .LM_OR_CASE,
        => {
            try bytes.append(allocator, @intFromEnum(life_program.LifeOpcode.LM_SWITCH));
            try appendLifeFunctionSample(&bytes, allocator, .LF_VAR_GAME);
            try bytes.append(allocator, @intFromEnum(opcode));
            try appendInt(&bytes, allocator, @as(i16, 123));
            try appendLifeTestSample(&bytes, allocator, .LT_EQUAL, .RET_S16);
            return bytes.toOwnedSlice(allocator);
        },
        else => try bytes.append(allocator, @intFromEnum(opcode)),
    }

    switch (opcode) {
        .LM_END,
        .LM_RETURN,
        .LM_END_COMPORTEMENT,
        .LM_SUICIDE,
        .LM_END_LIFE,
        .LM_STOP_L_TRACK,
        .LM_RESTORE_L_TRACK,
        .LM_INC_CHAPTER,
        .LM_USE_ONE_LITTLE_KEY,
        .LM_INC_CLOVER_BOX,
        .LM_FULL_POINT,
        .LM_GAME_OVER,
        .LM_THE_END,
        .LM_BRUTAL_EXIT,
        .LM_SAVE_COMPORTEMENT,
        .LM_RESTORE_COMPORTEMENT,
        .LM_INVERSE_BETA,
        .LM_NO_BODY,
        .LM_POPCORN,
        .LM_SAVE_HERO,
        .LM_RESTORE_HERO,
        .LM_ACTION,
        .LM_END_MESSAGE,
        .LM_NOP_132,
        .LM_DEFAULT,
        .LM_END_SWITCH,
        => {},
        .LM_COMPORTEMENT,
        .LM_FALLABLE,
        .LM_COMPORTEMENT_HERO,
        .LM_SET_MAGIC_LEVEL,
        .LM_SUB_MAGIC_POINT,
        .LM_CAM_FOLLOW,
        .LM_KILL_OBJ,
        .LM_BODY,
        .LM_SET_USED_INVENTORY,
        .LM_FOUND_OBJECT,
        .LM_CHANGE_CUBE,
        .LM_ADD_FUEL,
        .LM_SUB_FUEL,
        .LM_SET_HOLO_POS,
        .LM_CLR_HOLO_POS,
        .LM_OBJ_COL,
        .LM_INVISIBLE,
        .LM_BRICK_COL,
        .LM_POS_POINT,
        .LM_BULLE,
        .LM_PLAY_MUSIC,
        .LM_PALETTE,
        .LM_FADE_TO_PAL,
        .LM_CAMERA_CENTER,
        .LM_MEMO_ARDOISE,
        .LM_TRACK_TO_VAR_GAME,
        .LM_VAR_GAME_TO_TRACK,
        .LM_SET_FRAME,
        .LM_SET_FRAME_3DS,
        .LM_NO_CHOC,
        .LM_CINEMA_MODE,
        .LM_ANIM_TEXTURE,
        .LM_END_MESSAGE_OBJ,
        .LM_INIT_BUGGY,
        .LM_ECLAIR,
        .LM_PLUIE,
        .LM_BACKGROUND,
        .LM_GIVE_BONUS,
        .LM_STOP_L_TRACK_OBJ,
        .LM_RESTORE_L_TRACK_OBJ,
        .LM_SAVE_COMPORTEMENT_OBJ,
        .LM_RESTORE_COMPORTEMENT_OBJ,
        => try bytes.append(allocator, 7),
        .LM_SET_ARMURE => try bytes.append(allocator, @bitCast(@as(i8, -7))),
        .LM_SET_LIFE_POINT_OBJ,
        .LM_SUB_LIFE_POINT_OBJ,
        .LM_ADD_LIFE_POINT_OBJ,
        .LM_HIT_OBJ,
        .LM_BODY_OBJ,
        .LM_SET_VAR_CUBE,
        .LM_ADD_VAR_CUBE,
        .LM_SUB_VAR_CUBE,
        .LM_STATE_INVENTORY,
        .LM_ECHELLE,
        .LM_SET_HIT_ZONE,
        .LM_SET_GRM,
        .LM_SET_CHANGE_CUBE,
        .LM_FLOW_POINT,
        .LM_PCX,
        .LM_SET_CAMERA,
        .LM_SET_RAIL,
        .LM_SHADOW_OBJ,
        .LM_FLOW_OBJ,
        .LM_POS_OBJ_AROUND,
        .LM_ESCALATOR,
        => try bytes.appendSlice(allocator, &.{ 3, 9 }),
        .LM_SET_COMPORTEMENT,
        .LM_SET_TRACK,
        .LM_MESSAGE,
        .LM_ADD_MESSAGE,
        .LM_MESSAGE_ZOE,
        .LM_GIVE_GOLD_PIECES,
        .LM_ADD_GOLD_PIECES,
        .LM_SET_DOOR_LEFT,
        .LM_SET_DOOR_RIGHT,
        .LM_SET_DOOR_UP,
        .LM_SET_DOOR_DOWN,
        .LM_ADD_CHOICE,
        .LM_ASK_CHOICE,
        .LM_BETA,
        .LM_SAMPLE,
        .LM_SAMPLE_RND,
        .LM_SAMPLE_ALWAYS,
        .LM_SAMPLE_STOP,
        .LM_SET_SPRITE,
        .LM_OFFSET,
        .LM_ELSE,
        .LM_BREAK,
        => try appendInt(&bytes, allocator, @as(i16, -1234)),
        .LM_ANIM,
        .LM_ANIM_SET,
        .LM_SET_ANIM_DIAL,
        => try appendInt(&bytes, allocator, @as(u16, 513)),
        .LM_SET_ARMURE_OBJ => {
            try bytes.append(allocator, 5);
            try bytes.append(allocator, @bitCast(@as(i8, -2)));
        },
        .LM_SET_COMPORTEMENT_OBJ,
        .LM_SET_TRACK_OBJ,
        .LM_MESSAGE_OBJ,
        .LM_ADD_MESSAGE_OBJ,
        .LM_SET_VAR_GAME,
        .LM_ADD_VAR_GAME,
        .LM_SUB_VAR_GAME,
        .LM_ASK_CHOICE_OBJ,
        => {
            try bytes.append(allocator, 5);
            try appendInt(&bytes, allocator, @as(i16, -111));
        },
        .LM_REPEAT_SAMPLE => {
            try appendInt(&bytes, allocator, @as(i16, 44));
            try bytes.append(allocator, 2);
        },
        .LM_IMPACT_POINT,
        .LM_ANIM_OBJ,
        => {
            try bytes.append(allocator, 5);
            try appendInt(&bytes, allocator, @as(u16, 88));
        },
        .LM_IMPACT_OBJ => {
            try bytes.append(allocator, 5);
            try appendInt(&bytes, allocator, @as(u16, 88));
            try appendInt(&bytes, allocator, @as(i16, -30));
        },
        .LM_PCX_MESS_OBJ => {
            try bytes.appendSlice(allocator, &.{ 1, 2, 3 });
            try appendInt(&bytes, allocator, @as(i16, 77));
        },
        .LM_PARM_SAMPLE => {
            try appendInt(&bytes, allocator, @as(i16, 11));
            try bytes.append(allocator, 4);
            try appendInt(&bytes, allocator, @as(i16, 22));
        },
        .LM_NEW_SAMPLE => {
            try appendInt(&bytes, allocator, @as(i16, 11));
            try appendInt(&bytes, allocator, @as(i16, 22));
            try bytes.append(allocator, 4);
            try appendInt(&bytes, allocator, @as(i16, 33));
        },
        .LM_SET_DIR => try bytes.appendSlice(allocator, &.{ 2, 7 }),
        .LM_SET_DIR_OBJ => try bytes.appendSlice(allocator, &.{ 5, 2, 7 }),
        .LM_PLAY_ACF => try bytes.appendSlice(allocator, &.{ 'A', 'C', 'F', 0 }),
        .LM_IF,
        .LM_AND_IF,
        .LM_OR_IF,
        .LM_SWIF,
        .LM_SNIF,
        .LM_ONEIF,
        .LM_NEVERIF,
        => {
            try appendLifeFunctionSample(&bytes, allocator, .LF_VAR_CUBE);
            try appendLifeTestSample(&bytes, allocator, .LT_EQUAL, .RET_U8);
            try appendInt(&bytes, allocator, @as(i16, 123));
        },
        .LM_SWITCH => try appendLifeFunctionSample(&bytes, allocator, .LF_VAR_GAME),
        .LM_CASE,
        .LM_OR_CASE,
        => unreachable,
        .LM_NOP,
        .LM_ENDIF,
        .LM_REM,
        .LM_SPY,
        .LM_DEBUG,
        .LM_DEBUG_OBJ,
        => unreachable,
    }

    return bytes.toOwnedSlice(allocator);
}

pub fn expectedLifeInstructionByteLengthIndependent(opcode: life_program.LifeOpcode) usize {
    return switch (opcode) {
        .LM_END,
        .LM_RETURN,
        .LM_END_COMPORTEMENT,
        .LM_SUICIDE,
        .LM_END_LIFE,
        .LM_STOP_L_TRACK,
        .LM_RESTORE_L_TRACK,
        .LM_INC_CHAPTER,
        .LM_USE_ONE_LITTLE_KEY,
        .LM_INC_CLOVER_BOX,
        .LM_FULL_POINT,
        .LM_GAME_OVER,
        .LM_THE_END,
        .LM_BRUTAL_EXIT,
        .LM_SAVE_COMPORTEMENT,
        .LM_RESTORE_COMPORTEMENT,
        .LM_INVERSE_BETA,
        .LM_NO_BODY,
        .LM_POPCORN,
        .LM_SAVE_HERO,
        .LM_RESTORE_HERO,
        .LM_ACTION,
        .LM_END_MESSAGE,
        .LM_NOP_132,
        .LM_DEFAULT,
        .LM_END_SWITCH,
        => 1,

        .LM_COMPORTEMENT,
        .LM_FALLABLE,
        .LM_COMPORTEMENT_HERO,
        .LM_SET_MAGIC_LEVEL,
        .LM_SUB_MAGIC_POINT,
        .LM_CAM_FOLLOW,
        .LM_KILL_OBJ,
        .LM_BODY,
        .LM_SET_USED_INVENTORY,
        .LM_FOUND_OBJECT,
        .LM_CHANGE_CUBE,
        .LM_ADD_FUEL,
        .LM_SUB_FUEL,
        .LM_SET_HOLO_POS,
        .LM_CLR_HOLO_POS,
        .LM_OBJ_COL,
        .LM_INVISIBLE,
        .LM_BRICK_COL,
        .LM_POS_POINT,
        .LM_BULLE,
        .LM_PLAY_MUSIC,
        .LM_PALETTE,
        .LM_FADE_TO_PAL,
        .LM_CAMERA_CENTER,
        .LM_MEMO_ARDOISE,
        .LM_TRACK_TO_VAR_GAME,
        .LM_VAR_GAME_TO_TRACK,
        .LM_SET_FRAME,
        .LM_SET_FRAME_3DS,
        .LM_NO_CHOC,
        .LM_CINEMA_MODE,
        .LM_ANIM_TEXTURE,
        .LM_END_MESSAGE_OBJ,
        .LM_INIT_BUGGY,
        .LM_ECLAIR,
        .LM_PLUIE,
        .LM_BACKGROUND,
        .LM_GIVE_BONUS,
        .LM_STOP_L_TRACK_OBJ,
        .LM_RESTORE_L_TRACK_OBJ,
        .LM_SAVE_COMPORTEMENT_OBJ,
        .LM_RESTORE_COMPORTEMENT_OBJ,
        => 2,

        .LM_SET_ARMURE => 2,

        .LM_SET_LIFE_POINT_OBJ,
        .LM_SUB_LIFE_POINT_OBJ,
        .LM_ADD_LIFE_POINT_OBJ,
        .LM_HIT_OBJ,
        .LM_BODY_OBJ,
        .LM_SET_VAR_CUBE,
        .LM_ADD_VAR_CUBE,
        .LM_SUB_VAR_CUBE,
        .LM_STATE_INVENTORY,
        .LM_ECHELLE,
        .LM_SET_HIT_ZONE,
        .LM_SET_GRM,
        .LM_SET_CHANGE_CUBE,
        .LM_FLOW_POINT,
        .LM_PCX,
        .LM_SET_CAMERA,
        .LM_SET_RAIL,
        .LM_SHADOW_OBJ,
        .LM_FLOW_OBJ,
        .LM_POS_OBJ_AROUND,
        .LM_ESCALATOR,
        .LM_SET_COMPORTEMENT,
        .LM_SET_TRACK,
        .LM_MESSAGE,
        .LM_ADD_MESSAGE,
        .LM_MESSAGE_ZOE,
        .LM_GIVE_GOLD_PIECES,
        .LM_ADD_GOLD_PIECES,
        .LM_SET_DOOR_LEFT,
        .LM_SET_DOOR_RIGHT,
        .LM_SET_DOOR_UP,
        .LM_SET_DOOR_DOWN,
        .LM_ADD_CHOICE,
        .LM_ASK_CHOICE,
        .LM_BETA,
        .LM_SAMPLE,
        .LM_SAMPLE_RND,
        .LM_SAMPLE_ALWAYS,
        .LM_SAMPLE_STOP,
        .LM_SET_SPRITE,
        .LM_OFFSET,
        .LM_ELSE,
        .LM_BREAK,
        .LM_ANIM,
        .LM_ANIM_SET,
        .LM_SET_ANIM_DIAL,
        .LM_SET_ARMURE_OBJ,
        => 3,

        .LM_SET_COMPORTEMENT_OBJ,
        .LM_SET_TRACK_OBJ,
        .LM_MESSAGE_OBJ,
        .LM_ADD_MESSAGE_OBJ,
        .LM_SET_VAR_GAME,
        .LM_ADD_VAR_GAME,
        .LM_SUB_VAR_GAME,
        .LM_ASK_CHOICE_OBJ,
        .LM_REPEAT_SAMPLE,
        .LM_IMPACT_POINT,
        .LM_ANIM_OBJ,
        => 4,

        .LM_SWITCH => 3,

        .LM_IMPACT_OBJ,
        .LM_PCX_MESS_OBJ,
        => 6,

        .LM_PARM_SAMPLE => 6,
        .LM_NEW_SAMPLE => 8,
        .LM_SET_DIR => 3,
        .LM_SET_DIR_OBJ => 4,
        .LM_PLAY_ACF => 5,

        .LM_IF,
        .LM_AND_IF,
        .LM_OR_IF,
        .LM_SWIF,
        .LM_SNIF,
        .LM_ONEIF,
        .LM_NEVERIF,
        => 7,

        .LM_CASE,
        .LM_OR_CASE,
        => 6,

        .LM_NOP,
        .LM_ENDIF,
        .LM_REM,
        .LM_SPY,
        .LM_DEBUG,
        .LM_DEBUG_OBJ,
        => unreachable,
    };
}

pub fn isLifeOpcodeSupportedIndependent(opcode: life_program.LifeOpcode) bool {
    return switch (opcode) {
        .LM_NOP,
        .LM_ENDIF,
        .LM_REM,
        .LM_SPY,
        .LM_DEBUG,
        .LM_DEBUG_OBJ,
        => false,
        else => true,
    };
}

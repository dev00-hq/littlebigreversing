const std = @import("std");

pub const LifeOperandLayout = enum {
    none,
    u8,
    i8,
    u16,
    i16,
    u8_pair,
    u8_i8,
    u8_i16,
    i16_u8,
    u8_u16,
    u8_u16_i16,
    u8_u8_u8_i16,
    i16_u8_i16,
    i16_i16_u8_i16,
    move,
    move_obj,
    string,
    condition,
    switch_expr,
    case_branch,
    unsupported,
};

pub const LifeOpcode = enum(u8) {
    LM_END = 0,
    LM_NOP = 1,
    LM_SNIF = 2,
    LM_OFFSET = 3,
    LM_NEVERIF = 4,
    LM_PALETTE = 10,
    LM_RETURN = 11,
    LM_IF = 12,
    LM_SWIF = 13,
    LM_ONEIF = 14,
    LM_ELSE = 15,
    LM_ENDIF = 16,
    LM_BODY = 17,
    LM_BODY_OBJ = 18,
    LM_ANIM = 19,
    LM_ANIM_OBJ = 20,
    LM_SET_CAMERA = 21,
    LM_CAMERA_CENTER = 22,
    LM_SET_TRACK = 23,
    LM_SET_TRACK_OBJ = 24,
    LM_MESSAGE = 25,
    LM_FALLABLE = 26,
    LM_SET_DIR = 27,
    LM_SET_DIR_OBJ = 28,
    LM_CAM_FOLLOW = 29,
    LM_COMPORTEMENT_HERO = 30,
    LM_SET_VAR_CUBE = 31,
    LM_COMPORTEMENT = 32,
    LM_SET_COMPORTEMENT = 33,
    LM_SET_COMPORTEMENT_OBJ = 34,
    LM_END_COMPORTEMENT = 35,
    LM_SET_VAR_GAME = 36,
    LM_KILL_OBJ = 37,
    LM_SUICIDE = 38,
    LM_USE_ONE_LITTLE_KEY = 39,
    LM_GIVE_GOLD_PIECES = 40,
    LM_END_LIFE = 41,
    LM_STOP_L_TRACK = 42,
    LM_RESTORE_L_TRACK = 43,
    LM_MESSAGE_OBJ = 44,
    LM_INC_CHAPTER = 45,
    LM_FOUND_OBJECT = 46,
    LM_SET_DOOR_LEFT = 47,
    LM_SET_DOOR_RIGHT = 48,
    LM_SET_DOOR_UP = 49,
    LM_SET_DOOR_DOWN = 50,
    LM_GIVE_BONUS = 51,
    LM_CHANGE_CUBE = 52,
    LM_OBJ_COL = 53,
    LM_BRICK_COL = 54,
    LM_OR_IF = 55,
    LM_INVISIBLE = 56,
    LM_SHADOW_OBJ = 57,
    LM_POS_POINT = 58,
    LM_SET_MAGIC_LEVEL = 59,
    LM_SUB_MAGIC_POINT = 60,
    LM_SET_LIFE_POINT_OBJ = 61,
    LM_SUB_LIFE_POINT_OBJ = 62,
    LM_HIT_OBJ = 63,
    LM_PLAY_ACF = 64,
    LM_ECLAIR = 65,
    LM_INC_CLOVER_BOX = 66,
    LM_SET_USED_INVENTORY = 67,
    LM_ADD_CHOICE = 68,
    LM_ASK_CHOICE = 69,
    LM_INIT_BUGGY = 70,
    LM_MEMO_ARDOISE = 71,
    LM_SET_HOLO_POS = 72,
    LM_CLR_HOLO_POS = 73,
    LM_ADD_FUEL = 74,
    LM_SUB_FUEL = 75,
    LM_SET_GRM = 76,
    LM_SET_CHANGE_CUBE = 77,
    LM_MESSAGE_ZOE = 78,
    LM_FULL_POINT = 79,
    LM_BETA = 80,
    LM_FADE_TO_PAL = 81,
    LM_ACTION = 82,
    LM_SET_FRAME = 83,
    LM_SET_SPRITE = 84,
    LM_SET_FRAME_3DS = 85,
    LM_IMPACT_OBJ = 86,
    LM_IMPACT_POINT = 87,
    LM_ADD_MESSAGE = 88,
    LM_BULLE = 89,
    LM_NO_CHOC = 90,
    LM_ASK_CHOICE_OBJ = 91,
    LM_CINEMA_MODE = 92,
    LM_SAVE_HERO = 93,
    LM_RESTORE_HERO = 94,
    LM_ANIM_SET = 95,
    LM_PLUIE = 96,
    LM_GAME_OVER = 97,
    LM_THE_END = 98,
    LM_ESCALATOR = 99,
    LM_PLAY_MUSIC = 100,
    LM_TRACK_TO_VAR_GAME = 101,
    LM_VAR_GAME_TO_TRACK = 102,
    LM_ANIM_TEXTURE = 103,
    LM_ADD_MESSAGE_OBJ = 104,
    LM_BRUTAL_EXIT = 105,
    LM_REM = 106,
    LM_ECHELLE = 107,
    LM_SET_ARMURE = 108,
    LM_SET_ARMURE_OBJ = 109,
    LM_ADD_LIFE_POINT_OBJ = 110,
    LM_STATE_INVENTORY = 111,
    LM_AND_IF = 112,
    LM_SWITCH = 113,
    LM_OR_CASE = 114,
    LM_CASE = 115,
    LM_DEFAULT = 116,
    LM_BREAK = 117,
    LM_END_SWITCH = 118,
    LM_SET_HIT_ZONE = 119,
    LM_SAVE_COMPORTEMENT = 120,
    LM_RESTORE_COMPORTEMENT = 121,
    LM_SAMPLE = 122,
    LM_SAMPLE_RND = 123,
    LM_SAMPLE_ALWAYS = 124,
    LM_SAMPLE_STOP = 125,
    LM_REPEAT_SAMPLE = 126,
    LM_BACKGROUND = 127,
    LM_ADD_VAR_GAME = 128,
    LM_SUB_VAR_GAME = 129,
    LM_ADD_VAR_CUBE = 130,
    LM_SUB_VAR_CUBE = 131,
    LM_SET_RAIL = 133,
    LM_INVERSE_BETA = 134,
    LM_NO_BODY = 135,
    LM_ADD_GOLD_PIECES = 136,
    LM_STOP_L_TRACK_OBJ = 137,
    LM_RESTORE_L_TRACK_OBJ = 138,
    LM_SAVE_COMPORTEMENT_OBJ = 139,
    LM_RESTORE_COMPORTEMENT_OBJ = 140,
    LM_SPY = 141,
    LM_DEBUG = 142,
    LM_DEBUG_OBJ = 143,
    LM_POPCORN = 144,
    LM_FLOW_POINT = 145,
    LM_FLOW_OBJ = 146,
    LM_SET_ANIM_DIAL = 147,
    LM_PCX = 148,
    LM_END_MESSAGE = 149,
    LM_END_MESSAGE_OBJ = 150,
    LM_PARM_SAMPLE = 151,
    LM_NEW_SAMPLE = 152,
    LM_POS_OBJ_AROUND = 153,
    LM_PCX_MESS_OBJ = 154,

    pub fn mnemonic(self: LifeOpcode) []const u8 {
        return @tagName(self);
    }

    pub fn isSupported(self: LifeOpcode) bool {
        return self.operandLayout() != .unsupported;
    }

    pub fn operandLayout(self: LifeOpcode) LifeOperandLayout {
        return switch (self) {
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
            .LM_DEFAULT,
            .LM_END_SWITCH,
            => .none,

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
            => .u8,

            .LM_SET_ARMURE => .i8,

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
            => .u8_pair,

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
            => .i16,

            .LM_ANIM,
            .LM_ANIM_SET,
            .LM_SET_ANIM_DIAL,
            => .u16,

            .LM_SET_COMPORTEMENT_OBJ,
            .LM_SET_TRACK_OBJ,
            .LM_MESSAGE_OBJ,
            .LM_ADD_MESSAGE_OBJ,
            .LM_SET_VAR_GAME,
            .LM_ADD_VAR_GAME,
            .LM_SUB_VAR_GAME,
            .LM_ASK_CHOICE_OBJ,
            => .u8_i16,

            .LM_SET_ARMURE_OBJ => .u8_i8,
            .LM_REPEAT_SAMPLE => .i16_u8,
            .LM_IMPACT_POINT,
            .LM_ANIM_OBJ,
            => .u8_u16,
            .LM_IMPACT_OBJ => .u8_u16_i16,
            .LM_PCX_MESS_OBJ => .u8_u8_u8_i16,
            .LM_PARM_SAMPLE => .i16_u8_i16,
            .LM_NEW_SAMPLE => .i16_i16_u8_i16,
            .LM_SET_DIR => .move,
            .LM_SET_DIR_OBJ => .move_obj,
            .LM_PLAY_ACF => .string,

            .LM_IF,
            .LM_AND_IF,
            .LM_OR_IF,
            .LM_SWIF,
            .LM_SNIF,
            .LM_ONEIF,
            .LM_NEVERIF,
            => .condition,

            .LM_SWITCH => .switch_expr,
            .LM_CASE,
            .LM_OR_CASE,
            => .case_branch,

            .LM_NOP,
            .LM_ENDIF,
            .LM_REM,
            .LM_SPY,
            .LM_DEBUG,
            .LM_DEBUG_OBJ,
            => .unsupported,
        };
    }
};

pub const LifeReturnType = enum(u8) {
    RET_S8 = 0,
    RET_S16 = 1,
    RET_STRING = 2,
    RET_U8 = 4,
};

pub const LifeFunctionOperandLayout = enum {
    none,
    u8,
};

pub const LifeFunction = enum(u8) {
    LF_COL = 0,
    LF_COL_OBJ = 1,
    LF_DISTANCE = 2,
    LF_ZONE = 3,
    LF_ZONE_OBJ = 4,
    LF_BODY = 5,
    LF_BODY_OBJ = 6,
    LF_ANIM = 7,
    LF_ANIM_OBJ = 8,
    LF_L_TRACK = 9,
    LF_L_TRACK_OBJ = 10,
    LF_VAR_CUBE = 11,
    LF_CONE_VIEW = 12,
    LF_HIT_BY = 13,
    LF_ACTION = 14,
    LF_VAR_GAME = 15,
    LF_LIFE_POINT = 16,
    LF_LIFE_POINT_OBJ = 17,
    LF_NB_LITTLE_KEYS = 18,
    LF_NB_GOLD_PIECES = 19,
    LF_COMPORTEMENT_HERO = 20,
    LF_CHAPTER = 21,
    LF_DISTANCE_3D = 22,
    LF_MAGIC_LEVEL = 23,
    LF_MAGIC_POINT = 24,
    LF_USE_INVENTORY = 25,
    LF_CHOICE = 26,
    LF_FUEL = 27,
    LF_CARRY_BY = 28,
    LF_CDROM = 29,
    LF_ECHELLE = 30,
    LF_RND = 31,
    LF_RAIL = 32,
    LF_BETA = 33,
    LF_BETA_OBJ = 34,
    LF_CARRY_OBJ_BY = 35,
    LF_ANGLE = 36,
    LF_DISTANCE_MESSAGE = 37,
    LF_HIT_OBJ_BY = 38,
    LF_REAL_ANGLE = 39,
    LF_DEMO = 40,
    LF_COL_DECORS = 41,
    LF_COL_DECORS_OBJ = 42,
    LF_PROCESSOR = 43,
    LF_OBJECT_DISPLAYED = 44,
    LF_ANGLE_OBJ = 45,

    pub fn mnemonic(self: LifeFunction) []const u8 {
        return @tagName(self);
    }

    pub fn operandLayout(self: LifeFunction) LifeFunctionOperandLayout {
        return switch (self) {
            .LF_HIT_OBJ_BY,
            .LF_LIFE_POINT_OBJ,
            .LF_COL_OBJ,
            .LF_DISTANCE,
            .LF_DISTANCE_3D,
            .LF_CONE_VIEW,
            .LF_ZONE_OBJ,
            .LF_VAR_CUBE,
            .LF_VAR_GAME,
            .LF_USE_INVENTORY,
            .LF_L_TRACK_OBJ,
            .LF_BODY_OBJ,
            .LF_ANIM_OBJ,
            .LF_CARRY_OBJ_BY,
            .LF_ECHELLE,
            .LF_RND,
            .LF_RAIL,
            .LF_BETA_OBJ,
            .LF_ANGLE,
            .LF_ANGLE_OBJ,
            .LF_REAL_ANGLE,
            .LF_DISTANCE_MESSAGE,
            .LF_COL_DECORS_OBJ,
            .LF_OBJECT_DISPLAYED,
            => .u8,

            else => .none,
        };
    }

    pub fn returnType(self: LifeFunction) LifeReturnType {
        return switch (self) {
            .LF_LIFE_POINT,
            .LF_NB_GOLD_PIECES,
            .LF_CHOICE,
            .LF_FUEL,
            .LF_ANIM,
            .LF_DISTANCE,
            .LF_DISTANCE_3D,
            .LF_CONE_VIEW,
            .LF_VAR_GAME,
            .LF_LIFE_POINT_OBJ,
            .LF_ANIM_OBJ,
            .LF_BETA,
            .LF_BETA_OBJ,
            .LF_ANGLE,
            .LF_ANGLE_OBJ,
            .LF_REAL_ANGLE,
            .LF_DISTANCE_MESSAGE,
            => .RET_S16,

            .LF_L_TRACK,
            .LF_L_TRACK_OBJ,
            .LF_VAR_CUBE,
            .LF_RND,
            .LF_COL_DECORS,
            => .RET_U8,

            else => .RET_S8,
        };
    }
};

pub const LifeComparator = enum(u8) {
    LT_EQUAL = 0,
    LT_SUP = 1,
    LT_LESS = 2,
    LT_SUP_EQUAL = 3,
    LT_LESS_EQUAL = 4,
    LT_DIFFERENT = 5,

    pub fn mnemonic(self: LifeComparator) []const u8 {
        return @tagName(self);
    }
};

pub const LifeFunctionOperands = union(enum) {
    none: void,
    u8_value: u8,
};

pub const LifeFunctionCall = struct {
    offset: usize,
    function: LifeFunction,
    byte_length: usize,
    return_type: LifeReturnType,
    operands: LifeFunctionOperands,

    pub fn endOffset(self: LifeFunctionCall) usize {
        return self.offset + self.byte_length;
    }
};

pub const LifeTestLiteral = union(enum) {
    s8_value: i8,
    u8_value: u8,
    s16_value: i16,
    string: []const u8,
};

pub const LifeTest = struct {
    offset: usize,
    comparator: LifeComparator,
    byte_length: usize,
    return_type: LifeReturnType,
    literal: LifeTestLiteral,

    pub fn endOffset(self: LifeTest) usize {
        return self.offset + self.byte_length;
    }
};

pub const LifeMoveOperand = struct {
    move_id: u8,
    point_index: ?u8,
};

pub const LifeMoveObjectOperand = struct {
    object_index: u8,
    move_id: u8,
    point_index: ?u8,
};

pub const LifeCondition = struct {
    function: LifeFunctionCall,
    comparison: LifeTest,
    jump_offset: i16,
};

pub const LifeSwitchExpression = struct {
    function: LifeFunctionCall,
};

pub const LifeCaseBranch = struct {
    jump_offset: i16,
    comparison: LifeTest,
    switch_return_type: LifeReturnType,
};

pub const LifeOperands = union(enum) {
    none: void,
    u8_value: u8,
    i8_value: i8,
    u16_value: u16,
    i16_value: i16,
    u8_pair: struct {
        first: u8,
        second: u8,
    },
    u8_i8: struct {
        byte_value: u8,
        signed_value: i8,
    },
    u8_i16: struct {
        byte_value: u8,
        word_value: i16,
    },
    i16_u8: struct {
        word_value: i16,
        byte_value: u8,
    },
    u8_u16: struct {
        byte_value: u8,
        word_value: u16,
    },
    u8_u16_i16: struct {
        first_u8: u8,
        word_u16: u16,
        word_i16: i16,
    },
    u8_u8_u8_i16: struct {
        first_u8: u8,
        second_u8: u8,
        third_u8: u8,
        word_i16: i16,
    },
    i16_u8_i16: struct {
        first_i16: i16,
        middle_u8: u8,
        last_i16: i16,
    },
    i16_i16_u8_i16: struct {
        first_i16: i16,
        second_i16: i16,
        middle_u8: u8,
        last_i16: i16,
    },
    move: LifeMoveOperand,
    move_obj: LifeMoveObjectOperand,
    string: []const u8,
    condition: LifeCondition,
    switch_expr: LifeSwitchExpression,
    case_branch: LifeCaseBranch,
};

pub const LifeInstruction = struct {
    offset: usize,
    opcode: LifeOpcode,
    byte_length: usize,
    operands: LifeOperands,

    pub fn endOffset(self: LifeInstruction) usize {
        return self.offset + self.byte_length;
    }
};

pub const UnsupportedLifeOpcodeHit = struct {
    offset: usize,
    opcode_id: u8,
    opcode: LifeOpcode,
};

pub const UnknownLifeOpcodeHit = struct {
    offset: usize,
    opcode_id: u8,
};

pub const LifeProgramAuditStatus = union(enum) {
    decoded: void,
    unsupported_opcode: UnsupportedLifeOpcodeHit,
    unknown_opcode: UnknownLifeOpcodeHit,
    truncated_operand: void,
    malformed_string_operand: void,
    missing_switch_context: void,
    unknown_life_function: void,
    unknown_life_comparator: void,
};

pub const LifeProgramAudit = struct {
    instruction_count: usize,
    decoded_byte_length: usize,
    status: LifeProgramAuditStatus,
};

pub fn decodeLifeProgram(allocator: std.mem.Allocator, bytes: []const u8) ![]LifeInstruction {
    var instructions: std.ArrayList(LifeInstruction) = .empty;
    errdefer instructions.deinit(allocator);

    var active_switch_return_type: ?LifeReturnType = null;
    var offset: usize = 0;
    while (offset < bytes.len) {
        const decoded = try decodeInstruction(bytes, offset, active_switch_return_type);
        try instructions.append(allocator, decoded.instruction);
        active_switch_return_type = decoded.active_switch_return_type;
        offset += decoded.instruction.byte_length;
    }

    return instructions.toOwnedSlice(allocator);
}

pub fn auditLifeProgram(bytes: []const u8) LifeProgramAudit {
    var active_switch_return_type: ?LifeReturnType = null;
    var offset: usize = 0;
    var instruction_count: usize = 0;

    while (offset < bytes.len) {
        const opcode_id = readScalar(bytes, offset) catch return .{
            .instruction_count = instruction_count,
            .decoded_byte_length = offset,
            .status = .truncated_operand,
        };
        const opcode = std.meta.intToEnum(LifeOpcode, opcode_id) catch return .{
            .instruction_count = instruction_count,
            .decoded_byte_length = offset,
            .status = .{ .unknown_opcode = .{
                .offset = offset,
                .opcode_id = opcode_id,
            } },
        };

        if (!opcode.isSupported()) {
            return .{
                .instruction_count = instruction_count,
                .decoded_byte_length = offset,
                .status = .{ .unsupported_opcode = .{
                    .offset = offset,
                    .opcode_id = opcode_id,
                    .opcode = opcode,
                } },
            };
        }

        const decoded = decodeInstruction(bytes, offset, active_switch_return_type) catch |err| return .{
            .instruction_count = instruction_count,
            .decoded_byte_length = offset,
            .status = switch (err) {
                error.TruncatedLifeOperand => .truncated_operand,
                error.MalformedLifeStringOperand => .malformed_string_operand,
                error.MissingLifeSwitchContext => .missing_switch_context,
                error.UnknownLifeFunction => .unknown_life_function,
                error.UnknownLifeComparator => .unknown_life_comparator,
                else => unreachable,
            },
        };

        active_switch_return_type = decoded.active_switch_return_type;
        offset += decoded.instruction.byte_length;
        instruction_count += 1;
    }

    return .{
        .instruction_count = instruction_count,
        .decoded_byte_length = offset,
        .status = .decoded,
    };
}

const DecodedInstruction = struct {
    instruction: LifeInstruction,
    active_switch_return_type: ?LifeReturnType,
};

fn decodeInstruction(bytes: []const u8, offset: usize, active_switch_return_type: ?LifeReturnType) !DecodedInstruction {
    const opcode_id = try readScalar(bytes, offset);
    const opcode = std.meta.intToEnum(LifeOpcode, opcode_id) catch return error.UnknownLifeOpcode;

    return switch (opcode.operandLayout()) {
        .none => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 1,
                .operands = .{ .none = {} },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .u8 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 2,
                .operands = .{ .u8_value = try readScalar(bytes, offset + 1) },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .i8 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 2,
                .operands = .{ .i8_value = try readInt(bytes, offset + 1, i8) },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .u16 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 3,
                .operands = .{ .u16_value = try readInt(bytes, offset + 1, u16) },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .i16 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 3,
                .operands = .{ .i16_value = try readInt(bytes, offset + 1, i16) },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .u8_pair => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 3,
                .operands = .{ .u8_pair = .{
                    .first = try readScalar(bytes, offset + 1),
                    .second = try readScalar(bytes, offset + 2),
                } },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .u8_i8 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 3,
                .operands = .{ .u8_i8 = .{
                    .byte_value = try readScalar(bytes, offset + 1),
                    .signed_value = try readInt(bytes, offset + 2, i8),
                } },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .u8_i16 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 4,
                .operands = .{ .u8_i16 = .{
                    .byte_value = try readScalar(bytes, offset + 1),
                    .word_value = try readInt(bytes, offset + 2, i16),
                } },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .i16_u8 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 4,
                .operands = .{ .i16_u8 = .{
                    .word_value = try readInt(bytes, offset + 1, i16),
                    .byte_value = try readScalar(bytes, offset + 3),
                } },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .u8_u16 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 4,
                .operands = .{ .u8_u16 = .{
                    .byte_value = try readScalar(bytes, offset + 1),
                    .word_value = try readInt(bytes, offset + 2, u16),
                } },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .u8_u16_i16 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 6,
                .operands = .{ .u8_u16_i16 = .{
                    .first_u8 = try readScalar(bytes, offset + 1),
                    .word_u16 = try readInt(bytes, offset + 2, u16),
                    .word_i16 = try readInt(bytes, offset + 4, i16),
                } },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .u8_u8_u8_i16 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 6,
                .operands = .{ .u8_u8_u8_i16 = .{
                    .first_u8 = try readScalar(bytes, offset + 1),
                    .second_u8 = try readScalar(bytes, offset + 2),
                    .third_u8 = try readScalar(bytes, offset + 3),
                    .word_i16 = try readInt(bytes, offset + 4, i16),
                } },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .i16_u8_i16 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 6,
                .operands = .{ .i16_u8_i16 = .{
                    .first_i16 = try readInt(bytes, offset + 1, i16),
                    .middle_u8 = try readScalar(bytes, offset + 3),
                    .last_i16 = try readInt(bytes, offset + 4, i16),
                } },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .i16_i16_u8_i16 => .{
            .instruction = .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 8,
                .operands = .{ .i16_i16_u8_i16 = .{
                    .first_i16 = try readInt(bytes, offset + 1, i16),
                    .second_i16 = try readInt(bytes, offset + 3, i16),
                    .middle_u8 = try readScalar(bytes, offset + 5),
                    .last_i16 = try readInt(bytes, offset + 6, i16),
                } },
            },
            .active_switch_return_type = active_switch_return_type,
        },
        .move => blk: {
            const move_id = try readScalar(bytes, offset + 1);
            const point_index = if (moveUsesPointIndex(move_id)) try readScalar(bytes, offset + 2) else null;
            break :blk .{
                .instruction = .{
                    .offset = offset,
                    .opcode = opcode,
                    .byte_length = 2 + @as(usize, @intFromBool(point_index != null)),
                    .operands = .{ .move = .{
                        .move_id = move_id,
                        .point_index = point_index,
                    } },
                },
                .active_switch_return_type = active_switch_return_type,
            };
        },
        .move_obj => blk: {
            const object_index = try readScalar(bytes, offset + 1);
            const move_id = try readScalar(bytes, offset + 2);
            const point_index = if (moveUsesPointIndex(move_id)) try readScalar(bytes, offset + 3) else null;
            break :blk .{
                .instruction = .{
                    .offset = offset,
                    .opcode = opcode,
                    .byte_length = 3 + @as(usize, @intFromBool(point_index != null)),
                    .operands = .{ .move_obj = .{
                        .object_index = object_index,
                        .move_id = move_id,
                        .point_index = point_index,
                    } },
                },
                .active_switch_return_type = active_switch_return_type,
            };
        },
        .string => blk: {
            const end = findStringTerminator(bytes, offset + 1) orelse return error.MalformedLifeStringOperand;
            break :blk .{
                .instruction = .{
                    .offset = offset,
                    .opcode = opcode,
                    .byte_length = end - offset + 1,
                    .operands = .{ .string = bytes[(offset + 1)..end] },
                },
                .active_switch_return_type = active_switch_return_type,
            };
        },
        .condition => blk: {
            const function = try decodeFunction(bytes, offset + 1);
            const comparison = try decodeTest(bytes, function.endOffset(), function.return_type);
            const jump_offset = try readInt(bytes, comparison.endOffset(), i16);
            break :blk .{
                .instruction = .{
                    .offset = offset,
                    .opcode = opcode,
                    .byte_length = 1 + function.byte_length + comparison.byte_length + 2,
                    .operands = .{ .condition = .{
                        .function = function,
                        .comparison = comparison,
                        .jump_offset = jump_offset,
                    } },
                },
                .active_switch_return_type = active_switch_return_type,
            };
        },
        .switch_expr => blk: {
            const function = try decodeFunction(bytes, offset + 1);
            break :blk .{
                .instruction = .{
                    .offset = offset,
                    .opcode = opcode,
                    .byte_length = 1 + function.byte_length,
                    .operands = .{ .switch_expr = .{
                        .function = function,
                    } },
                },
                .active_switch_return_type = function.return_type,
            };
        },
        .case_branch => blk: {
            const switch_return_type = active_switch_return_type orelse return error.MissingLifeSwitchContext;
            const jump_offset = try readInt(bytes, offset + 1, i16);
            const comparison = try decodeTest(bytes, offset + 3, switch_return_type);
            break :blk .{
                .instruction = .{
                    .offset = offset,
                    .opcode = opcode,
                    .byte_length = 3 + comparison.byte_length,
                    .operands = .{ .case_branch = .{
                        .jump_offset = jump_offset,
                        .comparison = comparison,
                        .switch_return_type = switch_return_type,
                    } },
                },
                .active_switch_return_type = active_switch_return_type,
            };
        },
        .unsupported => error.UnsupportedLifeOpcode,
    };
}

fn decodeFunction(bytes: []const u8, offset: usize) !LifeFunctionCall {
    const function_id = try readScalar(bytes, offset);
    const function = std.meta.intToEnum(LifeFunction, function_id) catch return error.UnknownLifeFunction;

    return switch (function.operandLayout()) {
        .none => .{
            .offset = offset,
            .function = function,
            .byte_length = 1,
            .return_type = function.returnType(),
            .operands = .{ .none = {} },
        },
        .u8 => .{
            .offset = offset,
            .function = function,
            .byte_length = 2,
            .return_type = function.returnType(),
            .operands = .{ .u8_value = try readScalar(bytes, offset + 1) },
        },
    };
}

fn decodeTest(bytes: []const u8, offset: usize, return_type: LifeReturnType) !LifeTest {
    const comparator_id = try readScalar(bytes, offset);
    const comparator = std.meta.intToEnum(LifeComparator, comparator_id) catch return error.UnknownLifeComparator;

    return switch (return_type) {
        .RET_S8 => .{
            .offset = offset,
            .comparator = comparator,
            .byte_length = 2,
            .return_type = return_type,
            .literal = .{ .s8_value = try readInt(bytes, offset + 1, i8) },
        },
        .RET_U8 => .{
            .offset = offset,
            .comparator = comparator,
            .byte_length = 2,
            .return_type = return_type,
            .literal = .{ .u8_value = try readScalar(bytes, offset + 1) },
        },
        .RET_S16 => .{
            .offset = offset,
            .comparator = comparator,
            .byte_length = 3,
            .return_type = return_type,
            .literal = .{ .s16_value = try readInt(bytes, offset + 1, i16) },
        },
        .RET_STRING => blk: {
            const end = findStringTerminator(bytes, offset + 1) orelse return error.MalformedLifeStringOperand;
            break :blk .{
                .offset = offset,
                .comparator = comparator,
                .byte_length = end - offset + 1,
                .return_type = return_type,
                .literal = .{ .string = bytes[(offset + 1)..end] },
            };
        },
    };
}

fn moveUsesPointIndex(move_id: u8) bool {
    return switch (move_id) {
        2, 6, 9, 10, 11 => true,
        else => false,
    };
}

fn readScalar(bytes: []const u8, offset: usize) !u8 {
    if (offset >= bytes.len) return error.TruncatedLifeOperand;
    return bytes[offset];
}

fn readInt(bytes: []const u8, offset: usize, comptime T: type) !T {
    const size = @sizeOf(T);
    if (offset + size > bytes.len) return error.TruncatedLifeOperand;
    return std.mem.readInt(T, bytes[offset .. offset + size][0..size], .little);
}

fn findStringTerminator(bytes: []const u8, offset: usize) ?usize {
    var cursor = offset;
    while (cursor < bytes.len) : (cursor += 1) {
        if (bytes[cursor] == 0) return cursor;
    }
    return null;
}

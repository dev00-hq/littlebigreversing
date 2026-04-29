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

pub const LifeSemanticOperandKind = enum {
    move_mode,
    hero_behaviour,
    can_fall,
    zone_toggle,
    brick_collision,
    binary_toggle,
    buggy_init,
    pcx_message_effect,
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
    LM_NOP_132 = 132,
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
            .LM_NOP_132,
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

    pub fn fixedInstructionByteLength(self: LifeOpcode) ?usize {
        return switch (self.operandLayout()) {
            .none => 1,
            .u8, .i8 => 2,
            .u16, .i16, .u8_pair, .u8_i8 => 3,
            .u8_i16, .i16_u8, .u8_u16 => 4,
            .u8_u16_i16, .i16_u8_i16, .u8_u8_u8_i16 => 6,
            .i16_i16_u8_i16 => 8,
            .move,
            .move_obj,
            .string,
            .condition,
            .switch_expr,
            .case_branch,
            .unsupported,
            => null,
        };
    }

    pub fn variableLengthReason(self: LifeOpcode) ?LifeVariableLengthReason {
        return switch (self.operandLayout()) {
            .move, .move_obj => .move_mode,
            .string => .null_terminated_string,
            .condition, .switch_expr => .embedded_function_layout,
            .case_branch => .switch_return_type,
            .unsupported => .unsupported,
            else => null,
        };
    }

    pub fn semanticOperandKind(self: LifeOpcode) ?LifeSemanticOperandKind {
        return switch (self) {
            .LM_SET_DIR,
            .LM_SET_DIR_OBJ,
            => .move_mode,

            .LM_COMPORTEMENT_HERO => .hero_behaviour,
            .LM_FALLABLE => .can_fall,

            .LM_SET_CAMERA,
            .LM_SET_GRM,
            .LM_SET_CHANGE_CUBE,
            .LM_ECHELLE,
            .LM_ESCALATOR,
            .LM_SET_HIT_ZONE,
            .LM_SET_RAIL,
            => .zone_toggle,

            .LM_BRICK_COL => .brick_collision,

            .LM_BULLE,
            .LM_NO_CHOC,
            .LM_CINEMA_MODE,
            .LM_BACKGROUND,
            => .binary_toggle,

            .LM_INIT_BUGGY => .buggy_init,
            .LM_PCX_MESS_OBJ => .pcx_message_effect,
            else => null,
        };
    }
};

pub const LifeReturnType = enum(u8) {
    RET_S8 = 0,
    RET_S16 = 1,
    RET_STRING = 2,
    RET_U8 = 4,

    pub fn mnemonic(self: LifeReturnType) []const u8 {
        return @tagName(self);
    }

    pub fn literalLayout(self: LifeReturnType) LifeLiteralLayout {
        return switch (self) {
            .RET_S8 => .s8,
            .RET_S16 => .s16,
            .RET_STRING => .string,
            .RET_U8 => .u8,
        };
    }

    pub fn fixedLiteralByteLength(self: LifeReturnType) ?usize {
        return switch (self) {
            .RET_S8, .RET_U8 => 1,
            .RET_S16 => 2,
            .RET_STRING => null,
        };
    }

    pub fn fixedTestByteLength(self: LifeReturnType) ?usize {
        const literal_byte_length = self.fixedLiteralByteLength() orelse return null;
        return 1 + literal_byte_length;
    }

    pub fn variableLengthReason(self: LifeReturnType) ?LifeVariableLengthReason {
        return switch (self) {
            .RET_STRING => .null_terminated_string,
            else => null,
        };
    }
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

    pub fn fixedCallByteLength(self: LifeFunction) usize {
        return switch (self.operandLayout()) {
            .none => 1,
            .u8 => 2,
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

pub const LifeVariableLengthReason = enum {
    move_mode,
    null_terminated_string,
    embedded_function_layout,
    switch_return_type,
    unsupported,
};

pub const LifeMoveParameterKind = enum {
    actor,
    point,
};

pub const LifeMoveMode = enum(u8) {
    none = 0,
    player_control = 1,
    follow_actor = 2,
    unknown_3 = 3,
    unknown_4 = 4,
    unknown_5 = 5,
    same_xz_other_actor = 6,
    meca_penguin = 7,
    rail_cart = 8,
    circle_point = 9,
    circle_point_facing = 10,
    same_xz_angle_other_actor = 11,
    car = 12,
    car_player_control = 13,
};

pub const LifeHeroBehaviour = enum(u8) {
    normal = 0,
    athletic = 1,
    aggressive = 2,
    discreet = 3,
    protopack = 4,
    walking_with_zoe = 5,
    healing_horn = 6,
    spacesuit_normal_interior = 7,
    jetpack = 8,
    spacesuit_athletic_interior = 9,
    spacesuit_normal_exterior = 10,
    spacesuit_athletic_exterior = 11,
    car = 12,
    skeleton = 13,
};

pub const LifeCanFallState = enum(u8) {
    cannot_fall = 0,
    can_fall = 1,
    cannot_fall_stop_fall = 2,
};

pub const LifeBinaryToggleState = enum(u8) {
    disabled = 0,
    enabled = 1,
};

pub const LifeBuggyInitMode = enum(u8) {
    no_init = 0,
    init_if_needed = 1,
    force_init = 2,
};

pub const LifeZoneToggleKind = enum {
    camera,
    grm,
    change_cube,
    ladder,
    escalator,
    hit_zone,
    rail,
};

pub const LifeZoneToggleIndexMeaning = enum {
    zone_index,
    change_cube_destination_index,
};

pub const LifePcxMessageEffect = enum(u8) {
    none = 0,
    venetian_blinds = 1,
};

pub const LifeHeroBehaviourSemantic = struct {
    raw_value: u8,
    behaviour: ?LifeHeroBehaviour,
};

pub const LifeCanFallSemantic = struct {
    raw_value: u8,
    state: ?LifeCanFallState,
};

pub const LifeBrickCollisionSemantic = struct {
    raw_value: u8,
    enabled: ?bool,
};

pub const LifeBinaryToggleSemantic = struct {
    raw_value: u8,
    state: ?LifeBinaryToggleState,
};

pub const LifeBuggyInitSemantic = struct {
    raw_value: u8,
    mode: ?LifeBuggyInitMode,
};

pub const LifeZoneToggleSemantic = struct {
    kind: LifeZoneToggleKind,
    index_meaning: LifeZoneToggleIndexMeaning,
    raw_index: u8,
    raw_flag: u8,
    enabled: ?bool,
};

pub const LifePcxMessageSemantic = struct {
    image_index: u8,
    raw_effect: u8,
    effect: ?LifePcxMessageEffect,
    speaker_object_index: u8,
    message_id: i16,
};

pub const LifeLiteralLayout = enum {
    s8,
    s16,
    string,
    u8,
};

pub const LifeOpcodeDescriptor = struct {
    id: u8,
    mnemonic: []const u8,
    supported: bool,
    operand_layout: LifeOperandLayout,
    fixed_instruction_byte_length: ?usize,
    variable_length_reason: ?LifeVariableLengthReason,
    semantic_operand_kind: ?LifeSemanticOperandKind,
};

pub const LifeFunctionDescriptor = struct {
    id: u8,
    mnemonic: []const u8,
    operand_layout: LifeFunctionOperandLayout,
    return_type: LifeReturnType,
    fixed_call_byte_length: usize,
};

pub const LifeComparatorDescriptor = struct {
    id: u8,
    mnemonic: []const u8,
};

pub const LifeReturnTypeDescriptor = struct {
    id: u8,
    mnemonic: []const u8,
    literal_layout: LifeLiteralLayout,
    fixed_literal_byte_length: ?usize,
    fixed_test_byte_length: ?usize,
    variable_length_reason: ?LifeVariableLengthReason,
};

pub const LifeCatalog = struct {
    opcodes: []const LifeOpcodeDescriptor,
    functions: []const LifeFunctionDescriptor,
    comparators: []const LifeComparatorDescriptor,
    return_types: []const LifeReturnTypeDescriptor,

    pub fn deinit(self: LifeCatalog, allocator: std.mem.Allocator) void {
        allocator.free(self.opcodes);
        allocator.free(self.functions);
        allocator.free(self.comparators);
        allocator.free(self.return_types);
    }
};

pub fn buildCatalog(allocator: std.mem.Allocator) !LifeCatalog {
    var opcode_descriptors: std.ArrayList(LifeOpcodeDescriptor) = .empty;
    errdefer opcode_descriptors.deinit(allocator);

    var function_descriptors: std.ArrayList(LifeFunctionDescriptor) = .empty;
    errdefer function_descriptors.deinit(allocator);

    var comparator_descriptors: std.ArrayList(LifeComparatorDescriptor) = .empty;
    errdefer comparator_descriptors.deinit(allocator);

    var return_type_descriptors: std.ArrayList(LifeReturnTypeDescriptor) = .empty;
    errdefer return_type_descriptors.deinit(allocator);

    inline for (std.meta.fields(LifeOpcode)) |field| {
        const opcode: LifeOpcode = @enumFromInt(field.value);
        try opcode_descriptors.append(allocator, .{
            .id = @intFromEnum(opcode),
            .mnemonic = opcode.mnemonic(),
            .supported = opcode.isSupported(),
            .operand_layout = opcode.operandLayout(),
            .fixed_instruction_byte_length = opcode.fixedInstructionByteLength(),
            .variable_length_reason = opcode.variableLengthReason(),
            .semantic_operand_kind = opcode.semanticOperandKind(),
        });
    }

    inline for (std.meta.fields(LifeFunction)) |field| {
        const function: LifeFunction = @enumFromInt(field.value);
        try function_descriptors.append(allocator, .{
            .id = @intFromEnum(function),
            .mnemonic = function.mnemonic(),
            .operand_layout = function.operandLayout(),
            .return_type = function.returnType(),
            .fixed_call_byte_length = function.fixedCallByteLength(),
        });
    }

    inline for (std.meta.fields(LifeComparator)) |field| {
        const comparator: LifeComparator = @enumFromInt(field.value);
        try comparator_descriptors.append(allocator, .{
            .id = @intFromEnum(comparator),
            .mnemonic = comparator.mnemonic(),
        });
    }

    inline for (std.meta.fields(LifeReturnType)) |field| {
        const return_type: LifeReturnType = @enumFromInt(field.value);
        try return_type_descriptors.append(allocator, .{
            .id = @intFromEnum(return_type),
            .mnemonic = return_type.mnemonic(),
            .literal_layout = return_type.literalLayout(),
            .fixed_literal_byte_length = return_type.fixedLiteralByteLength(),
            .fixed_test_byte_length = return_type.fixedTestByteLength(),
            .variable_length_reason = return_type.variableLengthReason(),
        });
    }

    return .{
        .opcodes = try opcode_descriptors.toOwnedSlice(allocator),
        .functions = try function_descriptors.toOwnedSlice(allocator),
        .comparators = try comparator_descriptors.toOwnedSlice(allocator),
        .return_types = try return_type_descriptors.toOwnedSlice(allocator),
    };
}

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
    raw_mode_id: u8,
    mode: ?LifeMoveMode,
    parameter: ?u8,
    parameter_kind: ?LifeMoveParameterKind,
};

pub const LifeMoveObjectOperand = struct {
    object_index: u8,
    raw_mode_id: u8,
    mode: ?LifeMoveMode,
    parameter: ?u8,
    parameter_kind: ?LifeMoveParameterKind,
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

    pub fn semanticOperand(self: LifeInstruction) ?LifeInstructionSemantic {
        return switch (self.opcode) {
            .LM_SET_DIR => switch (self.operands) {
                .move => |value| .{ .move_mode = value },
                else => null,
            },
            .LM_SET_DIR_OBJ => switch (self.operands) {
                .move_obj => |value| .{ .move_mode_obj = value },
                else => null,
            },
            .LM_COMPORTEMENT_HERO => switch (self.operands) {
                .u8_value => |raw_value| .{ .hero_behaviour = .{
                    .raw_value = raw_value,
                    .behaviour = decodeEnumOrNull(LifeHeroBehaviour, raw_value),
                } },
                else => null,
            },
            .LM_FALLABLE => switch (self.operands) {
                .u8_value => |raw_value| .{ .can_fall = .{
                    .raw_value = raw_value,
                    .state = decodeEnumOrNull(LifeCanFallState, raw_value),
                } },
                else => null,
            },
            .LM_BRICK_COL => switch (self.operands) {
                .u8_value => |raw_value| .{ .brick_collision = .{
                    .raw_value = raw_value,
                    .enabled = switch (raw_value) {
                        0 => false,
                        1 => true,
                        else => null,
                    },
                } },
                else => null,
            },
            .LM_BULLE,
            .LM_NO_CHOC,
            .LM_CINEMA_MODE,
            .LM_BACKGROUND,
            => switch (self.operands) {
                .u8_value => |raw_value| .{ .binary_toggle = .{
                    .raw_value = raw_value,
                    .state = decodeEnumOrNull(LifeBinaryToggleState, raw_value),
                } },
                else => null,
            },
            .LM_INIT_BUGGY => switch (self.operands) {
                .u8_value => |raw_value| .{ .buggy_init = .{
                    .raw_value = raw_value,
                    .mode = decodeEnumOrNull(LifeBuggyInitMode, raw_value),
                } },
                else => null,
            },
            .LM_SET_CAMERA,
            .LM_SET_GRM,
            .LM_SET_CHANGE_CUBE,
            .LM_ECHELLE,
            .LM_ESCALATOR,
            .LM_SET_HIT_ZONE,
            .LM_SET_RAIL,
            => switch (self.operands) {
                .u8_pair => |value| .{ .zone_toggle = .{
                    .kind = switch (self.opcode) {
                        .LM_SET_CAMERA => .camera,
                        .LM_SET_GRM => .grm,
                        .LM_SET_CHANGE_CUBE => .change_cube,
                        .LM_ECHELLE => .ladder,
                        .LM_ESCALATOR => .escalator,
                        .LM_SET_HIT_ZONE => .hit_zone,
                        .LM_SET_RAIL => .rail,
                        else => unreachable,
                    },
                    .index_meaning = if (self.opcode == .LM_SET_CHANGE_CUBE) .change_cube_destination_index else .zone_index,
                    .raw_index = value.first,
                    .raw_flag = value.second,
                    .enabled = switch (value.second) {
                        0 => false,
                        1 => true,
                        else => null,
                    },
                } },
                else => null,
            },
            .LM_PCX_MESS_OBJ => switch (self.operands) {
                .u8_u8_u8_i16 => |value| .{ .pcx_message = .{
                    .image_index = value.first_u8,
                    .raw_effect = value.second_u8,
                    .effect = decodeEnumOrNull(LifePcxMessageEffect, value.second_u8),
                    .speaker_object_index = value.third_u8,
                    .message_id = value.word_i16,
                } },
                else => null,
            },
            else => null,
        };
    }
};

pub const LifeInstructionSemantic = union(enum) {
    move_mode: LifeMoveOperand,
    move_mode_obj: LifeMoveObjectOperand,
    hero_behaviour: LifeHeroBehaviourSemantic,
    can_fall: LifeCanFallSemantic,
    brick_collision: LifeBrickCollisionSemantic,
    binary_toggle: LifeBinaryToggleSemantic,
    buggy_init: LifeBuggyInitSemantic,
    zone_toggle: LifeZoneToggleSemantic,
    pcx_message: LifePcxMessageSemantic,
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
        const opcode = enumFromInt(LifeOpcode, opcode_id) orelse return .{
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
    const opcode = enumFromInt(LifeOpcode, opcode_id) orelse return error.UnknownLifeOpcode;

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
            const raw_mode_id = try readScalar(bytes, offset + 1);
            const parameter = if (moveUsesExtraParameter(raw_mode_id)) try readScalar(bytes, offset + 2) else null;
            break :blk .{
                .instruction = .{
                    .offset = offset,
                    .opcode = opcode,
                    .byte_length = 2 + @as(usize, @intFromBool(parameter != null)),
                    .operands = .{ .move = .{
                        .raw_mode_id = raw_mode_id,
                        .mode = decodeEnumOrNull(LifeMoveMode, raw_mode_id),
                        .parameter = parameter,
                        .parameter_kind = moveParameterKind(raw_mode_id),
                    } },
                },
                .active_switch_return_type = active_switch_return_type,
            };
        },
        .move_obj => blk: {
            const object_index = try readScalar(bytes, offset + 1);
            const raw_mode_id = try readScalar(bytes, offset + 2);
            const parameter = if (moveUsesExtraParameter(raw_mode_id)) try readScalar(bytes, offset + 3) else null;
            break :blk .{
                .instruction = .{
                    .offset = offset,
                    .opcode = opcode,
                    .byte_length = 3 + @as(usize, @intFromBool(parameter != null)),
                    .operands = .{ .move_obj = .{
                        .object_index = object_index,
                        .raw_mode_id = raw_mode_id,
                        .mode = decodeEnumOrNull(LifeMoveMode, raw_mode_id),
                        .parameter = parameter,
                        .parameter_kind = moveParameterKind(raw_mode_id),
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
    const function = enumFromInt(LifeFunction, function_id) orelse return error.UnknownLifeFunction;

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
    const comparator = enumFromInt(LifeComparator, comparator_id) orelse return error.UnknownLifeComparator;

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

fn moveUsesExtraParameter(raw_mode_id: u8) bool {
    return switch (raw_mode_id) {
        2, 6, 9, 10, 11 => true,
        else => false,
    };
}

fn moveParameterKind(raw_mode_id: u8) ?LifeMoveParameterKind {
    return switch (raw_mode_id) {
        2, 6, 11 => .actor,
        9, 10 => .point,
        else => null,
    };
}

fn decodeEnumOrNull(comptime T: type, raw_value: u8) ?T {
    return enumFromInt(T, raw_value);
}

fn enumFromInt(comptime T: type, raw_value: anytype) ?T {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        if (raw_value == field.value) return @enumFromInt(field.value);
    }
    return null;
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

const std = @import("std");

pub const TrackOperandLayout = enum {
    none,
    u8,
    u16,
    i16,
    point_index,
    background,
    label,
    wait_nb_anim,
    wait_timer,
    loop,
    angle,
    face_twinsen,
    angle_rnd,
    string,
};

pub const TrackOpcode = enum(u8) {
    end = 0,
    nop = 1,
    body = 2,
    anim = 3,
    goto_point = 4,
    wait_anim = 5,
    loop = 6,
    angle = 7,
    pos_point = 8,
    label = 9,
    goto = 10,
    stop = 11,
    goto_sym_point = 12,
    wait_nb_anim = 13,
    sample = 14,
    goto_point_3d = 15,
    speed = 16,
    background = 17,
    wait_nb_second = 18,
    no_body = 19,
    beta = 20,
    open_left = 21,
    open_right = 22,
    open_up = 23,
    open_down = 24,
    close = 25,
    wait_door = 26,
    sample_rnd = 27,
    sample_always = 28,
    sample_stop = 29,
    play_acf = 30,
    repeat_sample = 31,
    simple_sample = 32,
    face_twinsen = 33,
    angle_rnd = 34,
    rem = 35,
    wait_nb_dizieme = 36,
    do = 37,
    sprite = 38,
    wait_nb_second_rnd = 39,
    aff_timer = 40,
    set_frame = 41,
    set_frame_3ds = 42,
    set_start_3ds = 43,
    set_end_3ds = 44,
    start_anim_3ds = 45,
    stop_anim_3ds = 46,
    wait_anim_3ds = 47,
    wait_frame_3ds = 48,
    wait_nb_dizieme_rnd = 49,
    decalage = 50,
    frequence = 51,
    volume = 52,

    pub fn mnemonic(self: TrackOpcode) []const u8 {
        return switch (self) {
            .end => "TM_END",
            .nop => "TM_NOP",
            .body => "TM_BODY",
            .anim => "TM_ANIM",
            .goto_point => "TM_GOTO_POINT",
            .wait_anim => "TM_WAIT_ANIM",
            .loop => "TM_LOOP",
            .angle => "TM_ANGLE",
            .pos_point => "TM_POS_POINT",
            .label => "TM_LABEL",
            .goto => "TM_GOTO",
            .stop => "TM_STOP",
            .goto_sym_point => "TM_GOTO_SYM_POINT",
            .wait_nb_anim => "TM_WAIT_NB_ANIM",
            .sample => "TM_SAMPLE",
            .goto_point_3d => "TM_GOTO_POINT_3D",
            .speed => "TM_SPEED",
            .background => "TM_BACKGROUND",
            .wait_nb_second => "TM_WAIT_NB_SECOND",
            .no_body => "TM_NO_BODY",
            .beta => "TM_BETA",
            .open_left => "TM_OPEN_LEFT",
            .open_right => "TM_OPEN_RIGHT",
            .open_up => "TM_OPEN_UP",
            .open_down => "TM_OPEN_DOWN",
            .close => "TM_CLOSE",
            .wait_door => "TM_WAIT_DOOR",
            .sample_rnd => "TM_SAMPLE_RND",
            .sample_always => "TM_SAMPLE_ALWAYS",
            .sample_stop => "TM_SAMPLE_STOP",
            .play_acf => "TM_PLAY_ACF",
            .repeat_sample => "TM_REPEAT_SAMPLE",
            .simple_sample => "TM_SIMPLE_SAMPLE",
            .face_twinsen => "TM_FACE_TWINSEN",
            .angle_rnd => "TM_ANGLE_RND",
            .rem => "TM_REM",
            .wait_nb_dizieme => "TM_WAIT_NB_DIZIEME",
            .do => "TM_DO",
            .sprite => "TM_SPRITE",
            .wait_nb_second_rnd => "TM_WAIT_NB_SECOND_RND",
            .aff_timer => "TM_AFF_TIMER",
            .set_frame => "TM_SET_FRAME",
            .set_frame_3ds => "TM_SET_FRAME_3DS",
            .set_start_3ds => "TM_SET_START_3DS",
            .set_end_3ds => "TM_SET_END_3DS",
            .start_anim_3ds => "TM_START_ANIM_3DS",
            .stop_anim_3ds => "TM_STOP_ANIM_3DS",
            .wait_anim_3ds => "TM_WAIT_ANIM_3DS",
            .wait_frame_3ds => "TM_WAIT_FRAME_3DS",
            .wait_nb_dizieme_rnd => "TM_WAIT_NB_DIZIEME_RND",
            .decalage => "TM_DECALAGE",
            .frequence => "TM_FREQUENCE",
            .volume => "TM_VOLUME",
        };
    }

    pub fn operandLayout(self: TrackOpcode) TrackOperandLayout {
        return switch (self) {
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
            => .none,
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
            => .u8,
            .anim => .u16,
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
            => .i16,
            .background => .background,
            .label => .label,
            .wait_nb_anim => .wait_nb_anim,
            .wait_nb_second,
            .wait_nb_second_rnd,
            .wait_nb_dizieme,
            .wait_nb_dizieme_rnd,
            => .wait_timer,
            .loop => .loop,
            .angle => .angle,
            .face_twinsen => .face_twinsen,
            .angle_rnd => .angle_rnd,
            .play_acf => .string,
        };
    }
};

pub const TrackOperands = union(enum) {
    none: void,
    u8_value: u8,
    u16_value: u16,
    i16_value: i16,
    background: struct {
        raw_value: u8,
        enabled: bool,
    },
    label: struct {
        label: u8,
    },
    wait_nb_anim: struct {
        animation_count: u8,
        completed_animation_count: u8,
    },
    wait_timer: struct {
        raw_count: u8,
        deadline_timestamp: u32,
    },
    loop: struct {
        initial_count: u8,
        remaining_count: u8,
        target_offset: i16,
    },
    angle: struct {
        raw_angle: u16,
        target_angle: u16,
        rotation_started: bool,
    },
    face_twinsen: struct {
        cached_angle: i16,
    },
    angle_rnd: struct {
        delta_angle: i16,
        cached_angle: i16,
    },
    string: []const u8,
};

pub const TrackInstruction = struct {
    offset: usize,
    opcode: TrackOpcode,
    byte_length: usize,
    operands: TrackOperands,

    pub fn endOffset(self: TrackInstruction) usize {
        return self.offset + self.byte_length;
    }

    pub fn jsonStringify(self: TrackInstruction, jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("offset");
        try jws.write(self.offset);
        try jws.objectField("opcode");
        try jws.write(@intFromEnum(self.opcode));
        try jws.objectField("mnemonic");
        try jws.write(self.opcode.mnemonic());
        try jws.objectField("byte_length");
        try jws.write(self.byte_length);

        switch (self.opcode) {
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
            .body => {
                const value = expectOperand(self.operands, .u8_value);
                try jws.objectField("body_index");
                try jws.write(value);
            },
            .goto_point,
            .goto_point_3d,
            .goto_sym_point,
            .pos_point,
            => {
                const value = expectOperand(self.operands, .u8_value);
                try jws.objectField("point_index");
                try jws.write(value);
            },
            .set_frame,
            .set_frame_3ds,
            .set_start_3ds,
            .set_end_3ds,
            .wait_frame_3ds,
            => {
                const value = expectOperand(self.operands, .u8_value);
                try jws.objectField("frame_index");
                try jws.write(value);
            },
            .start_anim_3ds => {
                const value = expectOperand(self.operands, .u8_value);
                try jws.objectField("fps");
                try jws.write(value);
            },
            .volume => {
                const value = expectOperand(self.operands, .u8_value);
                try jws.objectField("volume");
                try jws.write(value);
            },
            .anim => {
                const value = expectOperand(self.operands, .u16_value);
                try jws.objectField("anim_index");
                try jws.write(value);
            },
            .sample,
            .sample_rnd,
            .sample_always,
            .sample_stop,
            .repeat_sample,
            .simple_sample,
            => {
                const value = expectOperand(self.operands, .i16_value);
                try jws.objectField("sample_index");
                try jws.write(value);
            },
            .speed => {
                const value = expectOperand(self.operands, .i16_value);
                try jws.objectField("speed");
                try jws.write(value);
            },
            .beta => {
                const value = expectOperand(self.operands, .i16_value);
                try jws.objectField("beta");
                try jws.write(value);
            },
            .open_left,
            .open_right,
            .open_up,
            .open_down,
            => {
                const value = expectOperand(self.operands, .i16_value);
                try jws.objectField("door_width");
                try jws.write(value);
            },
            .goto => {
                const value = expectOperand(self.operands, .i16_value);
                try jws.objectField("target_offset");
                try jws.write(value);
            },
            .sprite => {
                const value = expectOperand(self.operands, .i16_value);
                try jws.objectField("sprite_index");
                try jws.write(value);
            },
            .decalage => {
                const value = expectOperand(self.operands, .i16_value);
                try jws.objectField("sample_decalage");
                try jws.write(value);
            },
            .frequence => {
                const value = expectOperand(self.operands, .i16_value);
                try jws.objectField("sample_frequency");
                try jws.write(value);
            },
            .background => {
                const value = expectOperand(self.operands, .background);
                try jws.objectField("raw_value");
                try jws.write(value.raw_value);
                try jws.objectField("enabled");
                try jws.write(value.enabled);
            },
            .label => {
                const value = expectOperand(self.operands, .label);
                try jws.objectField("label");
                try jws.write(value.label);
            },
            .wait_nb_anim => {
                const value = expectOperand(self.operands, .wait_nb_anim);
                try jws.objectField("animation_count");
                try jws.write(value.animation_count);
                try jws.objectField("completed_animation_count");
                try jws.write(value.completed_animation_count);
            },
            .wait_nb_second => {
                const value = expectOperand(self.operands, .wait_timer);
                try jws.objectField("seconds");
                try jws.write(value.raw_count);
                try jws.objectField("deadline_timestamp");
                try jws.write(value.deadline_timestamp);
            },
            .wait_nb_second_rnd => {
                const value = expectOperand(self.operands, .wait_timer);
                try jws.objectField("max_seconds");
                try jws.write(value.raw_count);
                try jws.objectField("deadline_timestamp");
                try jws.write(value.deadline_timestamp);
            },
            .wait_nb_dizieme => {
                const value = expectOperand(self.operands, .wait_timer);
                try jws.objectField("tenths");
                try jws.write(value.raw_count);
                try jws.objectField("deadline_timestamp");
                try jws.write(value.deadline_timestamp);
            },
            .wait_nb_dizieme_rnd => {
                const value = expectOperand(self.operands, .wait_timer);
                try jws.objectField("max_tenths");
                try jws.write(value.raw_count);
                try jws.objectField("deadline_timestamp");
                try jws.write(value.deadline_timestamp);
            },
            .loop => {
                const value = expectOperand(self.operands, .loop);
                try jws.objectField("initial_count");
                try jws.write(value.initial_count);
                try jws.objectField("remaining_count");
                try jws.write(value.remaining_count);
                try jws.objectField("target_offset");
                try jws.write(value.target_offset);
            },
            .angle => {
                const value = expectOperand(self.operands, .angle);
                try jws.objectField("raw_angle");
                try jws.write(value.raw_angle);
                try jws.objectField("target_angle");
                try jws.write(value.target_angle);
                try jws.objectField("rotation_started");
                try jws.write(value.rotation_started);
            },
            .face_twinsen => {
                const value = expectOperand(self.operands, .face_twinsen);
                try jws.objectField("cached_angle");
                try jws.write(value.cached_angle);
            },
            .angle_rnd => {
                const value = expectOperand(self.operands, .angle_rnd);
                try jws.objectField("delta_angle");
                try jws.write(value.delta_angle);
                try jws.objectField("cached_angle");
                try jws.write(value.cached_angle);
            },
            .play_acf => {
                const value = expectOperand(self.operands, .string);
                try jws.objectField("clip_name");
                try jws.write(value);
            },
        }

        try jws.endObject();
    }
};

pub fn decodeTrackProgram(allocator: std.mem.Allocator, bytes: []const u8) ![]TrackInstruction {
    var instructions: std.ArrayList(TrackInstruction) = .empty;
    errdefer instructions.deinit(allocator);

    var offset: usize = 0;
    while (offset < bytes.len) {
        const instruction = try decodeInstruction(bytes, offset);
        try instructions.append(allocator, instruction);
        offset += instruction.byte_length;
    }

    return instructions.toOwnedSlice(allocator);
}

fn decodeInstruction(bytes: []const u8, offset: usize) !TrackInstruction {
    const opcode_id = try readScalar(bytes, offset);
    const opcode = std.meta.intToEnum(TrackOpcode, opcode_id) catch return error.UnknownTrackOpcode;

    return switch (opcode.operandLayout()) {
        .none => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 1,
            .operands = .{ .none = {} },
        },
        .u8 => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 2,
            .operands = .{ .u8_value = try readScalar(bytes, offset + 1) },
        },
        .u16 => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 3,
            .operands = .{ .u16_value = try readInt(bytes, offset + 1, u16) },
        },
        .i16 => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 3,
            .operands = .{ .i16_value = try readInt(bytes, offset + 1, i16) },
        },
        .background => blk: {
            const raw_value = try readScalar(bytes, offset + 1);
            break :blk .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 2,
                .operands = .{ .background = .{
                    .raw_value = raw_value,
                    .enabled = raw_value != 0,
                } },
            };
        },
        .label => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 2,
            .operands = .{ .label = .{ .label = try readScalar(bytes, offset + 1) } },
        },
        .wait_nb_anim => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 3,
            .operands = .{ .wait_nb_anim = .{
                .animation_count = try readScalar(bytes, offset + 1),
                .completed_animation_count = try readScalar(bytes, offset + 2),
            } },
        },
        .wait_timer => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 6,
            .operands = .{ .wait_timer = .{
                .raw_count = try readScalar(bytes, offset + 1),
                .deadline_timestamp = try readInt(bytes, offset + 2, u32),
            } },
        },
        .loop => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 5,
            .operands = .{ .loop = .{
                .initial_count = try readScalar(bytes, offset + 1),
                .remaining_count = try readScalar(bytes, offset + 2),
                .target_offset = try readInt(bytes, offset + 3, i16),
            } },
        },
        .angle => blk: {
            const raw_angle = try readInt(bytes, offset + 1, u16);
            break :blk .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = 3,
                .operands = .{ .angle = .{
                    .raw_angle = raw_angle,
                    .target_angle = raw_angle & 0x7FFF,
                    .rotation_started = (raw_angle & 0x8000) != 0,
                } },
            };
        },
        .face_twinsen => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 3,
            .operands = .{ .face_twinsen = .{
                .cached_angle = try readInt(bytes, offset + 1, i16),
            } },
        },
        .angle_rnd => .{
            .offset = offset,
            .opcode = opcode,
            .byte_length = 5,
            .operands = .{ .angle_rnd = .{
                .delta_angle = try readInt(bytes, offset + 1, i16),
                .cached_angle = try readInt(bytes, offset + 3, i16),
            } },
        },
        .string => blk: {
            const end = findStringTerminator(bytes, offset + 1) orelse return error.MalformedTrackStringOperand;
            break :blk .{
                .offset = offset,
                .opcode = opcode,
                .byte_length = end - offset + 1,
                .operands = .{ .string = bytes[(offset + 1)..end] },
            };
        },
        .point_index => unreachable,
    };
}

fn readScalar(bytes: []const u8, offset: usize) !u8 {
    if (offset >= bytes.len) return error.TruncatedTrackOperand;
    return bytes[offset];
}

fn readInt(bytes: []const u8, offset: usize, comptime T: type) !T {
    const size = @sizeOf(T);
    if (offset + size > bytes.len) return error.TruncatedTrackOperand;
    return std.mem.readInt(T, bytes[offset .. offset + size][0..size], .little);
}

fn findStringTerminator(bytes: []const u8, offset: usize) ?usize {
    var cursor = offset;
    while (cursor < bytes.len) : (cursor += 1) {
        if (bytes[cursor] == 0) return cursor;
    }
    return null;
}

fn expectOperand(value: TrackOperands, comptime tag: std.meta.Tag(TrackOperands)) std.meta.TagPayload(TrackOperands, tag) {
    return switch (value) {
        inline else => |payload, active_tag| {
            if (active_tag != tag) unreachable;
            return payload;
        },
    };
}

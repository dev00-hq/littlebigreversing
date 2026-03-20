const std = @import("std");
const asset_fixtures = @import("../../assets/fixtures.zig");
const hqr = @import("../../assets/hqr.zig");
const paths_mod = @import("../../foundation/paths.zig");
const life_program = @import("life_program.zig");
const model = @import("model.zig");
const parser = @import("parser.zig");
const track_program = @import("track_program.zig");
const zones = @import("zones.zig");

fn stringifyJsonAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
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

fn buildSyntheticScenePayload(allocator: std.mem.Allocator) ![]u8 {
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

fn fixtureTargetById(target_id: []const u8) !asset_fixtures.FixtureTarget {
    for (asset_fixtures.fixture_targets) |target| {
        if (std.mem.eql(u8, target.target_id, target_id)) return target;
    }
    return error.MissingFixtureTarget;
}

fn resolveSceneArchivePathForTests(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    return std.fs.path.join(allocator, &.{ resolved.asset_root, relative_path });
}

fn makeRawZone(zone_type: i16, num: i16, raw_info: [8]i32) zones.RawSceneZone {
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

fn instructionStreamByteLength(instructions: []const track_program.TrackInstruction) !usize {
    var total: usize = 0;
    for (instructions) |instruction| {
        try std.testing.expectEqual(total, instruction.offset);
        total += instruction.byte_length;
    }
    return total;
}

fn lifeInstructionStreamByteLength(instructions: []const life_program.LifeInstruction) !usize {
    var total: usize = 0;
    for (instructions) |instruction| {
        try std.testing.expectEqual(total, instruction.offset);
        total += instruction.byte_length;
    }
    return total;
}

fn buildInstructionSample(allocator: std.mem.Allocator, opcode: track_program.TrackOpcode) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    try bytes.append(allocator, @intFromEnum(opcode));
    switch (opcode.operandLayout()) {
        .none => {},
        .u8 => try bytes.append(allocator, 7),
        .u16 => try appendInt(&bytes, allocator, @as(u16, 513)),
        .i16 => try appendInt(&bytes, allocator, @as(i16, -1234)),
        .background => try bytes.append(allocator, 1),
        .label => try bytes.append(allocator, 42),
        .wait_nb_anim => try bytes.appendSlice(allocator, &.{ 4, 1 }),
        .wait_timer => {
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
        .string => try bytes.appendSlice(allocator, &.{ 'I', 'N', 'T', 'R', 'O', 0 }),
        .point_index => unreachable,
    }

    return bytes.toOwnedSlice(allocator);
}

fn appendLifeFunctionSample(list: *std.ArrayList(u8), allocator: std.mem.Allocator, function: life_program.LifeFunction) !void {
    try list.append(allocator, @intFromEnum(function));
    switch (function.operandLayout()) {
        .none => {},
        .u8 => try list.append(allocator, 7),
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

fn buildLifeInstructionSample(allocator: std.mem.Allocator, opcode: life_program.LifeOpcode) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    switch (opcode.operandLayout()) {
        .case_branch => {
            try bytes.append(allocator, @intFromEnum(life_program.LifeOpcode.LM_SWITCH));
            try appendLifeFunctionSample(&bytes, allocator, .LF_VAR_GAME);
            try bytes.append(allocator, @intFromEnum(opcode));
            try appendInt(&bytes, allocator, @as(i16, 123));
            try appendLifeTestSample(&bytes, allocator, .LT_EQUAL, .RET_S16);
            return bytes.toOwnedSlice(allocator);
        },
        else => try bytes.append(allocator, @intFromEnum(opcode)),
    }

    switch (opcode.operandLayout()) {
        .none => {},
        .u8 => try bytes.append(allocator, 7),
        .i8 => try bytes.append(allocator, @bitCast(@as(i8, -7))),
        .u16 => try appendInt(&bytes, allocator, @as(u16, 513)),
        .i16 => try appendInt(&bytes, allocator, @as(i16, -1234)),
        .u8_pair => try bytes.appendSlice(allocator, &.{ 3, 9 }),
        .u8_i8 => {
            try bytes.append(allocator, 5);
            try bytes.append(allocator, @bitCast(@as(i8, -2)));
        },
        .u8_i16 => {
            try bytes.append(allocator, 5);
            try appendInt(&bytes, allocator, @as(i16, -111));
        },
        .i16_u8 => {
            try appendInt(&bytes, allocator, @as(i16, 44));
            try bytes.append(allocator, 2);
        },
        .u8_u16 => {
            try bytes.append(allocator, 5);
            try appendInt(&bytes, allocator, @as(u16, 88));
        },
        .u8_u16_i16 => {
            try bytes.append(allocator, 5);
            try appendInt(&bytes, allocator, @as(u16, 88));
            try appendInt(&bytes, allocator, @as(i16, -30));
        },
        .u8_u8_u8_i16 => {
            try bytes.appendSlice(allocator, &.{ 1, 2, 3 });
            try appendInt(&bytes, allocator, @as(i16, 77));
        },
        .i16_u8_i16 => {
            try appendInt(&bytes, allocator, @as(i16, 11));
            try bytes.append(allocator, 4);
            try appendInt(&bytes, allocator, @as(i16, 22));
        },
        .i16_i16_u8_i16 => {
            try appendInt(&bytes, allocator, @as(i16, 11));
            try appendInt(&bytes, allocator, @as(i16, 22));
            try bytes.append(allocator, 4);
            try appendInt(&bytes, allocator, @as(i16, 33));
        },
        .move => try bytes.appendSlice(allocator, &.{ 2, 7 }),
        .move_obj => try bytes.appendSlice(allocator, &.{ 5, 2, 7 }),
        .string => try bytes.appendSlice(allocator, &.{ 'A', 'C', 'F', 0 }),
        .condition => {
            try appendLifeFunctionSample(&bytes, allocator, .LF_VAR_CUBE);
            try appendLifeTestSample(&bytes, allocator, .LT_EQUAL, .RET_U8);
            try appendInt(&bytes, allocator, @as(i16, 123));
        },
        .switch_expr => try appendLifeFunctionSample(&bytes, allocator, .LF_VAR_GAME),
        .case_branch => unreachable,
        .unsupported => unreachable,
    }

    return bytes.toOwnedSlice(allocator);
}

test "track decoder handles multiple opcode families and preserves mutable fields structurally" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.dupe(u8, &.{
        @intFromEnum(track_program.TrackOpcode.body),         4,
        @intFromEnum(track_program.TrackOpcode.wait_nb_anim), 3,
        1,                                                    @intFromEnum(track_program.TrackOpcode.wait_nb_second_rnd),
        9,                                                    0x78,
        0x56,                                                 0x34,
        0x12,                                                 @intFromEnum(track_program.TrackOpcode.loop),
        5,                                                    3,
        0x2C,                                                 0x01,
        @intFromEnum(track_program.TrackOpcode.angle),        0x23,
        0x81,                                                 @intFromEnum(track_program.TrackOpcode.face_twinsen),
        0xFF,                                                 0xFF,
        @intFromEnum(track_program.TrackOpcode.angle_rnd),    0x78,
        0x00,                                                 0xFF,
        0xFF,                                                 @intFromEnum(track_program.TrackOpcode.play_acf),
        'I',                                                  'N',
        'T',                                                  'R',
        'O',                                                  0,
        @intFromEnum(track_program.TrackOpcode.end),
    });
    defer allocator.free(bytes);

    const instructions = try track_program.decodeTrackProgram(allocator, bytes);
    defer allocator.free(instructions);

    try std.testing.expectEqual(@as(usize, 9), instructions.len);
    try std.testing.expectEqual(@as(usize, bytes.len), try instructionStreamByteLength(instructions));
    try std.testing.expectEqual(track_program.TrackOpcode.body, instructions[0].opcode);
    try std.testing.expectEqual(track_program.TrackOpcode.wait_nb_anim, instructions[1].opcode);
    try std.testing.expectEqual(track_program.TrackOpcode.wait_nb_second_rnd, instructions[2].opcode);
    try std.testing.expectEqual(track_program.TrackOpcode.loop, instructions[3].opcode);
    try std.testing.expectEqual(track_program.TrackOpcode.angle, instructions[4].opcode);
    try std.testing.expectEqual(track_program.TrackOpcode.face_twinsen, instructions[5].opcode);
    try std.testing.expectEqual(track_program.TrackOpcode.angle_rnd, instructions[6].opcode);
    try std.testing.expectEqual(track_program.TrackOpcode.play_acf, instructions[7].opcode);
    try std.testing.expectEqual(track_program.TrackOpcode.end, instructions[8].opcode);

    try std.testing.expectEqual(@as(usize, 2), instructions[0].byte_length);
    try std.testing.expectEqual(@as(usize, 3), instructions[1].byte_length);
    try std.testing.expectEqual(@as(usize, 6), instructions[2].byte_length);
    try std.testing.expectEqual(@as(usize, 5), instructions[3].byte_length);
    try std.testing.expectEqual(@as(usize, 3), instructions[4].byte_length);
    try std.testing.expectEqual(@as(usize, 3), instructions[5].byte_length);
    try std.testing.expectEqual(@as(usize, 5), instructions[6].byte_length);
    try std.testing.expectEqual(@as(usize, 7), instructions[7].byte_length);
    try std.testing.expectEqual(@as(usize, 1), instructions[8].byte_length);

    try std.testing.expectEqual(@as(u16, 0x0123), instructions[4].operands.angle.target_angle);
    try std.testing.expect(instructions[4].operands.angle.rotation_started);
    try std.testing.expectEqual(@as(i16, -1), instructions[5].operands.face_twinsen.cached_angle);
    try std.testing.expectEqual(@as(i16, 120), instructions[6].operands.angle_rnd.delta_angle);
    try std.testing.expectEqual(@as(i16, -1), instructions[6].operands.angle_rnd.cached_angle);
    try std.testing.expectEqualStrings("INTRO", instructions[7].operands.string);
}

test "track decoder exhaustively recognizes opcode ids 0 through 52" {
    const allocator = std.testing.allocator;

    for (0..53) |opcode_id| {
        const opcode = try std.meta.intToEnum(track_program.TrackOpcode, @as(u8, @intCast(opcode_id)));
        const bytes = try buildInstructionSample(allocator, opcode);
        defer allocator.free(bytes);

        const instructions = try track_program.decodeTrackProgram(allocator, bytes);
        defer allocator.free(instructions);

        try std.testing.expectEqual(@as(usize, 1), instructions.len);
        try std.testing.expectEqual(opcode, instructions[0].opcode);
        try std.testing.expectEqual(@as(usize, bytes.len), instructions[0].byte_length);
    }
}

test "track decoder rejects truncated operands and malformed strings" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.TruncatedTrackOperand, track_program.decodeTrackProgram(allocator, &.{@intFromEnum(track_program.TrackOpcode.body)}));
    try std.testing.expectError(error.TruncatedTrackOperand, track_program.decodeTrackProgram(allocator, &.{ @intFromEnum(track_program.TrackOpcode.anim), 0x01 }));
    try std.testing.expectError(error.TruncatedTrackOperand, track_program.decodeTrackProgram(allocator, &.{ @intFromEnum(track_program.TrackOpcode.angle_rnd), 0x01, 0x00, 0x02 }));
    try std.testing.expectError(error.TruncatedTrackOperand, track_program.decodeTrackProgram(allocator, &.{ @intFromEnum(track_program.TrackOpcode.wait_nb_second), 0x03, 0x01, 0x02, 0x03 }));
    try std.testing.expectError(error.MalformedTrackStringOperand, track_program.decodeTrackProgram(allocator, &.{ @intFromEnum(track_program.TrackOpcode.play_acf), 'B', 'A', 'D' }));
    try std.testing.expectError(error.UnknownTrackOpcode, track_program.decodeTrackProgram(allocator, &.{0x7F}));
}

test "life decoder preserves nested control-flow layout and switch case context structurally" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.dupe(u8, &.{
        @intFromEnum(life_program.LifeOpcode.LM_IF),
        @intFromEnum(life_program.LifeFunction.LF_VAR_CUBE),
        7,
        @intFromEnum(life_program.LifeComparator.LT_EQUAL),
        4,
        0x34,
        0x12,
        @intFromEnum(life_program.LifeOpcode.LM_SWITCH),
        @intFromEnum(life_program.LifeFunction.LF_VAR_GAME),
        3,
        @intFromEnum(life_program.LifeOpcode.LM_CASE),
        0x78,
        0x56,
        @intFromEnum(life_program.LifeComparator.LT_EQUAL),
        0x9A,
        0xBC,
        @intFromEnum(life_program.LifeOpcode.LM_PLAY_ACF),
        'A',
        'C',
        'F',
        0,
    });
    defer allocator.free(bytes);

    const instructions = try life_program.decodeLifeProgram(allocator, bytes);
    defer allocator.free(instructions);

    try std.testing.expectEqual(@as(usize, 4), instructions.len);
    try std.testing.expectEqual(@as(usize, bytes.len), try lifeInstructionStreamByteLength(instructions));

    try std.testing.expectEqual(life_program.LifeOpcode.LM_IF, instructions[0].opcode);
    try std.testing.expectEqual(life_program.LifeFunction.LF_VAR_CUBE, instructions[0].operands.condition.function.function);
    try std.testing.expectEqual(life_program.LifeReturnType.RET_U8, instructions[0].operands.condition.function.return_type);
    try std.testing.expectEqual(life_program.LifeComparator.LT_EQUAL, instructions[0].operands.condition.comparison.comparator);
    try std.testing.expectEqual(@as(u8, 4), instructions[0].operands.condition.comparison.literal.u8_value);
    try std.testing.expectEqual(@as(i16, 0x1234), instructions[0].operands.condition.jump_offset);

    try std.testing.expectEqual(life_program.LifeOpcode.LM_SWITCH, instructions[1].opcode);
    try std.testing.expectEqual(life_program.LifeFunction.LF_VAR_GAME, instructions[1].operands.switch_expr.function.function);
    try std.testing.expectEqual(life_program.LifeReturnType.RET_S16, instructions[1].operands.switch_expr.function.return_type);

    try std.testing.expectEqual(life_program.LifeOpcode.LM_CASE, instructions[2].opcode);
    try std.testing.expectEqual(life_program.LifeReturnType.RET_S16, instructions[2].operands.case_branch.switch_return_type);
    try std.testing.expectEqual(@as(i16, 0x5678), instructions[2].operands.case_branch.jump_offset);
    try std.testing.expectEqual(@as(i16, @bitCast(@as(u16, 0xBC9A))), instructions[2].operands.case_branch.comparison.literal.s16_value);

    try std.testing.expectEqual(life_program.LifeOpcode.LM_PLAY_ACF, instructions[3].opcode);
    try std.testing.expectEqualStrings("ACF", instructions[3].operands.string);
}

test "life decoder handles move operands and source-backed return-width quirks" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.dupe(u8, &.{
        @intFromEnum(life_program.LifeOpcode.LM_SET_DIR),          2,                                           9,
        @intFromEnum(life_program.LifeOpcode.LM_SET_DIR_OBJ),      4,                                           6,
        11,                                                        @intFromEnum(life_program.LifeOpcode.LM_IF), @intFromEnum(life_program.LifeFunction.LF_FUEL),
        @intFromEnum(life_program.LifeComparator.LT_EQUAL),        0x34,                                        0x12,
        0x10,                                                      0x00,                                        @intFromEnum(life_program.LifeOpcode.LM_IF),
        @intFromEnum(life_program.LifeFunction.LF_COL_DECORS_OBJ), 3,                                           @intFromEnum(life_program.LifeComparator.LT_DIFFERENT),
        2,                                                         0x20,                                        0x00,
    });
    defer allocator.free(bytes);

    const instructions = try life_program.decodeLifeProgram(allocator, bytes);
    defer allocator.free(instructions);

    try std.testing.expectEqual(@as(usize, 4), instructions.len);
    try std.testing.expectEqual(@as(u8, 2), instructions[0].operands.move.move_id);
    try std.testing.expectEqual(@as(?u8, 9), instructions[0].operands.move.point_index);
    try std.testing.expectEqual(@as(u8, 4), instructions[1].operands.move_obj.object_index);
    try std.testing.expectEqual(@as(u8, 6), instructions[1].operands.move_obj.move_id);
    try std.testing.expectEqual(@as(?u8, 11), instructions[1].operands.move_obj.point_index);

    try std.testing.expectEqual(life_program.LifeReturnType.RET_S16, instructions[2].operands.condition.function.return_type);
    try std.testing.expectEqual(@as(i16, 0x1234), instructions[2].operands.condition.comparison.literal.s16_value);

    try std.testing.expectEqual(life_program.LifeReturnType.RET_S8, instructions[3].operands.condition.function.return_type);
    try std.testing.expectEqual(@as(i8, 2), instructions[3].operands.condition.comparison.literal.s8_value);
}

test "life decoder recognizes every live opcode id from the checked-in runtime" {
    const allocator = std.testing.allocator;
    @setEvalBranchQuota(20_000);

    inline for (std.meta.fields(life_program.LifeOpcode)) |field| {
        const opcode: life_program.LifeOpcode = @enumFromInt(field.value);
        if (opcode.isSupported()) {
            const bytes = try buildLifeInstructionSample(allocator, opcode);
            defer allocator.free(bytes);

            const instructions = try life_program.decodeLifeProgram(allocator, bytes);
            defer allocator.free(instructions);

            if (opcode.operandLayout() == .case_branch) {
                try std.testing.expectEqual(@as(usize, 2), instructions.len);
                try std.testing.expectEqual(life_program.LifeOpcode.LM_SWITCH, instructions[0].opcode);
                try std.testing.expectEqual(opcode, instructions[1].opcode);
            } else {
                try std.testing.expectEqual(@as(usize, 1), instructions.len);
                try std.testing.expectEqual(opcode, instructions[0].opcode);
                try std.testing.expectEqual(@as(usize, bytes.len), instructions[0].byte_length);
            }
        }
    }
}

test "life decoder rejects unsupported ids, missing switch context, truncation, and malformed strings" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.UnsupportedLifeOpcode, life_program.decodeLifeProgram(allocator, &.{@intFromEnum(life_program.LifeOpcode.LM_NOP)}));
    try std.testing.expectError(error.UnknownLifeOpcode, life_program.decodeLifeProgram(allocator, &.{5}));
    try std.testing.expectError(error.MissingLifeSwitchContext, life_program.decodeLifeProgram(allocator, &.{ @intFromEnum(life_program.LifeOpcode.LM_CASE), 0x01, 0x00, @intFromEnum(life_program.LifeComparator.LT_EQUAL), 0x01 }));
    try std.testing.expectError(error.TruncatedLifeOperand, life_program.decodeLifeProgram(allocator, &.{ @intFromEnum(life_program.LifeOpcode.LM_SET_TRACK), 0x01 }));
    try std.testing.expectError(error.TruncatedLifeOperand, life_program.decodeLifeProgram(allocator, &.{ @intFromEnum(life_program.LifeOpcode.LM_SET_DIR), 2 }));
    try std.testing.expectError(error.TruncatedLifeOperand, life_program.decodeLifeProgram(allocator, &.{ @intFromEnum(life_program.LifeOpcode.LM_IF), @intFromEnum(life_program.LifeFunction.LF_VAR_GAME), 3, @intFromEnum(life_program.LifeComparator.LT_EQUAL), 0x02 }));
    try std.testing.expectError(error.MalformedLifeStringOperand, life_program.decodeLifeProgram(allocator, &.{ @intFromEnum(life_program.LifeOpcode.LM_PLAY_ACF), 'B', 'A', 'D' }));
    try std.testing.expectError(error.UnknownLifeFunction, life_program.decodeLifeProgram(allocator, &.{ @intFromEnum(life_program.LifeOpcode.LM_SWITCH), 255 }));
    try std.testing.expectError(error.UnknownLifeComparator, life_program.decodeLifeProgram(allocator, &.{ @intFromEnum(life_program.LifeOpcode.LM_IF), @intFromEnum(life_program.LifeFunction.LF_VAR_CUBE), 7, 255, 1, 0, 0 }));
}

test "life decoder covers selected real scene blobs without changing the scene surface" {
    const allocator = std.testing.allocator;

    const scene2_target = try fixtureTargetById("interior-room-twinsens-house-scene");
    const scene2_path = try resolveSceneArchivePathForTests(allocator, scene2_target.asset_path);
    defer allocator.free(scene2_path);
    const scene2 = try parser.loadSceneMetadata(allocator, scene2_path, scene2_target.entry_index);
    defer scene2.deinit(allocator);

    try std.testing.expectError(error.UnsupportedLifeOpcode, life_program.decodeLifeProgram(allocator, scene2.hero_start.life.bytes));

    const scene2_object5_life = try life_program.decodeLifeProgram(allocator, scene2.objects[4].life.bytes);
    defer allocator.free(scene2_object5_life);
    try std.testing.expectEqual(@as(usize, scene2.objects[4].life.bytes.len), try lifeInstructionStreamByteLength(scene2_object5_life));
}

test "scene payload parsing follows the classic loader layout" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticScenePayload(allocator);
    defer allocator.free(payload);

    const metadata = try parser.parseScenePayload(allocator, 7, .{
        .size_file = @intCast(payload.len),
        .compressed_size_file = @intCast(payload.len),
        .compress_method = 0,
    }, payload);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 7), metadata.entry_index);
    try std.testing.expectEqual(@as(u8, 0), metadata.island);
    try std.testing.expectEqual(@as(i16, 414), metadata.alpha_light);
    try std.testing.expectEqual(@as(u16, 1), metadata.hero_start.trackByteLength());
    try std.testing.expectEqualSlices(u8, &.{0x00}, metadata.hero_start.track.bytes);
    try std.testing.expectEqual(@as(usize, 1), metadata.hero_start.track_instructions.len);
    try std.testing.expectEqual(track_program.TrackOpcode.end, metadata.hero_start.track_instructions[0].opcode);
    try std.testing.expectEqual(@as(u16, 2), metadata.hero_start.lifeByteLength());
    try std.testing.expectEqualSlices(u8, &.{ 0xAA, 0xBB }, metadata.hero_start.life.bytes);
    try std.testing.expectEqual(@as(usize, 2), metadata.object_count);
    try std.testing.expectEqual(@as(usize, 1), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 2), metadata.track_count);
    try std.testing.expectEqual(@as(usize, 1), metadata.patch_count);
    try std.testing.expectEqual(@as(i16, 700), metadata.objects[0].x);
    try std.testing.expectEqual(@as(u16, 1), metadata.objects[0].trackByteLength());
    try std.testing.expectEqualSlices(u8, &.{0x01}, metadata.objects[0].track.bytes);
    try std.testing.expectEqual(@as(usize, 1), metadata.objects[0].track_instructions.len);
    try std.testing.expectEqual(track_program.TrackOpcode.nop, metadata.objects[0].track_instructions[0].opcode);
    try std.testing.expectEqual(@as(u16, 1), metadata.objects[0].lifeByteLength());
    try std.testing.expectEqualSlices(u8, &.{0x02}, metadata.objects[0].life.bytes);
    try std.testing.expectEqual(zones.ZoneType.message, metadata.zones[0].zone_type);
    try std.testing.expectEqualSlices(i32, &.{ 70, 71, 1, 73, 74, 75, 76, 77 }, &metadata.zones[0].raw_info);
    try std.testing.expectEqual(@as(i16, 6), metadata.zones[0].num);
    try std.testing.expectEqual(@as(i16, 6), metadata.zones[0].semantics.message.dialog_id);
    try std.testing.expectEqual(@as(?i32, 71), metadata.zones[0].semantics.message.linked_camera_zone_id);
    try std.testing.expectEqual(zones.MessageDirection.north, metadata.zones[0].semantics.message.facing_direction);
    try std.testing.expectEqual(@as(i32, 6000), metadata.tracks[1].z);
    try std.testing.expectEqual(@as(i16, 99), metadata.patches[0].offset);
}

test "zone json stringify keeps the stable tooling shape" {
    const allocator = std.testing.allocator;
    const zone = try zones.decodeZone(makeRawZone(5, 431, .{ 12, 2, 1, 0, 0, 0, 15000, 1 }), 1);
    const json = try stringifyJsonAlloc(allocator, zone);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"zone_type\": \"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"num\": 431") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\": \"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dialog_id\": 431") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"linked_camera_zone_id\": 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"facing_direction\": \"north\"") != null);
}

test "scene json stringify exposes raw program bytes and derived lengths" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticScenePayload(allocator);
    defer allocator.free(payload);

    const metadata = try parser.parseScenePayload(allocator, 7, .{
        .size_file = @intCast(payload.len),
        .compressed_size_file = @intCast(payload.len),
        .compress_method = 0,
    }, payload);
    defer metadata.deinit(allocator);

    const json = try stringifyJsonAlloc(allocator, .{
        .hero_start = metadata.hero_start,
        .objects = metadata.objects,
    });
    defer allocator.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const hero_start = root.get("hero_start").?.object;
    try std.testing.expectEqual(@as(i64, 1), hero_start.get("track_byte_length").?.integer);
    try std.testing.expectEqual(@as(i64, 2), hero_start.get("life_byte_length").?.integer);
    try std.testing.expectEqual(@as(usize, 1), hero_start.get("track_bytes").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 0x00), hero_start.get("track_bytes").?.array.items[0].integer);
    try std.testing.expectEqual(@as(usize, 1), hero_start.get("track_instructions").?.array.items.len);
    try std.testing.expectEqualStrings("TM_END", hero_start.get("track_instructions").?.array.items[0].object.get("mnemonic").?.string);
    try std.testing.expectEqual(@as(usize, 2), hero_start.get("life_bytes").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 0xAA), hero_start.get("life_bytes").?.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 0xBB), hero_start.get("life_bytes").?.array.items[1].integer);

    const objects = root.get("objects").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), objects[0].object.get("track_bytes").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 0x01), objects[0].object.get("track_bytes").?.array.items[0].integer);
    try std.testing.expectEqual(@as(usize, 1), objects[0].object.get("track_instructions").?.array.items.len);
    try std.testing.expectEqualStrings("TM_NOP", objects[0].object.get("track_instructions").?.array.items[0].object.get("mnemonic").?.string);
    try std.testing.expectEqual(@as(usize, 1), objects[0].object.get("life_bytes").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 0x02), objects[0].object.get("life_bytes").?.array.items[0].integer);
}

test "zone decoder normalizes source-backed load-time semantics" {
    const change_cube = try zones.decodeZone(makeRawZone(0, 42, .{ 17408, 256, 7680, 3, 9, 1, 1, 1 }), 0);
    try std.testing.expectEqual(zones.ZoneType.change_cube, change_cube.zone_type);
    try std.testing.expectEqual(@as(i32, 9), change_cube.raw_info[4]);
    try std.testing.expectEqual(@as(i16, 42), change_cube.semantics.change_cube.destination_cube);
    try std.testing.expect(change_cube.semantics.change_cube.test_brick);
    try std.testing.expect(change_cube.semantics.change_cube.dont_readjust_twinsen);
    try std.testing.expect(change_cube.semantics.change_cube.initially_on);

    const camera = try zones.decodeZone(makeRawZone(1, 7, .{ 2, 5, 19, 341, 3908, 0, 10500, 9 }), 1);
    try std.testing.expectEqual(zones.ZoneType.camera, camera.zone_type);
    try std.testing.expectEqual(@as(?i32, 341), camera.semantics.camera.alpha);
    try std.testing.expectEqual(@as(?i32, 3908), camera.semantics.camera.beta);
    try std.testing.expectEqual(@as(?i32, 0), camera.semantics.camera.gamma);
    try std.testing.expectEqual(@as(?i32, 10500), camera.semantics.camera.distance);
    try std.testing.expect(camera.semantics.camera.initially_on);
    try std.testing.expect(camera.semantics.camera.obligatory);

    const grm = try zones.decodeZone(makeRawZone(3, 5, .{ 12, 0, 1, 0, 0, 0, 0, 0 }), 0);
    try std.testing.expectEqual(@as(i32, 12), grm.semantics.grm.grm_index);
    try std.testing.expect(grm.semantics.grm.initially_on);

    const giver = try zones.decodeZone(makeRawZone(4, 0, .{ 112, 2, 99, 0, 0, 0, 0, 0 }), 0);
    try std.testing.expect(giver.semantics.giver.bonus_kinds.money);
    try std.testing.expect(giver.semantics.giver.bonus_kinds.life);
    try std.testing.expect(giver.semantics.giver.bonus_kinds.magic);
    try std.testing.expectEqual(@as(i32, 2), giver.semantics.giver.quantity);
    try std.testing.expect(!giver.semantics.giver.already_taken);

    const ladder = try zones.decodeZone(makeRawZone(6, 1, .{ 1, 0, 0, 0, 0, 0, 0, 0 }), 0);
    try std.testing.expect(ladder.semantics.ladder.enabled_on_load);

    const hit = try zones.decodeZone(makeRawZone(8, 1, .{ 0, 3, 9, 22, 0, 0, 0, 0 }), 0);
    try std.testing.expectEqual(@as(i32, 3), hit.semantics.hit.damage);
    try std.testing.expectEqual(@as(i32, 9), hit.semantics.hit.cooldown_raw_value);
    try std.testing.expectEqual(@as(i32, 0), hit.semantics.hit.initial_timer);

    const rail = try zones.decodeZone(makeRawZone(9, 2, .{ 1, 0, 0, 0, 0, 0, 0, 0 }), 0);
    try std.testing.expect(rail.semantics.rail.switch_state_on_load);
}

test "zone decoder rejects unsupported types and directions" {
    try std.testing.expectError(error.UnsupportedSceneZoneType, zones.decodeZone(makeRawZone(99, 0, .{ 0, 0, 0, 0, 0, 0, 0, 0 }), 0));
    try std.testing.expectError(error.UnsupportedSceneZoneMessageDirection, zones.decodeZone(makeRawZone(5, 0, .{ 12, 0, 3, 0, 0, 0, 0, 0 }), 0));
    try std.testing.expectError(error.UnsupportedSceneZoneEscalatorDirection, zones.decodeZone(makeRawZone(7, 0, .{ 0, 1, 3, 0, 0, 0, 0, 0 }), 0));
}

test "real scene 2 metadata matches canonical asset bytes" {
    const allocator = std.testing.allocator;
    const target = try fixtureTargetById("interior-room-twinsens-house-scene");
    const archive_path = try resolveSceneArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const metadata = try parser.loadSceneMetadata(allocator, archive_path, target.entry_index);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), metadata.entry_index);
    try std.testing.expectEqual(@as(u32, 1412), metadata.compressed_header.size_file);
    try std.testing.expectEqual(@as(u32, 778), metadata.compressed_header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 1), metadata.compressed_header.compress_method);
    try std.testing.expectEqualStrings("interior", metadata.sceneKind());
    try std.testing.expectEqual(@as(u8, 0), metadata.island);
    try std.testing.expectEqual(@as(u8, 12), metadata.shadow_level);
    try std.testing.expectEqual(@as(i16, 414), metadata.alpha_light);
    try std.testing.expectEqual(@as(i16, 136), metadata.beta_light);
    try std.testing.expectEqual(@as(i16, 9724), metadata.hero_start.x);
    try std.testing.expectEqual(@as(i16, 1024), metadata.hero_start.y);
    try std.testing.expectEqual(@as(i16, 782), metadata.hero_start.z);
    try std.testing.expectEqual(@as(u16, 1), metadata.hero_start.trackByteLength());
    try std.testing.expectEqual(@as(usize, metadata.hero_start.trackByteLength()), metadata.hero_start.track.bytes.len);
    try std.testing.expectEqual(@as(usize, 1), metadata.hero_start.track_instructions.len);
    try std.testing.expectEqual(@as(usize, metadata.hero_start.track.bytes.len), try instructionStreamByteLength(metadata.hero_start.track_instructions));
    try std.testing.expectEqual(@as(u16, 203), metadata.hero_start.lifeByteLength());
    try std.testing.expectEqual(@as(usize, metadata.hero_start.lifeByteLength()), metadata.hero_start.life.bytes.len);
    try std.testing.expectEqual(@as(usize, 9), metadata.object_count);
    try std.testing.expectEqual(@as(usize, 10), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 4), metadata.track_count);
    try std.testing.expectEqual(@as(usize, 4), metadata.patch_count);
    try std.testing.expectEqual(@as(u32, 34887), metadata.objects[0].flags);
    try std.testing.expectEqual(@as(i16, 14), metadata.objects[0].file3d_index);
    try std.testing.expectEqual(@as(u8, 7), metadata.objects[0].move);
    try std.testing.expectEqual(zones.ZoneType.change_cube, metadata.zones[0].zone_type);
    try std.testing.expectEqual(@as(i16, 0), metadata.zones[0].semantics.change_cube.destination_cube);
    try std.testing.expectEqual(@as(i32, 2560), metadata.zones[0].semantics.change_cube.destination_x);
    try std.testing.expect(metadata.zones[0].semantics.change_cube.initially_on);
    try std.testing.expectEqual(zones.ZoneType.scenario, metadata.zones[1].zone_type);
    try std.testing.expectEqual(zones.ZoneType.giver, metadata.zones[2].zone_type);
    try std.testing.expect(metadata.zones[2].semantics.giver.bonus_kinds.money);
    try std.testing.expect(metadata.zones[2].semantics.giver.bonus_kinds.life);
    try std.testing.expect(metadata.zones[2].semantics.giver.bonus_kinds.magic);
    try std.testing.expectEqual(@as(i32, 2), metadata.zones[2].semantics.giver.quantity);
    try std.testing.expectEqual(@as(usize, 5), metadata.objects[4].index);
    try std.testing.expectEqual(@as(u16, 12), metadata.objects[4].trackByteLength());
    try std.testing.expectEqual(@as(usize, metadata.objects[4].trackByteLength()), metadata.objects[4].track.bytes.len);
    try std.testing.expectEqual(@as(usize, 5), metadata.objects[4].track_instructions.len);
    try std.testing.expectEqual(@as(usize, metadata.objects[4].track.bytes.len), try instructionStreamByteLength(metadata.objects[4].track_instructions));
    try std.testing.expectEqual(@as(u16, 51), metadata.objects[4].lifeByteLength());
    try std.testing.expectEqual(@as(usize, metadata.objects[4].lifeByteLength()), metadata.objects[4].life.bytes.len);
    try std.testing.expectEqual(zones.ZoneType.message, metadata.zones[6].zone_type);
    try std.testing.expectEqual(@as(i16, 284), metadata.zones[6].num);
    try std.testing.expectEqual(zones.MessageDirection.north, metadata.zones[6].semantics.message.facing_direction);
    try std.testing.expectEqual(@as(?i32, null), metadata.zones[6].semantics.message.linked_camera_zone_id);
    try std.testing.expectEqual(zones.MessageDirection.west, metadata.zones[7].semantics.message.facing_direction);
    try std.testing.expectEqual(@as(i32, 10736), metadata.tracks[3].z);
    try std.testing.expectEqual(@as(i16, 521), metadata.patches[3].offset);
}

test "real scene 44 metadata matches the canonical citadel exterior target" {
    const allocator = std.testing.allocator;
    const target = try fixtureTargetById("exterior-area-citadel-tavern-and-shop-scene");
    const archive_path = try resolveSceneArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const metadata = try parser.loadSceneMetadata(allocator, archive_path, target.entry_index);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 44), metadata.entry_index);
    try std.testing.expectEqual(@as(?usize, 42), metadata.classicLoaderSceneNumber());
    try std.testing.expectEqual(@as(u32, 9338), metadata.compressed_header.size_file);
    try std.testing.expectEqual(@as(u32, 5917), metadata.compressed_header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 1), metadata.compressed_header.compress_method);
    try std.testing.expectEqualStrings("exterior", metadata.sceneKind());
    try std.testing.expectEqual(@as(u8, 0), metadata.island);
    try std.testing.expectEqual(@as(u8, 7), metadata.cube_x);
    try std.testing.expectEqual(@as(u8, 9), metadata.cube_y);
    try std.testing.expectEqual(@as(i16, 356), metadata.alpha_light);
    try std.testing.expectEqual(@as(i16, 3411), metadata.beta_light);
    try std.testing.expectEqual(@as(i16, 19607), metadata.hero_start.x);
    try std.testing.expectEqual(@as(i16, 13818), metadata.hero_start.z);
    try std.testing.expectEqual(@as(u16, 48), metadata.hero_start.trackByteLength());
    try std.testing.expectEqual(@as(usize, metadata.hero_start.trackByteLength()), metadata.hero_start.track.bytes.len);
    try std.testing.expectEqual(@as(usize, 20), metadata.hero_start.track_instructions.len);
    try std.testing.expectEqual(@as(usize, metadata.hero_start.track.bytes.len), try instructionStreamByteLength(metadata.hero_start.track_instructions));
    try std.testing.expectEqual(@as(u16, 823), metadata.hero_start.lifeByteLength());
    try std.testing.expectEqual(@as(usize, metadata.hero_start.lifeByteLength()), metadata.hero_start.life.bytes.len);
    try std.testing.expectEqual(@as(usize, 20), metadata.object_count);
    try std.testing.expectEqual(@as(usize, 22), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 31), metadata.track_count);
    try std.testing.expectEqual(@as(usize, 154), metadata.patch_count);
    try std.testing.expectEqual(@as(i16, 106), metadata.objects[1].file3d_index);
    try std.testing.expectEqual(@as(usize, 2), metadata.objects[1].index);
    try std.testing.expectEqual(@as(u16, 85), metadata.objects[1].trackByteLength());
    try std.testing.expectEqual(@as(usize, metadata.objects[1].trackByteLength()), metadata.objects[1].track.bytes.len);
    try std.testing.expectEqual(@as(usize, 34), metadata.objects[1].track_instructions.len);
    try std.testing.expectEqual(@as(usize, metadata.objects[1].track.bytes.len), try instructionStreamByteLength(metadata.objects[1].track_instructions));
    try std.testing.expectEqual(@as(u16, 329), metadata.objects[1].lifeByteLength());
    try std.testing.expectEqual(@as(usize, metadata.objects[1].lifeByteLength()), metadata.objects[1].life.bytes.len);
    try std.testing.expectEqual(zones.ZoneType.change_cube, metadata.zones[0].zone_type);
    try std.testing.expectEqual(@as(i16, 42), metadata.zones[0].semantics.change_cube.destination_cube);
    try std.testing.expectEqual(@as(i32, 512), metadata.zones[0].semantics.change_cube.destination_x);
    try std.testing.expectEqual(zones.ZoneType.camera, metadata.zones[3].zone_type);
    try std.testing.expectEqual(@as(i32, 34), metadata.zones[3].semantics.camera.anchor_x);
    try std.testing.expectEqual(@as(?i32, 168), metadata.zones[3].semantics.camera.alpha);
    try std.testing.expect(metadata.zones[3].semantics.camera.initially_on);
    try std.testing.expectEqual(zones.ZoneType.message, metadata.zones[7].zone_type);
    try std.testing.expectEqual(zones.MessageDirection.north, metadata.zones[7].semantics.message.facing_direction);
    try std.testing.expectEqual(@as(?i32, 2), metadata.zones[7].semantics.message.linked_camera_zone_id);
    try std.testing.expectEqual(@as(i32, 11232), metadata.tracks[30].z);
    try std.testing.expectEqual(@as(i16, 7007), metadata.patches[153].offset);
}

test "classic loader scene numbers stay distinct from raw SCENE.HQR entry indices" {
    try std.testing.expectEqual(@as(?usize, null), model.entryIndexToClassicLoaderSceneNumber(1));
    try std.testing.expectEqual(@as(?usize, 0), model.entryIndexToClassicLoaderSceneNumber(2));
    try std.testing.expectEqual(@as(?usize, 42), model.entryIndexToClassicLoaderSceneNumber(44));
}

test "real scene 5 metadata keeps non-golden zone regressions aligned" {
    const allocator = std.testing.allocator;
    const archive_path = try resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const metadata = try parser.loadSceneMetadata(allocator, archive_path, 5);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 5), metadata.entry_index);
    try std.testing.expectEqual(@as(u16, 13), metadata.hero_start.trackByteLength());
    try std.testing.expectEqual(@as(usize, metadata.hero_start.trackByteLength()), metadata.hero_start.track.bytes.len);
    try std.testing.expectEqual(@as(usize, 7), metadata.hero_start.track_instructions.len);
    try std.testing.expectEqual(@as(usize, metadata.hero_start.track.bytes.len), try instructionStreamByteLength(metadata.hero_start.track_instructions));
    try std.testing.expectEqual(@as(u16, 61), metadata.hero_start.lifeByteLength());
    try std.testing.expectEqual(@as(usize, metadata.hero_start.lifeByteLength()), metadata.hero_start.life.bytes.len);
    try std.testing.expectEqual(@as(usize, 12), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 2), metadata.objects[1].index);
    try std.testing.expectEqual(@as(u16, 170), metadata.objects[1].trackByteLength());
    try std.testing.expectEqual(@as(usize, metadata.objects[1].trackByteLength()), metadata.objects[1].track.bytes.len);
    try std.testing.expectEqual(@as(usize, 76), metadata.objects[1].track_instructions.len);
    try std.testing.expectEqual(@as(usize, metadata.objects[1].track.bytes.len), try instructionStreamByteLength(metadata.objects[1].track_instructions));
    try std.testing.expectEqual(@as(u16, 194), metadata.objects[1].lifeByteLength());
    try std.testing.expectEqual(@as(usize, metadata.objects[1].lifeByteLength()), metadata.objects[1].life.bytes.len);
    try std.testing.expectEqual(zones.ZoneType.change_cube, metadata.zones[0].zone_type);
    try std.testing.expectEqual(@as(i16, 3), metadata.zones[0].semantics.change_cube.destination_cube);
    try std.testing.expectEqual(zones.ZoneType.change_cube, metadata.zones[1].zone_type);
    try std.testing.expect(metadata.zones[1].semantics.change_cube.dont_readjust_twinsen);
    try std.testing.expectEqual(zones.ZoneType.giver, metadata.zones[2].zone_type);
    try std.testing.expectEqual(@as(i32, 7), metadata.zones[2].semantics.giver.quantity);
    try std.testing.expectEqual(zones.ZoneType.scenario, metadata.zones[6].zone_type);
    try std.testing.expectEqual(zones.ZoneType.scenario, metadata.zones[7].zone_type);
    try std.testing.expectEqual(@as(i32, 6), metadata.zones[11].semantics.giver.quantity);
}

test "scene payload rejects trailing bytes" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticScenePayload(allocator);
    defer allocator.free(payload);

    const padded = try allocator.alloc(u8, payload.len + 1);
    defer allocator.free(padded);
    @memcpy(padded[0..payload.len], payload);
    padded[payload.len] = 0xFF;

    try std.testing.expectError(
        error.TrailingScenePayloadBytes,
        parser.parseScenePayload(allocator, 7, .{
            .size_file = @intCast(padded.len),
            .compressed_size_file = @intCast(padded.len),
            .compress_method = 0,
        }, padded),
    );
}

test "scene payload rejects zero object count" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticScenePayload(allocator);
    defer allocator.free(payload);

    const patched = try allocator.dupe(u8, payload);
    defer allocator.free(patched);

    patched[69] = 0;
    patched[70] = 0;

    try std.testing.expectError(
        error.InvalidSceneObjectCount,
        parser.parseScenePayload(allocator, 7, .{
            .size_file = @intCast(patched.len),
            .compressed_size_file = @intCast(patched.len),
            .compress_method = 0,
        }, patched),
    );
}

test "scene payload rejects truncated bytes" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticScenePayload(allocator);
    defer allocator.free(payload);

    try std.testing.expectError(
        error.TruncatedScenePayload,
        parser.parseScenePayload(allocator, 7, .{
            .size_file = @intCast(payload.len - 1),
            .compressed_size_file = @intCast(payload.len - 1),
            .compress_method = 0,
        }, payload[0 .. payload.len - 1]),
    );
}

test "scene payload rejects truncation inside a preserved program blob" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticScenePayload(allocator);
    defer allocator.free(payload);

    try std.testing.expectError(
        error.TruncatedScenePayload,
        parser.parseScenePayload(allocator, 7, .{
            .size_file = 68,
            .compressed_size_file = 68,
            .compress_method = 0,
        }, payload[0..68]),
    );
}

test "scene payload preserves wrapped header fields across module split" {
    const allocator = std.testing.allocator;
    const target = try fixtureTargetById("interior-room-twinsens-house-scene");
    const archive_path = try resolveSceneArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const raw_entry = try hqr.extractEntryToBytes(allocator, archive_path, target.entry_index);
    defer allocator.free(raw_entry);

    const header = try hqr.parseResourceHeader(raw_entry);
    const payload = try hqr.decodeResourceEntryBytes(allocator, raw_entry);
    defer allocator.free(payload);

    const metadata = try parser.parseScenePayload(allocator, target.entry_index, header, payload);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(header.size_file, metadata.compressed_header.size_file);
    try std.testing.expectEqual(header.compressed_size_file, metadata.compressed_header.compressed_size_file);
    try std.testing.expectEqual(header.compress_method, metadata.compressed_header.compress_method);
}

test "asset-backed scene zone json retains raw and semantic fields" {
    const allocator = std.testing.allocator;
    const target = try fixtureTargetById("exterior-area-citadel-tavern-and-shop-scene");
    const archive_path = try resolveSceneArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const metadata = try parser.loadSceneMetadata(allocator, archive_path, target.entry_index);
    defer metadata.deinit(allocator);

    const json = try stringifyJsonAlloc(allocator, metadata.zones[7]);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"zone_type\": \"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"raw_info\": [") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\": \"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"linked_camera_zone_id\": 2") != null);
}

const std = @import("std");
const life_program = @import("../life_program.zig");
const parser = @import("../parser.zig");
const support = @import("support.zig");

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
    try std.testing.expectEqual(@as(usize, bytes.len), try support.lifeInstructionStreamByteLength(instructions));

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
        if (support.isLifeOpcodeSupportedIndependent(opcode)) {
            const bytes = try support.buildLifeInstructionSample(allocator, opcode);
            defer allocator.free(bytes);

            const instructions = try life_program.decodeLifeProgram(allocator, bytes);
            defer allocator.free(instructions);

            if (opcode == .LM_CASE or opcode == .LM_OR_CASE) {
                try std.testing.expectEqual(@as(usize, 2), instructions.len);
                try std.testing.expectEqual(life_program.LifeOpcode.LM_SWITCH, instructions[0].opcode);
                try std.testing.expectEqual(opcode, instructions[1].opcode);
                try std.testing.expectEqual(@as(usize, 3), instructions[0].byte_length);
                try std.testing.expectEqual(support.expectedLifeInstructionByteLengthIndependent(opcode), instructions[1].byte_length);
                try std.testing.expectEqual(@as(usize, 9), bytes.len);
            } else {
                try std.testing.expectEqual(@as(usize, 1), instructions.len);
                try std.testing.expectEqual(opcode, instructions[0].opcode);
                try std.testing.expectEqual(support.expectedLifeInstructionByteLengthIndependent(opcode), instructions[0].byte_length);
                try std.testing.expectEqual(support.expectedLifeInstructionByteLengthIndependent(opcode), bytes.len);
            }
        }
    }
}

test "life decoder treats LM_DEFAULT and LM_END_SWITCH as one-byte structural markers" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.dupe(u8, &.{
        @intFromEnum(life_program.LifeOpcode.LM_DEFAULT),
        @intFromEnum(life_program.LifeOpcode.LM_END_SWITCH),
    });
    defer allocator.free(bytes);

    const instructions = try life_program.decodeLifeProgram(allocator, bytes);
    defer allocator.free(instructions);

    try std.testing.expectEqual(@as(usize, 2), instructions.len);
    try std.testing.expectEqual(life_program.LifeOpcode.LM_DEFAULT, instructions[0].opcode);
    try std.testing.expectEqual(@as(usize, 1), instructions[0].byte_length);
    try std.testing.expect(instructions[0].operands == .none);
    try std.testing.expectEqual(life_program.LifeOpcode.LM_END_SWITCH, instructions[1].opcode);
    try std.testing.expectEqual(@as(usize, 1), instructions[1].byte_length);
    try std.testing.expect(instructions[1].operands == .none);
    try std.testing.expectEqual(@as(usize, bytes.len), try support.lifeInstructionStreamByteLength(instructions));
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

    const scene2_target = try support.fixtureTargetById("interior-room-twinsens-house-scene");
    const scene2_path = try support.resolveSceneArchivePathForTests(allocator, scene2_target.asset_path);
    defer allocator.free(scene2_path);
    const scene2 = try parser.loadSceneMetadata(allocator, scene2_path, scene2_target.entry_index);
    defer scene2.deinit(allocator);

    const scene2_hero_life = try life_program.decodeLifeProgram(allocator, scene2.hero_start.life.bytes);
    defer allocator.free(scene2_hero_life);
    try std.testing.expectEqual(@as(usize, scene2.hero_start.life.bytes.len), try support.lifeInstructionStreamByteLength(scene2_hero_life));

    const scene2_object5_life = try life_program.decodeLifeProgram(allocator, scene2.objects[4].life.bytes);
    defer allocator.free(scene2_object5_life);
    try std.testing.expectEqual(@as(usize, scene2.objects[4].life.bytes.len), try support.lifeInstructionStreamByteLength(scene2_object5_life));
}

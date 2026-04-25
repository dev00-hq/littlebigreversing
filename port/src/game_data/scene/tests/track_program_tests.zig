const std = @import("std");
const track_program = @import("../track_program.zig");
const support = @import("support.zig");

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
    try std.testing.expectEqual(@as(usize, bytes.len), try support.instructionStreamByteLength(instructions));
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
        const opcode: track_program.TrackOpcode = @enumFromInt(@as(u8, @intCast(opcode_id)));
        const expected_len = support.expectedTrackInstructionByteLengthIndependent(opcode);
        const bytes = try support.buildInstructionSample(allocator, opcode);
        defer allocator.free(bytes);

        const instructions = try track_program.decodeTrackProgram(allocator, bytes);
        defer allocator.free(instructions);

        try std.testing.expectEqual(@as(usize, 1), instructions.len);
        try std.testing.expectEqual(opcode, instructions[0].opcode);
        try std.testing.expectEqual(expected_len, instructions[0].byte_length);
        try std.testing.expectEqual(expected_len, bytes.len);
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

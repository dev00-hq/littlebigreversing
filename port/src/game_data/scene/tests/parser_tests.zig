const std = @import("std");
const model = @import("../model.zig");
const parser = @import("../parser.zig");
const track_program = @import("../track_program.zig");
const zones = @import("../zones.zig");
const support = @import("support.zig");

test "scene payload parsing follows the classic loader layout" {
    const allocator = std.testing.allocator;
    const payload = try support.buildSyntheticScenePayload(allocator);
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

test "scene json stringify exposes raw program bytes and derived lengths" {
    const allocator = std.testing.allocator;
    const payload = try support.buildSyntheticScenePayload(allocator);
    defer allocator.free(payload);

    const metadata = try parser.parseScenePayload(allocator, 7, .{
        .size_file = @intCast(payload.len),
        .compressed_size_file = @intCast(payload.len),
        .compress_method = 0,
    }, payload);
    defer metadata.deinit(allocator);

    const json = try support.stringifyJsonAlloc(allocator, .{
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

test "classic loader scene numbers stay distinct from raw SCENE.HQR entry indices" {
    try std.testing.expectEqual(@as(?usize, null), model.entryIndexToClassicLoaderSceneNumber(1));
    try std.testing.expectEqual(@as(?usize, 0), model.entryIndexToClassicLoaderSceneNumber(2));
    try std.testing.expectEqual(@as(?usize, 42), model.entryIndexToClassicLoaderSceneNumber(44));
}

test "scene payload rejects trailing bytes" {
    const allocator = std.testing.allocator;
    const payload = try support.buildSyntheticScenePayload(allocator);
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
    const payload = try support.buildSyntheticScenePayload(allocator);
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
    const payload = try support.buildSyntheticScenePayload(allocator);
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
    const payload = try support.buildSyntheticScenePayload(allocator);
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

const std = @import("std");
const hqr = @import("../../../assets/hqr.zig");
const parser = @import("../parser.zig");
const zones = @import("../zones.zig");
const support = @import("support.zig");

test "real scene 2 metadata matches canonical asset bytes" {
    const allocator = std.testing.allocator;
    const target = try support.fixtureTargetById("interior-room-twinsens-house-scene");
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, target.asset_path);
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
    try std.testing.expectEqual(@as(usize, metadata.hero_start.track.bytes.len), try support.instructionStreamByteLength(metadata.hero_start.track_instructions));
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
    try std.testing.expectEqual(@as(usize, metadata.objects[4].track.bytes.len), try support.instructionStreamByteLength(metadata.objects[4].track_instructions));
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
    const target = try support.fixtureTargetById("exterior-area-citadel-tavern-and-shop-scene");
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, target.asset_path);
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
    try std.testing.expectEqual(@as(usize, metadata.hero_start.track.bytes.len), try support.instructionStreamByteLength(metadata.hero_start.track_instructions));
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
    try std.testing.expectEqual(@as(usize, metadata.objects[1].track.bytes.len), try support.instructionStreamByteLength(metadata.objects[1].track_instructions));
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

test "real scene 5 metadata keeps non-golden zone regressions aligned" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const metadata = try parser.loadSceneMetadata(allocator, archive_path, 5);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 5), metadata.entry_index);
    try std.testing.expectEqual(@as(u16, 13), metadata.hero_start.trackByteLength());
    try std.testing.expectEqual(@as(usize, metadata.hero_start.trackByteLength()), metadata.hero_start.track.bytes.len);
    try std.testing.expectEqual(@as(usize, 7), metadata.hero_start.track_instructions.len);
    try std.testing.expectEqual(@as(usize, metadata.hero_start.track.bytes.len), try support.instructionStreamByteLength(metadata.hero_start.track_instructions));
    try std.testing.expectEqual(@as(u16, 61), metadata.hero_start.lifeByteLength());
    try std.testing.expectEqual(@as(usize, metadata.hero_start.lifeByteLength()), metadata.hero_start.life.bytes.len);
    try std.testing.expectEqual(@as(usize, 12), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 2), metadata.objects[1].index);
    try std.testing.expectEqual(@as(u16, 170), metadata.objects[1].trackByteLength());
    try std.testing.expectEqual(@as(usize, metadata.objects[1].trackByteLength()), metadata.objects[1].track.bytes.len);
    try std.testing.expectEqual(@as(usize, 76), metadata.objects[1].track_instructions.len);
    try std.testing.expectEqual(@as(usize, metadata.objects[1].track.bytes.len), try support.instructionStreamByteLength(metadata.objects[1].track_instructions));
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

test "scene payload preserves wrapped header fields across module split" {
    const allocator = std.testing.allocator;
    const target = try support.fixtureTargetById("interior-room-twinsens-house-scene");
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, target.asset_path);
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
    const target = try support.fixtureTargetById("exterior-area-citadel-tavern-and-shop-scene");
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const metadata = try parser.loadSceneMetadata(allocator, archive_path, target.entry_index);
    defer metadata.deinit(allocator);

    const json = try support.stringifyJsonAlloc(allocator, metadata.zones[7]);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"zone_type\": \"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"raw_info\": [") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\": \"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"linked_camera_zone_id\": 2") != null);
}

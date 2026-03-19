const std = @import("std");
const asset_fixtures = @import("../../assets/fixtures.zig");
const hqr = @import("../../assets/hqr.zig");
const paths_mod = @import("../../foundation/paths.zig");
const model = @import("model.zig");
const parser = @import("parser.zig");
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
    try bytes.append(allocator, 0x7F);
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
    try std.testing.expectEqualSlices(u8, &.{0x7F}, metadata.hero_start.track.bytes);
    try std.testing.expectEqual(@as(u16, 2), metadata.hero_start.lifeByteLength());
    try std.testing.expectEqualSlices(u8, &.{ 0xAA, 0xBB }, metadata.hero_start.life.bytes);
    try std.testing.expectEqual(@as(usize, 2), metadata.object_count);
    try std.testing.expectEqual(@as(usize, 1), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 2), metadata.track_count);
    try std.testing.expectEqual(@as(usize, 1), metadata.patch_count);
    try std.testing.expectEqual(@as(i16, 700), metadata.objects[0].x);
    try std.testing.expectEqual(@as(u16, 1), metadata.objects[0].trackByteLength());
    try std.testing.expectEqualSlices(u8, &.{0x01}, metadata.objects[0].track.bytes);
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
    try std.testing.expectEqual(@as(i64, 0x7F), hero_start.get("track_bytes").?.array.items[0].integer);
    try std.testing.expectEqual(@as(usize, 2), hero_start.get("life_bytes").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 0xAA), hero_start.get("life_bytes").?.array.items[0].integer);
    try std.testing.expectEqual(@as(i64, 0xBB), hero_start.get("life_bytes").?.array.items[1].integer);

    const objects = root.get("objects").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), objects[0].object.get("track_bytes").?.array.items.len);
    try std.testing.expectEqual(@as(i64, 0x01), objects[0].object.get("track_bytes").?.array.items[0].integer);
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
    try std.testing.expectEqual(@as(u16, 61), metadata.hero_start.lifeByteLength());
    try std.testing.expectEqual(@as(usize, metadata.hero_start.lifeByteLength()), metadata.hero_start.life.bytes.len);
    try std.testing.expectEqual(@as(usize, 12), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 2), metadata.objects[1].index);
    try std.testing.expectEqual(@as(u16, 170), metadata.objects[1].trackByteLength());
    try std.testing.expectEqual(@as(usize, metadata.objects[1].trackByteLength()), metadata.objects[1].track.bytes.len);
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

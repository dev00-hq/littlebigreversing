const std = @import("std");
const hqr = @import("../assets/hqr.zig");
const asset_fixtures = @import("../assets/fixtures.zig");
const paths_mod = @import("../foundation/paths.zig");

const anim_3ds_flag = 1 << 18;

pub const AmbientSample = struct {
    sample: i16,
    repeat: i16,
    random_delay: i16,
    frequency: i16,
    volume: i16,
};

pub const HeroStart = struct {
    x: i16,
    y: i16,
    z: i16,
    track_byte_length: u16,
    life_byte_length: u16,
};

pub const SceneObject = struct {
    index: usize,
    flags: u32,
    file3d_index: i16,
    gen_body: u8,
    gen_anim: i16,
    sprite: i16,
    x: i16,
    y: i16,
    z: i16,
    hit_force: u8,
    option_flags: i16,
    beta: i16,
    speed_rotation: i16,
    move: u8,
    info: i16,
    info1: i16,
    info2: i16,
    info3: i16,
    bonus_count: i16,
    dominant_color: u8,
    armor: u8,
    life_points: u8,
    track_byte_length: u16,
    life_byte_length: u16,
    anim_3ds_index: ?u32,
    anim_3ds_fps: ?i16,
};

pub const SceneZone = struct {
    x0: i32,
    y0: i32,
    z0: i32,
    x1: i32,
    y1: i32,
    z1: i32,
    info0: i32,
    info1: i32,
    info2: i32,
    info3: i32,
    info4: i32,
    info5: i32,
    info6: i32,
    info7: i32,
    type_id: i16,
    num: i16,
};

pub const TrackPoint = struct {
    index: usize,
    x: i32,
    y: i32,
    z: i32,
};

pub const Patch = struct {
    size: i16,
    offset: i16,
};

pub const SceneMetadata = struct {
    entry_index: usize,
    compressed_header: hqr.ResourceHeader,
    island: u8,
    cube_x: u8,
    cube_y: u8,
    shadow_level: u8,
    mode_labyrinth: u8,
    cube_mode: u8,
    unused_header_byte: u8,
    alpha_light: i16,
    beta_light: i16,
    ambient_samples: [4]AmbientSample,
    second_min: i16,
    second_ecart: i16,
    cube_jingle: u8,
    hero_start: HeroStart,
    checksum: u32,
    object_count: usize,
    zone_count: usize,
    track_count: usize,
    patch_count: usize,
    objects: []SceneObject,
    zones: []SceneZone,
    tracks: []TrackPoint,
    patches: []Patch,

    pub fn deinit(self: SceneMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.objects);
        allocator.free(self.zones);
        allocator.free(self.tracks);
        allocator.free(self.patches);
    }

    pub fn sceneKind(self: SceneMetadata) []const u8 {
        return switch (self.cube_mode) {
            0 => "interior",
            1 => "exterior",
            else => "unknown",
        };
    }
};

pub fn loadSceneMetadata(allocator: std.mem.Allocator, absolute_path: []const u8, entry_index: usize) !SceneMetadata {
    const raw_entry = try hqr.extractEntryToBytes(allocator, absolute_path, entry_index);
    defer allocator.free(raw_entry);

    const header = try hqr.parseResourceHeader(raw_entry);
    const payload = try hqr.decodeResourceEntryBytes(allocator, raw_entry);
    defer allocator.free(payload);

    return parseScenePayload(allocator, entry_index, header, payload);
}

pub fn parseScenePayload(
    allocator: std.mem.Allocator,
    entry_index: usize,
    compressed_header: hqr.ResourceHeader,
    payload: []const u8,
) !SceneMetadata {
    var reader = Reader{ .bytes = payload };

    const island = try reader.readInt(u8);
    const cube_x = try reader.readInt(u8);
    const cube_y = try reader.readInt(u8);
    const shadow_level = try reader.readInt(u8);
    const mode_labyrinth = try reader.readInt(u8);
    const cube_mode = try reader.readInt(u8);
    const unused_header_byte = try reader.readInt(u8);

    const alpha_light = try reader.readInt(i16);
    const beta_light = try reader.readInt(i16);

    var ambient_samples: [4]AmbientSample = undefined;
    for (&ambient_samples) |*sample| {
        sample.* = .{
            .sample = try reader.readInt(i16),
            .repeat = try reader.readInt(i16),
            .random_delay = try reader.readInt(i16),
            .frequency = try reader.readInt(i16),
            .volume = try reader.readInt(i16),
        };
    }

    const second_min = try reader.readInt(i16);
    const second_ecart = try reader.readInt(i16);
    const cube_jingle = try reader.readInt(u8);

    const hero_start = HeroStart{
        .x = try reader.readInt(i16),
        .y = try reader.readInt(i16),
        .z = try reader.readInt(i16),
        .track_byte_length = try reader.readInt(u16),
        .life_byte_length = undefined,
    };
    try reader.skip(hero_start.track_byte_length);
    var hero = hero_start;
    hero.life_byte_length = try reader.readInt(u16);
    try reader.skip(hero.life_byte_length);

    const object_count = try reader.readInt(u16);
    if (object_count == 0) return error.InvalidSceneObjectCount;

    const objects = try allocator.alloc(SceneObject, object_count - 1);
    errdefer allocator.free(objects);

    for (objects, 1..) |*object, index| {
        const flags = try reader.readInt(u32);
        object.* = .{
            .index = index,
            .flags = flags,
            .file3d_index = try reader.readInt(i16),
            .gen_body = try reader.readInt(u8),
            .gen_anim = try reader.readInt(i16),
            .sprite = try reader.readInt(i16),
            .x = try reader.readInt(i16),
            .y = try reader.readInt(i16),
            .z = try reader.readInt(i16),
            .hit_force = try reader.readInt(u8),
            .option_flags = try reader.readInt(i16),
            .beta = try reader.readInt(i16),
            .speed_rotation = try reader.readInt(i16),
            .move = try reader.readInt(u8),
            .info = try reader.readInt(i16),
            .info1 = try reader.readInt(i16),
            .info2 = try reader.readInt(i16),
            .info3 = try reader.readInt(i16),
            .bonus_count = try reader.readInt(i16),
            .dominant_color = try reader.readInt(u8),
            .armor = 0,
            .life_points = 0,
            .track_byte_length = 0,
            .life_byte_length = 0,
            .anim_3ds_index = null,
            .anim_3ds_fps = null,
        };

        if ((flags & anim_3ds_flag) != 0) {
            object.anim_3ds_index = try reader.readInt(u32);
            object.anim_3ds_fps = try reader.readInt(i16);
        }

        object.armor = try reader.readInt(u8);
        object.life_points = try reader.readInt(u8);
        object.track_byte_length = try reader.readInt(u16);
        try reader.skip(object.track_byte_length);
        object.life_byte_length = try reader.readInt(u16);
        try reader.skip(object.life_byte_length);
    }

    const checksum = try reader.readInt(u32);
    const zone_count = try reader.readInt(u16);

    const zones = try allocator.alloc(SceneZone, zone_count);
    errdefer allocator.free(zones);
    for (zones) |*zone| {
        zone.* = .{
            .x0 = try reader.readInt(i32),
            .y0 = try reader.readInt(i32),
            .z0 = try reader.readInt(i32),
            .x1 = try reader.readInt(i32),
            .y1 = try reader.readInt(i32),
            .z1 = try reader.readInt(i32),
            .info0 = try reader.readInt(i32),
            .info1 = try reader.readInt(i32),
            .info2 = try reader.readInt(i32),
            .info3 = try reader.readInt(i32),
            .info4 = try reader.readInt(i32),
            .info5 = try reader.readInt(i32),
            .info6 = try reader.readInt(i32),
            .info7 = try reader.readInt(i32),
            .type_id = try reader.readInt(i16),
            .num = try reader.readInt(i16),
        };
    }

    const track_count = try reader.readInt(u16);
    const tracks = try allocator.alloc(TrackPoint, track_count);
    errdefer allocator.free(tracks);
    for (tracks, 0..) |*track, index| {
        track.* = .{
            .index = index,
            .x = try reader.readInt(i32),
            .y = try reader.readInt(i32),
            .z = try reader.readInt(i32),
        };
    }

    const patch_count = try reader.readInt(u32);
    const patches = try allocator.alloc(Patch, patch_count);
    errdefer allocator.free(patches);
    for (patches) |*patch| {
        patch.* = .{
            .size = try reader.readInt(i16),
            .offset = try reader.readInt(i16),
        };
    }

    if (reader.remaining() != 0) return error.TrailingScenePayloadBytes;

    return .{
        .entry_index = entry_index,
        .compressed_header = compressed_header,
        .island = island,
        .cube_x = cube_x,
        .cube_y = cube_y,
        .shadow_level = shadow_level,
        .mode_labyrinth = mode_labyrinth,
        .cube_mode = cube_mode,
        .unused_header_byte = unused_header_byte,
        .alpha_light = alpha_light,
        .beta_light = beta_light,
        .ambient_samples = ambient_samples,
        .second_min = second_min,
        .second_ecart = second_ecart,
        .cube_jingle = cube_jingle,
        .hero_start = hero,
        .checksum = checksum,
        .object_count = object_count,
        .zone_count = zone_count,
        .track_count = track_count,
        .patch_count = patch_count,
        .objects = objects,
        .zones = zones,
        .tracks = tracks,
        .patches = patches,
    };
}

const Reader = struct {
    bytes: []const u8,
    offset: usize = 0,

    fn readInt(self: *Reader, comptime T: type) !T {
        const size = @sizeOf(T);
        if (self.offset + size > self.bytes.len) return error.TruncatedScenePayload;
        const value = std.mem.readInt(T, self.bytes[self.offset .. self.offset + size][0..size], .little);
        self.offset += size;
        return value;
    }

    fn skip(self: *Reader, count: usize) !void {
        if (self.offset + count > self.bytes.len) return error.TruncatedScenePayload;
        self.offset += count;
    }

    fn remaining(self: Reader) usize {
        return self.bytes.len - self.offset;
    }
};

fn appendInt(list: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    var buffer: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buffer, value, .little);
    try list.appendSlice(std.testing.allocator, &buffer);
}

fn buildSyntheticScenePayload(allocator: std.mem.Allocator) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    try bytes.appendSlice(allocator, &.{ 0, 1, 2, 12, 0, 0, 0 });
    try appendInt(&bytes, @as(i16, 414));
    try appendInt(&bytes, @as(i16, 136));
    for (0..4) |_| {
        try appendInt(&bytes, @as(i16, -1));
        try appendInt(&bytes, @as(i16, 1));
        try appendInt(&bytes, @as(i16, 1));
        try appendInt(&bytes, @as(i16, 4096));
        try appendInt(&bytes, @as(i16, 110));
    }
    try appendInt(&bytes, @as(i16, 10));
    try appendInt(&bytes, @as(i16, 10));
    try bytes.append(allocator, 21);

    try appendInt(&bytes, @as(i16, 100));
    try appendInt(&bytes, @as(i16, 200));
    try appendInt(&bytes, @as(i16, 300));
    try appendInt(&bytes, @as(u16, 1));
    try bytes.append(allocator, 0x7F);
    try appendInt(&bytes, @as(u16, 2));
    try bytes.appendSlice(allocator, &.{ 0xAA, 0xBB });

    try appendInt(&bytes, @as(u16, 2));
    try appendInt(&bytes, @as(u32, 0x00001200));
    try appendInt(&bytes, @as(i16, 16));
    try bytes.append(allocator, 4);
    try appendInt(&bytes, @as(i16, 5));
    try appendInt(&bytes, @as(i16, 6));
    try appendInt(&bytes, @as(i16, 700));
    try appendInt(&bytes, @as(i16, 800));
    try appendInt(&bytes, @as(i16, 900));
    try bytes.append(allocator, 3);
    try appendInt(&bytes, @as(i16, 10));
    try appendInt(&bytes, @as(i16, 1024));
    try appendInt(&bytes, @as(i16, 40));
    try bytes.append(allocator, 7);
    try appendInt(&bytes, @as(i16, 11));
    try appendInt(&bytes, @as(i16, 12));
    try appendInt(&bytes, @as(i16, 13));
    try appendInt(&bytes, @as(i16, 14));
    try appendInt(&bytes, @as(i16, 15));
    try bytes.append(allocator, 9);
    try bytes.append(allocator, 2);
    try bytes.append(allocator, 100);
    try appendInt(&bytes, @as(u16, 1));
    try bytes.append(allocator, 0x01);
    try appendInt(&bytes, @as(u16, 1));
    try bytes.append(allocator, 0x02);

    try appendInt(&bytes, @as(u32, 0x12345678));
    try appendInt(&bytes, @as(u16, 1));
    try appendInt(&bytes, @as(i32, 10));
    try appendInt(&bytes, @as(i32, 20));
    try appendInt(&bytes, @as(i32, 30));
    try appendInt(&bytes, @as(i32, 40));
    try appendInt(&bytes, @as(i32, 50));
    try appendInt(&bytes, @as(i32, 60));
    try appendInt(&bytes, @as(i32, 70));
    try appendInt(&bytes, @as(i32, 71));
    try appendInt(&bytes, @as(i32, 72));
    try appendInt(&bytes, @as(i32, 73));
    try appendInt(&bytes, @as(i32, 74));
    try appendInt(&bytes, @as(i32, 75));
    try appendInt(&bytes, @as(i32, 76));
    try appendInt(&bytes, @as(i32, 77));
    try appendInt(&bytes, @as(i16, 5));
    try appendInt(&bytes, @as(i16, 6));

    try appendInt(&bytes, @as(u16, 2));
    try appendInt(&bytes, @as(i32, 1000));
    try appendInt(&bytes, @as(i32, 2000));
    try appendInt(&bytes, @as(i32, 3000));
    try appendInt(&bytes, @as(i32, 4000));
    try appendInt(&bytes, @as(i32, 5000));
    try appendInt(&bytes, @as(i32, 6000));

    try appendInt(&bytes, @as(u32, 1));
    try appendInt(&bytes, @as(i16, 2));
    try appendInt(&bytes, @as(i16, 99));

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

test "scene payload parsing follows the classic loader layout" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticScenePayload(allocator);
    defer allocator.free(payload);

    const metadata = try parseScenePayload(allocator, 7, .{
        .size_file = @intCast(payload.len),
        .compressed_size_file = @intCast(payload.len),
        .compress_method = 0,
    }, payload);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 7), metadata.entry_index);
    try std.testing.expectEqual(@as(u8, 0), metadata.island);
    try std.testing.expectEqual(@as(i16, 414), metadata.alpha_light);
    try std.testing.expectEqual(@as(u16, 2), metadata.hero_start.life_byte_length);
    try std.testing.expectEqual(@as(usize, 2), metadata.object_count);
    try std.testing.expectEqual(@as(usize, 1), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 2), metadata.track_count);
    try std.testing.expectEqual(@as(usize, 1), metadata.patch_count);
    try std.testing.expectEqual(@as(i16, 700), metadata.objects[0].x);
    try std.testing.expectEqual(@as(i16, 5), metadata.zones[0].type_id);
    try std.testing.expectEqual(@as(i32, 6000), metadata.tracks[1].z);
    try std.testing.expectEqual(@as(i16, 99), metadata.patches[0].offset);
}

test "real scene 2 metadata matches canonical asset bytes" {
    const allocator = std.testing.allocator;
    const target = try fixtureTargetById("interior-room-twinsens-house-scene");
    const archive_path = try resolveSceneArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const metadata = try loadSceneMetadata(allocator, archive_path, target.entry_index);
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
    try std.testing.expectEqual(@as(u16, 203), metadata.hero_start.life_byte_length);
    try std.testing.expectEqual(@as(usize, 9), metadata.object_count);
    try std.testing.expectEqual(@as(usize, 10), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 4), metadata.track_count);
    try std.testing.expectEqual(@as(usize, 4), metadata.patch_count);
    try std.testing.expectEqual(@as(u32, 34887), metadata.objects[0].flags);
    try std.testing.expectEqual(@as(i16, 14), metadata.objects[0].file3d_index);
    try std.testing.expectEqual(@as(u8, 7), metadata.objects[0].move);
    try std.testing.expectEqual(@as(i16, 0), metadata.zones[0].type_id);
    try std.testing.expectEqual(@as(i16, 284), metadata.zones[6].num);
    try std.testing.expectEqual(@as(i32, 10736), metadata.tracks[3].z);
    try std.testing.expectEqual(@as(i16, 521), metadata.patches[3].offset);
}

test "real scene 4 metadata stays aligned on a larger payload" {
    const allocator = std.testing.allocator;
    const target = try fixtureTargetById("exterior-area-citadel-cliffs-scene");
    const archive_path = try resolveSceneArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const metadata = try loadSceneMetadata(allocator, archive_path, target.entry_index);
    defer metadata.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4), metadata.entry_index);
    try std.testing.expectEqual(@as(u32, 8389), metadata.compressed_header.size_file);
    try std.testing.expectEqual(@as(u32, 5716), metadata.compressed_header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 1), metadata.compressed_header.compress_method);
    try std.testing.expectEqual(@as(i16, 568), metadata.alpha_light);
    try std.testing.expectEqual(@as(i16, 4068), metadata.beta_light);
    try std.testing.expectEqual(@as(i16, 6619), metadata.hero_start.x);
    try std.testing.expectEqual(@as(i16, 15109), metadata.hero_start.z);
    try std.testing.expectEqual(@as(usize, 22), metadata.object_count);
    try std.testing.expectEqual(@as(usize, 13), metadata.zone_count);
    try std.testing.expectEqual(@as(usize, 35), metadata.track_count);
    try std.testing.expectEqual(@as(usize, 115), metadata.patch_count);
    try std.testing.expectEqual(@as(i16, 104), metadata.objects[1].sprite);
    try std.testing.expectEqual(@as(i16, 4), metadata.zones[1].num);
    try std.testing.expectEqual(@as(i32, 10960), metadata.tracks[34].z);
    try std.testing.expectEqual(@as(i16, 6523), metadata.patches[114].offset);
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
        parseScenePayload(allocator, 7, .{
            .size_file = @intCast(padded.len),
            .compressed_size_file = @intCast(padded.len),
            .compress_method = 0,
        }, padded),
    );
}

test "scene payload rejects truncated bytes" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticScenePayload(allocator);
    defer allocator.free(payload);

    try std.testing.expectError(
        error.TruncatedScenePayload,
        parseScenePayload(allocator, 7, .{
            .size_file = @intCast(payload.len - 1),
            .compressed_size_file = @intCast(payload.len - 1),
            .compress_method = 0,
        }, payload[0 .. payload.len - 1]),
    );
}

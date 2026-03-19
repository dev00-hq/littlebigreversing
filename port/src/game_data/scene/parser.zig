const std = @import("std");
const hqr = @import("../../assets/hqr.zig");
const model = @import("model.zig");
const zones = @import("zones.zig");

const anim_3ds_flag = 1 << 18;

pub fn loadSceneMetadata(allocator: std.mem.Allocator, absolute_path: []const u8, entry_index: usize) !model.SceneMetadata {
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
) !model.SceneMetadata {
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

    var ambient_samples: [4]model.AmbientSample = undefined;
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

    const hero_start = model.HeroStart{
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

    const objects = try allocator.alloc(model.SceneObject, object_count - 1);
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

    const decoded_zones = try allocator.alloc(zones.SceneZone, zone_count);
    errdefer allocator.free(decoded_zones);
    for (decoded_zones) |*zone| {
        const raw_zone = zones.RawSceneZone{
            .x0 = try reader.readInt(i32),
            .y0 = try reader.readInt(i32),
            .z0 = try reader.readInt(i32),
            .x1 = try reader.readInt(i32),
            .y1 = try reader.readInt(i32),
            .z1 = try reader.readInt(i32),
            .raw_info = .{
                try reader.readInt(i32),
                try reader.readInt(i32),
                try reader.readInt(i32),
                try reader.readInt(i32),
                try reader.readInt(i32),
                try reader.readInt(i32),
                try reader.readInt(i32),
                try reader.readInt(i32),
            },
            .type_id = try reader.readInt(i16),
            .num = try reader.readInt(i16),
        };
        zone.* = try zones.decodeZone(raw_zone, cube_mode);
    }

    const track_count = try reader.readInt(u16);
    const tracks = try allocator.alloc(model.TrackPoint, track_count);
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
    const patches = try allocator.alloc(model.Patch, patch_count);
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
        .zones = decoded_zones,
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

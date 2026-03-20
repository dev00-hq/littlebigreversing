const std = @import("std");
const hqr = @import("../../assets/hqr.zig");
const model = @import("model.zig");
const track_program = @import("track_program.zig");
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

    const hero_x = try reader.readInt(i16);
    const hero_y = try reader.readInt(i16);
    const hero_z = try reader.readInt(i16);
    const hero_track = try reader.readProgramBlob(allocator);
    errdefer hero_track.deinit(allocator);
    const hero_track_instructions = try track_program.decodeTrackProgram(allocator, hero_track.bytes);
    errdefer allocator.free(hero_track_instructions);
    const hero_life = try reader.readProgramBlob(allocator);
    errdefer hero_life.deinit(allocator);

    const hero_start = model.HeroStart{
        .x = hero_x,
        .y = hero_y,
        .z = hero_z,
        .track = hero_track,
        .track_instructions = hero_track_instructions,
        .life = hero_life,
    };

    const object_count = try reader.readInt(u16);
    if (object_count == 0) return error.InvalidSceneObjectCount;

    const objects = try allocator.alloc(model.SceneObject, object_count - 1);
    var parsed_object_count: usize = 0;
    errdefer {
        for (objects[0..parsed_object_count]) |object| object.deinit(allocator);
        allocator.free(objects);
    }

    for (objects, 1..) |*object, index| {
        const flags = try reader.readInt(u32);
        var anim_3ds_index: ?u32 = null;
        var anim_3ds_fps: ?i16 = null;

        const file3d_index = try reader.readInt(i16);
        const gen_body = try reader.readInt(u8);
        const gen_anim = try reader.readInt(i16);
        const sprite = try reader.readInt(i16);
        const x = try reader.readInt(i16);
        const y = try reader.readInt(i16);
        const z = try reader.readInt(i16);
        const hit_force = try reader.readInt(u8);
        const option_flags = try reader.readInt(i16);
        const beta = try reader.readInt(i16);
        const speed_rotation = try reader.readInt(i16);
        const move = try reader.readInt(u8);
        const info = try reader.readInt(i16);
        const info1 = try reader.readInt(i16);
        const info2 = try reader.readInt(i16);
        const info3 = try reader.readInt(i16);
        const bonus_count = try reader.readInt(i16);
        const dominant_color = try reader.readInt(u8);

        if ((flags & anim_3ds_flag) != 0) {
            anim_3ds_index = try reader.readInt(u32);
            anim_3ds_fps = try reader.readInt(i16);
        }

        const armor = try reader.readInt(u8);
        const life_points = try reader.readInt(u8);
        const track = try reader.readProgramBlob(allocator);
        errdefer track.deinit(allocator);
        const track_instructions = try track_program.decodeTrackProgram(allocator, track.bytes);
        errdefer allocator.free(track_instructions);
        const life = try reader.readProgramBlob(allocator);
        errdefer life.deinit(allocator);

        object.* = .{
            .index = index,
            .flags = flags,
            .file3d_index = file3d_index,
            .gen_body = gen_body,
            .gen_anim = gen_anim,
            .sprite = sprite,
            .x = x,
            .y = y,
            .z = z,
            .hit_force = hit_force,
            .option_flags = option_flags,
            .beta = beta,
            .speed_rotation = speed_rotation,
            .move = move,
            .info = info,
            .info1 = info1,
            .info2 = info2,
            .info3 = info3,
            .bonus_count = bonus_count,
            .dominant_color = dominant_color,
            .armor = armor,
            .life_points = life_points,
            .track = track,
            .track_instructions = track_instructions,
            .life = life,
            .anim_3ds_index = anim_3ds_index,
            .anim_3ds_fps = anim_3ds_fps,
        };
        parsed_object_count += 1;
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
        .hero_start = hero_start,
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

    fn readProgramBlob(self: *Reader, allocator: std.mem.Allocator) !model.SceneProgramBlob {
        const byte_length = try self.readInt(u16);
        if (self.offset + byte_length > self.bytes.len) return error.TruncatedScenePayload;

        const bytes = try allocator.alloc(u8, byte_length);
        errdefer allocator.free(bytes);
        @memcpy(bytes, self.bytes[self.offset .. self.offset + byte_length]);
        self.offset += byte_length;

        return .{ .bytes = bytes };
    }

    fn remaining(self: Reader) usize {
        return self.bytes.len - self.offset;
    }
};

const std = @import("std");
const hqr = @import("../../assets/hqr.zig");
const zones = @import("zones.zig");

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
    zones: []zones.SceneZone,
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

    pub fn classicLoaderSceneNumber(self: SceneMetadata) ?usize {
        return entryIndexToClassicLoaderSceneNumber(self.entry_index);
    }
};

pub fn entryIndexToClassicLoaderSceneNumber(entry_index: usize) ?usize {
    if (entry_index <= 1) return null;
    return entry_index - 2;
}

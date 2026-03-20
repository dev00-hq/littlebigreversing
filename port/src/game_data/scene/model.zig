const std = @import("std");
const hqr = @import("../../assets/hqr.zig");
const track_program = @import("track_program.zig");
const zones = @import("zones.zig");

pub const AmbientSample = struct {
    sample: i16,
    repeat: i16,
    random_delay: i16,
    frequency: i16,
    volume: i16,
};

pub const SceneProgramBlob = struct {
    bytes: []u8,

    pub fn deinit(self: SceneProgramBlob, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
    }

    pub fn byteLength(self: SceneProgramBlob) u16 {
        return std.math.cast(u16, self.bytes.len) orelse unreachable;
    }
};

pub const TrackOpcode = track_program.TrackOpcode;
pub const TrackInstruction = track_program.TrackInstruction;

fn writeProgramBytesJson(jw: anytype, bytes: []const u8) !void {
    try jw.beginArray();
    for (bytes) |byte| {
        try jw.write(byte);
    }
    try jw.endArray();
}

fn writeTrackInstructionsJson(jw: anytype, instructions: []const TrackInstruction) !void {
    try jw.beginArray();
    for (instructions) |instruction| {
        try jw.write(instruction);
    }
    try jw.endArray();
}

pub const HeroStart = struct {
    x: i16,
    y: i16,
    z: i16,
    track: SceneProgramBlob,
    track_instructions: []TrackInstruction,
    life: SceneProgramBlob,

    pub fn deinit(self: HeroStart, allocator: std.mem.Allocator) void {
        allocator.free(self.track_instructions);
        self.track.deinit(allocator);
        self.life.deinit(allocator);
    }

    pub fn trackByteLength(self: HeroStart) u16 {
        return self.track.byteLength();
    }

    pub fn lifeByteLength(self: HeroStart) u16 {
        return self.life.byteLength();
    }

    pub fn jsonStringify(self: HeroStart, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("x");
        try jw.write(self.x);
        try jw.objectField("y");
        try jw.write(self.y);
        try jw.objectField("z");
        try jw.write(self.z);
        try jw.objectField("track_byte_length");
        try jw.write(self.trackByteLength());
        try jw.objectField("track_bytes");
        try writeProgramBytesJson(jw, self.track.bytes);
        try jw.objectField("track_instructions");
        try writeTrackInstructionsJson(jw, self.track_instructions);
        try jw.objectField("life_byte_length");
        try jw.write(self.lifeByteLength());
        try jw.objectField("life_bytes");
        try writeProgramBytesJson(jw, self.life.bytes);
        try jw.endObject();
    }
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
    track: SceneProgramBlob,
    track_instructions: []TrackInstruction,
    life: SceneProgramBlob,
    anim_3ds_index: ?u32,
    anim_3ds_fps: ?i16,

    pub fn deinit(self: SceneObject, allocator: std.mem.Allocator) void {
        allocator.free(self.track_instructions);
        self.track.deinit(allocator);
        self.life.deinit(allocator);
    }

    pub fn trackByteLength(self: SceneObject) u16 {
        return self.track.byteLength();
    }

    pub fn lifeByteLength(self: SceneObject) u16 {
        return self.life.byteLength();
    }

    pub fn jsonStringify(self: SceneObject, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("index");
        try jw.write(self.index);
        try jw.objectField("flags");
        try jw.write(self.flags);
        try jw.objectField("file3d_index");
        try jw.write(self.file3d_index);
        try jw.objectField("gen_body");
        try jw.write(self.gen_body);
        try jw.objectField("gen_anim");
        try jw.write(self.gen_anim);
        try jw.objectField("sprite");
        try jw.write(self.sprite);
        try jw.objectField("x");
        try jw.write(self.x);
        try jw.objectField("y");
        try jw.write(self.y);
        try jw.objectField("z");
        try jw.write(self.z);
        try jw.objectField("hit_force");
        try jw.write(self.hit_force);
        try jw.objectField("option_flags");
        try jw.write(self.option_flags);
        try jw.objectField("beta");
        try jw.write(self.beta);
        try jw.objectField("speed_rotation");
        try jw.write(self.speed_rotation);
        try jw.objectField("move");
        try jw.write(self.move);
        try jw.objectField("info");
        try jw.write(self.info);
        try jw.objectField("info1");
        try jw.write(self.info1);
        try jw.objectField("info2");
        try jw.write(self.info2);
        try jw.objectField("info3");
        try jw.write(self.info3);
        try jw.objectField("bonus_count");
        try jw.write(self.bonus_count);
        try jw.objectField("dominant_color");
        try jw.write(self.dominant_color);
        try jw.objectField("armor");
        try jw.write(self.armor);
        try jw.objectField("life_points");
        try jw.write(self.life_points);
        try jw.objectField("track_byte_length");
        try jw.write(self.trackByteLength());
        try jw.objectField("track_bytes");
        try writeProgramBytesJson(jw, self.track.bytes);
        try jw.objectField("track_instructions");
        try writeTrackInstructionsJson(jw, self.track_instructions);
        try jw.objectField("life_byte_length");
        try jw.write(self.lifeByteLength());
        try jw.objectField("life_bytes");
        try writeProgramBytesJson(jw, self.life.bytes);
        try jw.objectField("anim_3ds_index");
        try jw.write(self.anim_3ds_index);
        try jw.objectField("anim_3ds_fps");
        try jw.write(self.anim_3ds_fps);
        try jw.endObject();
    }
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
        self.hero_start.deinit(allocator);
        for (self.objects) |object| object.deinit(allocator);
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

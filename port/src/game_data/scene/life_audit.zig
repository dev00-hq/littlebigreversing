const std = @import("std");
const life_program = @import("life_program.zig");
const parser = @import("parser.zig");

pub const canonical_scene_entry_indices = [_]usize{ 2, 5, 44 };

pub const LifeBlobOwner = union(enum) {
    hero: void,
    object: usize,
};

pub const SceneLifeProgramAudit = struct {
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    owner: LifeBlobOwner,
    life_byte_length: usize,
    instruction_count: usize,
    decoded_byte_length: usize,
    status: life_program.LifeProgramAuditStatus,
};

pub fn auditCanonicalSceneLifePrograms(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
) ![]SceneLifeProgramAudit {
    var audits: std.ArrayList(SceneLifeProgramAudit) = .empty;
    errdefer audits.deinit(allocator);

    for (canonical_scene_entry_indices) |entry_index| {
        try appendSceneLifeProgramAudits(allocator, &audits, scene_archive_path, entry_index);
    }

    return audits.toOwnedSlice(allocator);
}

fn appendSceneLifeProgramAudits(
    allocator: std.mem.Allocator,
    audits: *std.ArrayList(SceneLifeProgramAudit),
    scene_archive_path: []const u8,
    entry_index: usize,
) !void {
    const scene = try parser.loadSceneMetadata(allocator, scene_archive_path, entry_index);
    defer scene.deinit(allocator);

    try audits.append(allocator, .{
        .scene_entry_index = scene.entry_index,
        .classic_loader_scene_number = scene.classicLoaderSceneNumber(),
        .scene_kind = scene.sceneKind(),
        .owner = .{ .hero = {} },
        .life_byte_length = scene.hero_start.life.bytes.len,
        .instruction_count = 0,
        .decoded_byte_length = 0,
        .status = undefined,
    });
    audits.items[audits.items.len - 1] = buildLifeProgramAudit(
        scene.entry_index,
        scene.classicLoaderSceneNumber(),
        scene.sceneKind(),
        .{ .hero = {} },
        scene.hero_start.life.bytes,
    );

    for (scene.objects) |object| {
        try audits.append(allocator, buildLifeProgramAudit(
            scene.entry_index,
            scene.classicLoaderSceneNumber(),
            scene.sceneKind(),
            .{ .object = object.index },
            object.life.bytes,
        ));
    }
}

fn buildLifeProgramAudit(
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    owner: LifeBlobOwner,
    bytes: []const u8,
) SceneLifeProgramAudit {
    const audit = life_program.auditLifeProgram(bytes);
    return .{
        .scene_entry_index = scene_entry_index,
        .classic_loader_scene_number = classic_loader_scene_number,
        .scene_kind = scene_kind,
        .owner = owner,
        .life_byte_length = bytes.len,
        .instruction_count = audit.instruction_count,
        .decoded_byte_length = audit.decoded_byte_length,
        .status = audit.status,
    };
}

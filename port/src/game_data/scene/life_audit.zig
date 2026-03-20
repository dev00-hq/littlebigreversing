const std = @import("std");
const hqr = @import("../../assets/hqr.zig");
const life_program = @import("life_program.zig");
const parser = @import("parser.zig");

pub const canonical_scene_entry_indices = [_]usize{ 2, 5, 44 };

pub const AuditSceneSelection = union(enum) {
    canonical: void,
    explicit_entries: []const usize,
    all_scene_entries: void,
};

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

pub fn resolveSceneEntryIndicesAlloc(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
    selection: AuditSceneSelection,
) ![]usize {
    switch (selection) {
        .canonical => return allocator.dupe(usize, &canonical_scene_entry_indices),
        .explicit_entries => |scene_entry_indices| return allocator.dupe(usize, scene_entry_indices),
        .all_scene_entries => {
            const archive_entry_indices = try hqr.listNonEmptyEntryIndices(allocator, scene_archive_path);
            defer allocator.free(archive_entry_indices);

            var scene_entry_indices: std.ArrayList(usize) = .empty;
            errdefer scene_entry_indices.deinit(allocator);

            for (archive_entry_indices) |entry_index| {
                if (entry_index < 2) continue;
                try scene_entry_indices.append(allocator, entry_index);
            }

            return scene_entry_indices.toOwnedSlice(allocator);
        },
    }
}

pub fn auditSceneLifePrograms(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
    selection: AuditSceneSelection,
) ![]SceneLifeProgramAudit {
    const scene_entry_indices = try resolveSceneEntryIndicesAlloc(allocator, scene_archive_path, selection);
    defer allocator.free(scene_entry_indices);

    return auditSceneLifeProgramsForEntryIndices(allocator, scene_archive_path, scene_entry_indices);
}

pub fn auditCanonicalSceneLifePrograms(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
) ![]SceneLifeProgramAudit {
    return auditSceneLifeProgramsForEntryIndices(allocator, scene_archive_path, &canonical_scene_entry_indices);
}

pub fn auditSelectedSceneLifePrograms(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
    scene_entry_indices: []const usize,
) ![]SceneLifeProgramAudit {
    return auditSceneLifeProgramsForEntryIndices(allocator, scene_archive_path, scene_entry_indices);
}

pub fn auditAllSceneLifePrograms(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
) ![]SceneLifeProgramAudit {
    return auditSceneLifePrograms(allocator, scene_archive_path, .{ .all_scene_entries = {} });
}

pub fn auditSceneLifeProgramsForEntryIndices(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
    scene_entry_indices: []const usize,
) ![]SceneLifeProgramAudit {
    var audits: std.ArrayList(SceneLifeProgramAudit) = .empty;
    errdefer audits.deinit(allocator);

    for (scene_entry_indices) |entry_index| {
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

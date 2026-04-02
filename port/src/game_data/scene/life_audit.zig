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

pub const UnsupportedSceneLifeHit = struct {
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    owner: LifeBlobOwner,
    unsupported_opcode_mnemonic: []const u8,
    unsupported_opcode_id: u8,
    byte_offset: usize,
};

pub const SceneLifeValidationResult = union(enum) {
    decoded: void,
    unsupported_life_blob: UnsupportedSceneLifeHit,
};

pub const DecodedInteriorSceneCandidate = struct {
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    blob_count: usize,
};

pub fn inspectSceneLifeProgram(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
    scene_entry_index: usize,
    owner: LifeBlobOwner,
) !SceneLifeProgramAudit {
    if (scene_entry_index < 2) return error.InvalidSceneEntryIndex;

    const scene = parser.loadSceneMetadata(allocator, scene_archive_path, scene_entry_index) catch |err| switch (err) {
        error.EntryIndexOutOfRange => return error.UnknownSceneEntryIndex,
        else => return err,
    };
    defer scene.deinit(allocator);

    return buildSceneLifeProgramAudit(scene, owner);
}

pub fn validateSceneLifeBoundaryForEntry(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
    scene_entry_index: usize,
) !SceneLifeValidationResult {
    if (scene_entry_index < 2) return error.InvalidSceneEntryIndex;

    const scene = parser.loadSceneMetadata(allocator, scene_archive_path, scene_entry_index) catch |err| switch (err) {
        error.EntryIndexOutOfRange => return error.UnknownSceneEntryIndex,
        else => return err,
    };
    defer scene.deinit(allocator);

    return validateSceneLifeBoundary(scene);
}

pub fn validateSceneLifeBoundary(scene: anytype) !SceneLifeValidationResult {
    const hero_audit = try buildSceneLifeProgramAudit(scene, .{ .hero = {} });
    switch (hero_audit.status) {
        .decoded => {},
        .unsupported_opcode => return .{ .unsupported_life_blob = buildUnsupportedSceneLifeHit(hero_audit) },
        else => return error.UnexpectedSceneLifeAuditStatus,
    }

    for (scene.objects) |object| {
        const object_audit = try buildSceneLifeProgramAudit(scene, .{ .object = object.index });
        switch (object_audit.status) {
            .decoded => {},
            .unsupported_opcode => return .{ .unsupported_life_blob = buildUnsupportedSceneLifeHit(object_audit) },
            else => return error.UnexpectedSceneLifeAuditStatus,
        }
    }

    return .{ .decoded = {} };
}

pub fn listDecodedInteriorSceneCandidates(
    allocator: std.mem.Allocator,
    scene_archive_path: []const u8,
) ![]DecodedInteriorSceneCandidate {
    const audits = try auditAllSceneLifePrograms(allocator, scene_archive_path);
    defer allocator.free(audits);

    var candidates: std.ArrayList(DecodedInteriorSceneCandidate) = .empty;
    errdefer candidates.deinit(allocator);

    var index: usize = 0;
    while (index < audits.len) {
        const scene_entry_index = audits[index].scene_entry_index;
        const classic_loader_scene_number = audits[index].classic_loader_scene_number;
        const scene_kind = audits[index].scene_kind;
        var blob_count: usize = 0;
        var all_decoded = true;

        while (index < audits.len and audits[index].scene_entry_index == scene_entry_index) : (index += 1) {
            blob_count += 1;
            if (audits[index].status != .decoded) all_decoded = false;
        }

        if (std.mem.eql(u8, scene_kind, "interior") and all_decoded) {
            try candidates.append(allocator, .{
                .scene_entry_index = scene_entry_index,
                .classic_loader_scene_number = classic_loader_scene_number,
                .blob_count = blob_count,
            });
        }
    }

    std.mem.sort(DecodedInteriorSceneCandidate, candidates.items, {}, struct {
        fn lessThan(_: void, lhs: DecodedInteriorSceneCandidate, rhs: DecodedInteriorSceneCandidate) bool {
            return lhs.scene_entry_index < rhs.scene_entry_index;
        }
    }.lessThan);

    return candidates.toOwnedSlice(allocator);
}

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

    try audits.append(allocator, try buildSceneLifeProgramAudit(scene, .{ .hero = {} }));

    for (scene.objects) |object| {
        try audits.append(allocator, try buildSceneLifeProgramAudit(scene, .{ .object = object.index }));
    }
}

fn buildSceneLifeProgramAudit(
    scene: anytype,
    owner: LifeBlobOwner,
) !SceneLifeProgramAudit {
    const bytes = switch (owner) {
        .hero => scene.hero_start.life.bytes,
        .object => |object_index| blk: {
            for (scene.objects) |object| {
                if (object.index == object_index) break :blk object.life.bytes;
            }
            return error.UnknownSceneObjectIndex;
        },
    };

    return buildLifeProgramAudit(
        scene.entry_index,
        scene.classicLoaderSceneNumber(),
        scene.sceneKind(),
        owner,
        bytes,
    );
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

fn buildUnsupportedSceneLifeHit(audit: SceneLifeProgramAudit) UnsupportedSceneLifeHit {
    const unsupported = audit.status.unsupported_opcode;
    return .{
        .scene_entry_index = audit.scene_entry_index,
        .classic_loader_scene_number = audit.classic_loader_scene_number,
        .scene_kind = audit.scene_kind,
        .owner = audit.owner,
        .unsupported_opcode_mnemonic = unsupported.opcode.mnemonic(),
        .unsupported_opcode_id = unsupported.opcode_id,
        .byte_offset = unsupported.offset,
    };
}

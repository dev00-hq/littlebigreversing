const std = @import("std");
const life_audit = @import("../life_audit.zig");
const support = @import("support.zig");

test "scene-level life validation pins the canonical decoded interior candidate set" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const candidates = try life_audit.listDecodedInteriorSceneCandidates(allocator, archive_path);
    defer allocator.free(candidates);

    try std.testing.expectEqual(@as(usize, 50), candidates.len);
    try std.testing.expectEqual(@as(usize, 19), candidates[0].scene_entry_index);
    try std.testing.expectEqual(@as(?usize, 17), candidates[0].classic_loader_scene_number);
    try std.testing.expectEqual(@as(usize, 3), candidates[0].blob_count);

    const validation = try life_audit.validateSceneLifeBoundaryForEntry(allocator, archive_path, candidates[0].scene_entry_index);
    try std.testing.expect(validation == .decoded);
}

test "decoded interior candidate ranking pins the current scene 19 comparison" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const ranked = try life_audit.rankDecodedInteriorSceneCandidates(allocator, archive_path);
    defer allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 50), ranked.len);
    try std.testing.expectEqualStrings("track_count_desc", life_audit.ranked_decoded_interior_scene_candidate_basis[0]);
    try std.testing.expectEqualStrings("scene_entry_index_asc", life_audit.ranked_decoded_interior_scene_candidate_basis[4]);

    try std.testing.expectEqual(@as(usize, 219), ranked[0].scene_entry_index);
    try std.testing.expectEqual(@as(?usize, 217), ranked[0].classic_loader_scene_number);
    try std.testing.expectEqualStrings("interior", ranked[0].scene_kind);
    try std.testing.expectEqual(@as(usize, 34), ranked[0].blob_count);
    try std.testing.expectEqual(@as(usize, 34), ranked[0].object_count);
    try std.testing.expectEqual(@as(usize, 16), ranked[0].zone_count);
    try std.testing.expectEqual(@as(usize, 17), ranked[0].track_count);
    try std.testing.expectEqual(@as(usize, 42), ranked[0].patch_count);

    const baseline_index = life_audit.findRankedDecodedInteriorSceneCandidateIndex(ranked, 19) orelse return error.MissingScene19RankedCandidate;
    try std.testing.expectEqual(@as(usize, 48), baseline_index);
    try std.testing.expectEqual(@as(usize, 19), ranked[baseline_index].scene_entry_index);
    try std.testing.expectEqual(@as(?usize, 17), ranked[baseline_index].classic_loader_scene_number);
    try std.testing.expectEqual(@as(usize, 3), ranked[baseline_index].blob_count);
    try std.testing.expectEqual(@as(usize, 3), ranked[baseline_index].object_count);
    try std.testing.expectEqual(@as(usize, 4), ranked[baseline_index].zone_count);
    try std.testing.expectEqual(@as(usize, 0), ranked[baseline_index].track_count);
    try std.testing.expectEqual(@as(usize, 5), ranked[baseline_index].patch_count);
}

test "all-scene life audit selection skips the reserved header entry" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const scene_entry_indices = try life_audit.resolveSceneEntryIndicesAlloc(allocator, archive_path, .{ .all_scene_entries = {} });
    defer allocator.free(scene_entry_indices);

    try std.testing.expectEqual(@as(usize, 221), scene_entry_indices.len);
    try std.testing.expect(scene_entry_indices.len > life_audit.canonical_scene_entry_indices.len);
    try std.testing.expectEqual(@as(usize, 2), scene_entry_indices[0]);
    try std.testing.expectEqual(@as(usize, 222), scene_entry_indices[scene_entry_indices.len - 1]);

    var has_scene5 = false;
    var has_scene44 = false;
    for (scene_entry_indices) |entry_index| {
        if (entry_index == 1) return error.ReservedHeaderEntryShouldNotBeAudited;
        if (entry_index == 5) has_scene5 = true;
        if (entry_index == 44) has_scene44 = true;
    }

    try std.testing.expect(has_scene5);
    try std.testing.expect(has_scene44);
}

test "all-scene life audit pins the broader unsupported-opcode inventory" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const audits = try life_audit.auditAllSceneLifePrograms(allocator, archive_path);
    defer allocator.free(audits);

    var unsupported_count: usize = 0;
    var default_count: usize = 0;
    var end_switch_count: usize = 0;

    for (audits) |audit| {
        switch (audit.status) {
            .unsupported_opcode => |unsupported| {
                unsupported_count += 1;
                switch (unsupported.opcode) {
                    .LM_DEFAULT => default_count += 1,
                    .LM_END_SWITCH => end_switch_count += 1,
                    else => return error.UnexpectedUnsupportedOpcodeInAllSceneAudit,
                }
            },
            .decoded => {},
            else => return error.UnexpectedFailureStatusInAllSceneAudit,
        }
    }

    try std.testing.expectEqual(@as(usize, 3109), audits.len);
    try std.testing.expectEqual(@as(usize, 394), unsupported_count);
    try std.testing.expectEqual(@as(usize, 188), default_count);
    try std.testing.expectEqual(@as(usize, 206), end_switch_count);
}

test "all-scene life audit resolves a broader non-header scene set" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const scene_entry_indices = try life_audit.resolveSceneEntryIndicesAlloc(allocator, archive_path, .{ .all_scene_entries = {} });
    defer allocator.free(scene_entry_indices);

    try std.testing.expect(scene_entry_indices.len > life_audit.canonical_scene_entry_indices.len);
    try std.testing.expect(scene_entry_indices[0] >= 2);
    try std.testing.expect(std.mem.indexOfScalar(usize, scene_entry_indices, 2) != null);
    try std.testing.expect(std.mem.indexOfScalar(usize, scene_entry_indices, 44) != null);
    try std.testing.expect(std.mem.indexOfScalar(usize, scene_entry_indices, 1) == null);
}

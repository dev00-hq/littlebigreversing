const std = @import("std");
const life_audit = @import("../life_audit.zig");
const life_program = @import("../life_program.zig");
const support = @import("support.zig");

test "canonical life audit pins the known scene 2 hero blocker and scene 2 object 5 success" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const audits = try life_audit.auditCanonicalSceneLifePrograms(allocator, archive_path);
    defer allocator.free(audits);

    var scene2_hero: ?life_audit.SceneLifeProgramAudit = null;
    var scene2_object5: ?life_audit.SceneLifeProgramAudit = null;

    for (audits) |audit| {
        if (audit.scene_entry_index != 2) continue;
        switch (audit.owner) {
            .hero => scene2_hero = audit,
            .object => |object_index| {
                if (object_index == 5) scene2_object5 = audit;
            },
        }
    }

    const hero_audit = scene2_hero orelse return error.MissingScene2HeroAudit;
    const object5_audit = scene2_object5 orelse return error.MissingScene2Object5Audit;

    try std.testing.expectEqual(@as(usize, 203), hero_audit.life_byte_length);
    try std.testing.expectEqual(@as(usize, 36), hero_audit.instruction_count);
    try std.testing.expectEqual(@as(usize, 170), hero_audit.decoded_byte_length);
    try std.testing.expectEqual(life_program.LifeOpcode.LM_DEFAULT, hero_audit.status.unsupported_opcode.opcode);
    try std.testing.expectEqual(@as(u8, 116), hero_audit.status.unsupported_opcode.opcode_id);
    try std.testing.expectEqual(@as(usize, 170), hero_audit.status.unsupported_opcode.offset);

    try std.testing.expectEqual(@as(usize, 51), object5_audit.life_byte_length);
    try std.testing.expect(object5_audit.status == .decoded);
    try std.testing.expectEqual(@as(usize, 14), object5_audit.instruction_count);
    try std.testing.expectEqual(object5_audit.life_byte_length, object5_audit.decoded_byte_length);
}

test "canonical life audit covers the locked scene set" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const audits = try life_audit.auditCanonicalSceneLifePrograms(allocator, archive_path);
    defer allocator.free(audits);

    var has_scene2 = false;
    var has_scene5 = false;
    var has_scene44 = false;
    var has_scene5_hero_end_switch = false;
    var has_scene5_object2_success = false;
    var has_scene44_hero_end_switch = false;
    var has_scene44_object2_default = false;
    var unsupported_count: usize = 0;

    for (audits) |audit| {
        if (audit.scene_entry_index == 2) has_scene2 = true;
        if (audit.scene_entry_index == 5) has_scene5 = true;
        if (audit.scene_entry_index == 44) has_scene44 = true;
        if (audit.status == .unsupported_opcode) {
            unsupported_count += 1;
            switch (audit.owner) {
                .hero => {
                    if (audit.scene_entry_index == 5 and audit.status.unsupported_opcode.opcode == .LM_END_SWITCH and audit.status.unsupported_opcode.offset == 46) {
                        has_scene5_hero_end_switch = true;
                    }
                    if (audit.scene_entry_index == 44 and audit.status.unsupported_opcode.opcode == .LM_END_SWITCH and audit.status.unsupported_opcode.offset == 713) {
                        has_scene44_hero_end_switch = true;
                    }
                },
                .object => |object_index| {
                    if (audit.scene_entry_index == 5 and object_index == 2 and audit.status == .decoded and audit.instruction_count == 51 and audit.decoded_byte_length == 194) {
                        has_scene5_object2_success = true;
                    }
                    if (audit.scene_entry_index == 44 and object_index == 2 and audit.status.unsupported_opcode.opcode == .LM_DEFAULT and audit.status.unsupported_opcode.offset == 274) {
                        has_scene44_object2_default = true;
                    }
                },
            }
        } else if (audit.scene_entry_index == 5) {
            switch (audit.owner) {
                .hero => {},
                .object => |object_index| {
                    if (object_index == 2 and audit.instruction_count == 51 and audit.decoded_byte_length == 194) {
                        has_scene5_object2_success = true;
                    }
                },
            }
        }
    }

    try std.testing.expectEqual(@as(usize, 36), audits.len);
    try std.testing.expect(has_scene2);
    try std.testing.expect(has_scene5);
    try std.testing.expect(has_scene44);
    try std.testing.expectEqual(@as(usize, 5), unsupported_count);
    try std.testing.expect(has_scene5_hero_end_switch);
    try std.testing.expect(has_scene5_object2_success);
    try std.testing.expect(has_scene44_hero_end_switch);
    try std.testing.expect(has_scene44_object2_default);
}

test "explicit life audit selection limits auditing to the requested scene entries" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const audits = try life_audit.auditSelectedSceneLifePrograms(allocator, archive_path, &.{5});
    defer allocator.free(audits);

    try std.testing.expect(audits.len > 0);

    var has_hero_end_switch = false;
    var has_object2_success = false;
    for (audits) |audit| {
        try std.testing.expectEqual(@as(usize, 5), audit.scene_entry_index);
        switch (audit.owner) {
            .hero => {
                if (audit.status == .unsupported_opcode and audit.status.unsupported_opcode.opcode == .LM_END_SWITCH and audit.status.unsupported_opcode.offset == 46) {
                    has_hero_end_switch = true;
                }
            },
            .object => |object_index| {
                if (object_index == 2 and audit.status == .decoded and audit.instruction_count == 51 and audit.decoded_byte_length == 194) {
                    has_object2_success = true;
                }
            },
        }
    }

    try std.testing.expect(has_hero_end_switch);
    try std.testing.expect(has_object2_success);
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

test "selected life audit honors explicit scene-entry lists" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const audits = try life_audit.auditSelectedSceneLifePrograms(allocator, archive_path, &.{44});
    defer allocator.free(audits);

    var has_hero_end_switch = false;
    var has_object2_default = false;

    for (audits) |audit| {
        try std.testing.expectEqual(@as(usize, 44), audit.scene_entry_index);
        switch (audit.owner) {
            .hero => {
                if (audit.status == .unsupported_opcode and audit.status.unsupported_opcode.opcode == .LM_END_SWITCH and audit.status.unsupported_opcode.offset == 713) {
                    has_hero_end_switch = true;
                }
            },
            .object => |object_index| {
                if (object_index == 2 and audit.status == .unsupported_opcode and audit.status.unsupported_opcode.opcode == .LM_DEFAULT and audit.status.unsupported_opcode.offset == 274) {
                    has_object2_default = true;
                }
            },
        }
    }

    try std.testing.expect(audits.len > 1);
    try std.testing.expect(has_hero_end_switch);
    try std.testing.expect(has_object2_default);
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

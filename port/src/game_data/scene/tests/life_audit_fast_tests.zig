const std = @import("std");
const life_audit = @import("../life_audit.zig");
const support = @import("support.zig");

test "canonical life audit now decodes the former scene 2 hero blocker and keeps scene 2 object 5 stable" {
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
    try std.testing.expect(hero_audit.status == .decoded);
    try std.testing.expectEqual(@as(usize, 47), hero_audit.instruction_count);
    try std.testing.expectEqual(hero_audit.life_byte_length, hero_audit.decoded_byte_length);

    try std.testing.expectEqual(@as(usize, 51), object5_audit.life_byte_length);
    try std.testing.expect(object5_audit.status == .decoded);
    try std.testing.expectEqual(@as(usize, 14), object5_audit.instruction_count);
    try std.testing.expectEqual(object5_audit.life_byte_length, object5_audit.decoded_byte_length);
}

test "single-blob life inspection now decodes the former switch-family blocker anchors" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const scene2_hero = try life_audit.inspectSceneLifeProgram(allocator, archive_path, 2, .{ .hero = {} });
    try std.testing.expectEqual(@as(usize, 203), scene2_hero.life_byte_length);
    try std.testing.expect(scene2_hero.status == .decoded);
    try std.testing.expectEqual(@as(usize, 47), scene2_hero.instruction_count);
    try std.testing.expectEqual(scene2_hero.life_byte_length, scene2_hero.decoded_byte_length);

    const scene5_hero = try life_audit.inspectSceneLifeProgram(allocator, archive_path, 5, .{ .hero = {} });
    try std.testing.expect(scene5_hero.status == .decoded);
    try std.testing.expectEqual(@as(usize, 20), scene5_hero.instruction_count);
    try std.testing.expectEqual(scene5_hero.life_byte_length, scene5_hero.decoded_byte_length);

    const scene44_hero = try life_audit.inspectSceneLifeProgram(allocator, archive_path, 44, .{ .hero = {} });
    try std.testing.expect(scene44_hero.status == .decoded);
    try std.testing.expectEqual(@as(usize, 197), scene44_hero.instruction_count);
    try std.testing.expectEqual(scene44_hero.life_byte_length, scene44_hero.decoded_byte_length);

    const scene44_object2 = try life_audit.inspectSceneLifeProgram(allocator, archive_path, 44, .{ .object = 2 });
    try std.testing.expect(scene44_object2.status == .decoded);
    try std.testing.expectEqual(@as(usize, 87), scene44_object2.instruction_count);
    try std.testing.expectEqual(scene44_object2.life_byte_length, scene44_object2.decoded_byte_length);

    const scene44_object3 = try life_audit.inspectSceneLifeProgram(allocator, archive_path, 44, .{ .object = 3 });
    try std.testing.expect(scene44_object3.status == .decoded);
    try std.testing.expectEqual(@as(usize, 33), scene44_object3.instruction_count);
    try std.testing.expectEqual(scene44_object3.life_byte_length, scene44_object3.decoded_byte_length);

    const scene2_object5 = try life_audit.inspectSceneLifeProgram(allocator, archive_path, 2, .{ .object = 5 });
    try std.testing.expect(scene2_object5.status == .decoded);
    try std.testing.expectEqual(@as(usize, 14), scene2_object5.instruction_count);
    try std.testing.expectEqual(scene2_object5.life_byte_length, scene2_object5.decoded_byte_length);
}

test "single-blob life inspection rejects unknown selectors explicitly" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    try std.testing.expectError(error.UnknownSceneObjectIndex, life_audit.inspectSceneLifeProgram(allocator, archive_path, 2, .{ .object = 99 }));
    try std.testing.expectError(error.UnknownSceneEntryIndex, life_audit.inspectSceneLifeProgram(allocator, archive_path, 999, .{ .hero = {} }));
}

test "scene-level life validation now decodes the former guarded switch-family set" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    try std.testing.expect((try life_audit.validateSceneLifeBoundaryForEntry(allocator, archive_path, 2)) == .decoded);
    try std.testing.expect((try life_audit.validateSceneLifeBoundaryForEntry(allocator, archive_path, 44)) == .decoded);
    try std.testing.expect((try life_audit.validateSceneLifeBoundaryForEntry(allocator, archive_path, 11)) == .decoded);
}

test "scene 11 life audit now decodes the former guarded switch-family objects" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const scene11_object12 = try life_audit.inspectSceneLifeProgram(allocator, archive_path, 11, .{ .object = 12 });
    try std.testing.expect(scene11_object12.status == .decoded);
    try std.testing.expectEqual(@as(usize, 59), scene11_object12.instruction_count);
    try std.testing.expectEqual(scene11_object12.life_byte_length, scene11_object12.decoded_byte_length);

    const scene11_object18 = try life_audit.inspectSceneLifeProgram(allocator, archive_path, 11, .{ .object = 18 });
    try std.testing.expect(scene11_object18.status == .decoded);
    try std.testing.expectEqual(@as(usize, 33), scene11_object18.instruction_count);
    try std.testing.expectEqual(scene11_object18.life_byte_length, scene11_object18.decoded_byte_length);
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
    var has_scene5_hero_success = false;
    var has_scene5_object2_success = false;
    var has_scene44_hero_success = false;
    var has_scene44_object2_success = false;
    var unsupported_count: usize = 0;

    for (audits) |audit| {
        if (audit.scene_entry_index == 2) has_scene2 = true;
        if (audit.scene_entry_index == 5) has_scene5 = true;
        if (audit.scene_entry_index == 44) has_scene44 = true;
        if (audit.status == .unsupported_opcode) {
            unsupported_count += 1;
        } else if (audit.scene_entry_index == 5) {
            switch (audit.owner) {
                .hero => {
                    if (audit.instruction_count == 20 and audit.decoded_byte_length == 61) {
                        has_scene5_hero_success = true;
                    }
                },
                .object => |object_index| {
                    if (object_index == 2 and audit.instruction_count == 51 and audit.decoded_byte_length == 194) {
                        has_scene5_object2_success = true;
                    }
                },
            }
        } else if (audit.scene_entry_index == 44) {
            switch (audit.owner) {
                .hero => {
                    if (audit.instruction_count == 197 and audit.decoded_byte_length == 823) {
                        has_scene44_hero_success = true;
                    }
                },
                .object => |object_index| {
                    if (object_index == 2 and audit.instruction_count == 87 and audit.decoded_byte_length == 329) {
                        has_scene44_object2_success = true;
                    }
                },
            }
        }
    }

    try std.testing.expectEqual(@as(usize, 36), audits.len);
    try std.testing.expect(has_scene2);
    try std.testing.expect(has_scene5);
    try std.testing.expect(has_scene44);
    try std.testing.expectEqual(@as(usize, 0), unsupported_count);
    try std.testing.expect(has_scene5_hero_success);
    try std.testing.expect(has_scene5_object2_success);
    try std.testing.expect(has_scene44_hero_success);
    try std.testing.expect(has_scene44_object2_success);
}

test "explicit life audit selection limits auditing to the requested scene entries" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const audits = try life_audit.auditSelectedSceneLifePrograms(allocator, archive_path, &.{5});
    defer allocator.free(audits);

    try std.testing.expect(audits.len > 0);

    var has_hero_success = false;
    var has_object2_success = false;
    for (audits) |audit| {
        try std.testing.expectEqual(@as(usize, 5), audit.scene_entry_index);
        switch (audit.owner) {
            .hero => {
                if (audit.status == .decoded and audit.instruction_count == 20 and audit.decoded_byte_length == 61) {
                    has_hero_success = true;
                }
            },
            .object => |object_index| {
                if (object_index == 2 and audit.status == .decoded and audit.instruction_count == 51 and audit.decoded_byte_length == 194) {
                    has_object2_success = true;
                }
            },
        }
    }

    try std.testing.expect(has_hero_success);
    try std.testing.expect(has_object2_success);
}

test "selected life audit honors explicit scene-entry lists" {
    const allocator = std.testing.allocator;
    const archive_path = try support.resolveSceneArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(archive_path);

    const audits = try life_audit.auditSelectedSceneLifePrograms(allocator, archive_path, &.{44});
    defer allocator.free(audits);

    var has_hero_success = false;
    var has_object2_success = false;

    for (audits) |audit| {
        try std.testing.expectEqual(@as(usize, 44), audit.scene_entry_index);
        switch (audit.owner) {
            .hero => {
                if (audit.status == .decoded and audit.instruction_count == 197 and audit.decoded_byte_length == 823) {
                    has_hero_success = true;
                }
            },
            .object => |object_index| {
                if (object_index == 2 and audit.status == .decoded and audit.instruction_count == 87 and audit.decoded_byte_length == 329) {
                    has_object2_success = true;
                }
            },
        }
    }

    try std.testing.expect(audits.len > 1);
    try std.testing.expect(has_hero_success);
    try std.testing.expect(has_object2_success);
}

const std = @import("std");
const zones = @import("../zones.zig");
const support = @import("support.zig");

test "zone json stringify keeps the stable tooling shape" {
    const allocator = std.testing.allocator;
    const zone = try zones.decodeZone(support.makeRawZone(5, 431, .{ 12, 2, 1, 0, 0, 0, 15000, 1 }), 1);
    const json = try support.stringifyJsonAlloc(allocator, zone);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"zone_type\": \"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"num\": 431") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\": \"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"dialog_id\": 431") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"linked_camera_zone_id\": 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"facing_direction\": \"north\"") != null);
}

test "zone decoder normalizes source-backed load-time semantics" {
    const change_cube = try zones.decodeZone(support.makeRawZone(0, 42, .{ 17408, 256, 7680, 3, 9, 1, 1, 1 }), 0);
    try std.testing.expectEqual(zones.ZoneType.change_cube, change_cube.zone_type);
    try std.testing.expectEqual(@as(i32, 9), change_cube.raw_info[4]);
    try std.testing.expectEqual(@as(i16, 42), change_cube.semantics.change_cube.destination_cube);
    try std.testing.expect(change_cube.semantics.change_cube.test_brick);
    try std.testing.expect(change_cube.semantics.change_cube.dont_readjust_twinsen);
    try std.testing.expect(change_cube.semantics.change_cube.initially_on);

    const camera = try zones.decodeZone(support.makeRawZone(1, 7, .{ 2, 5, 19, 341, 3908, 0, 10500, 9 }), 1);
    try std.testing.expectEqual(zones.ZoneType.camera, camera.zone_type);
    try std.testing.expectEqual(@as(?i32, 341), camera.semantics.camera.alpha);
    try std.testing.expectEqual(@as(?i32, 3908), camera.semantics.camera.beta);
    try std.testing.expectEqual(@as(?i32, 0), camera.semantics.camera.gamma);
    try std.testing.expectEqual(@as(?i32, 10500), camera.semantics.camera.distance);
    try std.testing.expect(camera.semantics.camera.initially_on);
    try std.testing.expect(camera.semantics.camera.obligatory);

    const grm = try zones.decodeZone(support.makeRawZone(3, 5, .{ 12, 0, 1, 0, 0, 0, 0, 0 }), 0);
    try std.testing.expectEqual(@as(i32, 12), grm.semantics.grm.grm_index);
    try std.testing.expect(grm.semantics.grm.initially_on);

    const giver = try zones.decodeZone(support.makeRawZone(4, 0, .{ 112, 2, 99, 0, 0, 0, 0, 0 }), 0);
    try std.testing.expect(giver.semantics.giver.bonus_kinds.money);
    try std.testing.expect(giver.semantics.giver.bonus_kinds.life);
    try std.testing.expect(giver.semantics.giver.bonus_kinds.magic);
    try std.testing.expectEqual(@as(i32, 2), giver.semantics.giver.quantity);
    try std.testing.expect(!giver.semantics.giver.already_taken);

    const ladder = try zones.decodeZone(support.makeRawZone(6, 1, .{ 1, 0, 0, 0, 0, 0, 0, 0 }), 0);
    try std.testing.expect(ladder.semantics.ladder.enabled_on_load);

    const hit = try zones.decodeZone(support.makeRawZone(8, 1, .{ 0, 3, 9, 22, 0, 0, 0, 0 }), 0);
    try std.testing.expectEqual(@as(i32, 3), hit.semantics.hit.damage);
    try std.testing.expectEqual(@as(i32, 9), hit.semantics.hit.cooldown_raw_value);
    try std.testing.expectEqual(@as(i32, 0), hit.semantics.hit.initial_timer);

    const rail = try zones.decodeZone(support.makeRawZone(9, 2, .{ 1, 0, 0, 0, 0, 0, 0, 0 }), 0);
    try std.testing.expect(rail.semantics.rail.switch_state_on_load);
}

test "zone decoder rejects unsupported types and directions" {
    try std.testing.expectError(error.UnsupportedSceneZoneType, zones.decodeZone(support.makeRawZone(99, 0, .{ 0, 0, 0, 0, 0, 0, 0, 0 }), 0));
    try std.testing.expectError(error.UnsupportedSceneZoneMessageDirection, zones.decodeZone(support.makeRawZone(5, 0, .{ 12, 0, 3, 0, 0, 0, 0, 0 }), 0));
    try std.testing.expectError(error.UnsupportedSceneZoneEscalatorDirection, zones.decodeZone(support.makeRawZone(7, 0, .{ 0, 1, 3, 0, 0, 0, 0, 0 }), 0));
}

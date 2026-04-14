const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const room_state = @import("../runtime/room_state.zig");
const room_fixtures = @import("../testing/room_fixtures.zig");

test "inspect-room widened guarded admissions stay covered outside the fast shard" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const guarded_22 = try room_fixtures.guarded22();
    try std.testing.expectEqual(@as(usize, 2), guarded_22.scene.entry_index);
    try std.testing.expectEqualStrings("interior", guarded_22.scene.scene_kind);
    try std.testing.expectEqual(@as(usize, 2), guarded_22.background.entry_index);

    const guarded_1110 = try room_fixtures.guarded1110();
    try std.testing.expectEqual(@as(usize, 11), guarded_1110.scene.entry_index);
    try std.testing.expectEqualStrings("interior", guarded_1110.scene.scene_kind);
    try std.testing.expectEqual(@as(usize, 10), guarded_1110.background.entry_index);

    try std.testing.expectError(
        error.ViewerSceneMustBeInterior,
        room_state.loadRoomSnapshot(allocator, resolved, 44, 2),
    );
}

const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const viewer_shell = @import("viewer_shell.zig");

test "viewer argument parsing requires explicit scene and background entries" {
    const parsed = try viewer_shell.parseArgs(std.testing.allocator, &.{
        "--scene-entry",
        "2",
        "--background-entry",
        "2",
        "--asset-root",
        "D:/assets",
    });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), parsed.scene_entry);
    try std.testing.expectEqual(@as(usize, 2), parsed.background_entry);
    try std.testing.expectEqualStrings("D:/assets", parsed.asset_root_override.?);
}

test "viewer window title carries the canonical room metadata" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try viewer_shell.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    const title = try viewer_shell.formatWindowTitleZ(allocator, room);
    defer allocator.free(title);

    try std.testing.expect(std.mem.indexOf(u8, title, "scene=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "background=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "kind=interior") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "loader=17") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "hero=1987,512,3743") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "cube=19") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "gri=20(grm=2,bll=1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "grm=151") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "bll=180") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "fragments=0/0") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "blocks=73[1|2|3|4|5|7|...]") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "columns=64x64") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "comp=1246") != null);
}

const std = @import("std");
const diagnostics = @import("../foundation/diagnostics.zig");
const paths_mod = @import("../foundation/paths.zig");
const background_data = @import("../game_data/background.zig");
const scene_data = @import("../game_data/scene.zig");

pub const ParsedArgs = struct {
    asset_root_override: ?[]u8,
    scene_entry: usize,
    background_entry: usize,

    pub fn deinit(self: ParsedArgs, allocator: std.mem.Allocator) void {
        if (self.asset_root_override) |value| allocator.free(value);
    }
};

pub const HeroStartSnapshot = struct {
    x: i16,
    y: i16,
    z: i16,
};

pub const SceneSnapshot = struct {
    entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    hero_start: HeroStartSnapshot,
    object_count: usize,
    zone_count: usize,
    track_count: usize,
};

pub const BackgroundLinkageSnapshot = struct {
    remapped_cube_index: usize,
    gri_entry_index: usize,
    gri_my_grm: u8,
    grm_entry_index: usize,
    gri_my_bll: u8,
    bll_entry_index: usize,
};

pub const ColumnTableSnapshot = struct {
    width: usize,
    depth: usize,
    offset_count: usize,
    table_byte_length: usize,
    data_byte_length: usize,
    min_offset: u16,
    max_offset: u16,
};

pub const BackgroundSnapshot = struct {
    entry_index: usize,
    linkage: BackgroundLinkageSnapshot,
    used_block_ids: []u8,
    column_table: ColumnTableSnapshot,

    pub fn deinit(self: BackgroundSnapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.used_block_ids);
    }
};

pub const RoomSnapshot = struct {
    scene: SceneSnapshot,
    background: BackgroundSnapshot,

    pub fn deinit(self: RoomSnapshot, allocator: std.mem.Allocator) void {
        self.background.deinit(allocator);
    }
};

pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    var asset_root_override: ?[]u8 = null;
    errdefer if (asset_root_override) |value| allocator.free(value);

    var scene_entry: ?usize = null;
    var background_entry: ?usize = null;

    var index: usize = 0;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--asset-root")) {
            if (asset_root_override != null) return error.DuplicateAssetRootOverride;
            if (index + 1 >= args.len) return error.MissingAssetRoot;
            asset_root_override = try allocator.dupe(u8, args[index + 1]);
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--scene-entry")) {
            if (scene_entry != null) return error.DuplicateSceneEntry;
            if (index + 1 >= args.len) return error.MissingSceneEntry;
            scene_entry = try std.fmt.parseInt(usize, args[index + 1], 10);
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--background-entry")) {
            if (background_entry != null) return error.DuplicateBackgroundEntry;
            if (index + 1 >= args.len) return error.MissingBackgroundEntry;
            background_entry = try std.fmt.parseInt(usize, args[index + 1], 10);
            index += 2;
            continue;
        }
        return error.UnknownOption;
    }

    return .{
        .asset_root_override = asset_root_override,
        .scene_entry = scene_entry orelse return error.MissingSceneEntry,
        .background_entry = background_entry orelse return error.MissingBackgroundEntry,
    };
}

pub fn loadRoomSnapshot(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
) !RoomSnapshot {
    const scene_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(scene_path);

    var scene = try scene_data.loadSceneMetadata(allocator, scene_path, scene_entry_index);
    defer scene.deinit(allocator);
    if (scene.cube_mode != 0) return error.ViewerSceneMustBeInterior;

    const background_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "LBA_BKG.HQR" });
    defer allocator.free(background_path);

    const background = try background_data.loadBackgroundMetadata(allocator, background_path, background_entry_index);
    defer background.deinit(allocator);

    return .{
        .scene = .{
            .entry_index = scene.entry_index,
            .classic_loader_scene_number = scene.classicLoaderSceneNumber(),
            .scene_kind = scene.sceneKind(),
            .hero_start = .{
                .x = scene.hero_start.x,
                .y = scene.hero_start.y,
                .z = scene.hero_start.z,
            },
            .object_count = scene.object_count,
            .zone_count = scene.zone_count,
            .track_count = scene.track_count,
        },
        .background = .{
            .entry_index = background.entry_index,
            .linkage = .{
                .remapped_cube_index = background.remapped_cube_index,
                .gri_entry_index = background.gri_entry_index,
                .gri_my_grm = background.gri_header.my_grm,
                .grm_entry_index = background.grm_entry_index,
                .gri_my_bll = background.gri_header.my_bll,
                .bll_entry_index = background.bll_entry_index,
            },
            .used_block_ids = try allocator.dupe(u8, background.used_blocks.used_block_ids),
            .column_table = .{
                .width = background.column_table.width,
                .depth = background.column_table.depth,
                .offset_count = background.column_table.offset_count,
                .table_byte_length = background.column_table.table_byte_length,
                .data_byte_length = background.column_table.data_byte_length,
                .min_offset = background.column_table.min_offset,
                .max_offset = background.column_table.max_offset,
            },
        },
    };
}

pub fn printStartupDiagnostics(
    writer: anytype,
    resolved: paths_mod.ResolvedPaths,
    room: RoomSnapshot,
) !void {
    try diagnostics.printLine(writer, &.{
        .{ .key = "event", .value = "startup" },
        .{ .key = "repo_root", .value = resolved.repo_root },
        .{ .key = "asset_root", .value = resolved.asset_root },
        .{ .key = "work_root", .value = resolved.work_root },
    });
    try diagnostics.printLine(writer, &.{
        .{ .key = "event", .value = "room_snapshot" },
        .{ .key = "scene_kind", .value = room.scene.scene_kind },
    });
    try writer.print(
        "scene_entry_index={d} background_entry_index={d} classic_loader_scene_number={any} hero_x={d} hero_y={d} hero_z={d} object_count={d} zone_count={d} track_count={d}\n",
        .{
            room.scene.entry_index,
            room.background.entry_index,
            room.scene.classic_loader_scene_number,
            room.scene.hero_start.x,
            room.scene.hero_start.y,
            room.scene.hero_start.z,
            room.scene.object_count,
            room.scene.zone_count,
            room.scene.track_count,
        },
    );
    try writer.print(
        "remapped_cube_index={d} gri_entry_index={d} gri_my_grm={d} grm_entry_index={d} gri_my_bll={d} bll_entry_index={d}\n",
        .{
            room.background.linkage.remapped_cube_index,
            room.background.linkage.gri_entry_index,
            room.background.linkage.gri_my_grm,
            room.background.linkage.grm_entry_index,
            room.background.linkage.gri_my_bll,
            room.background.linkage.bll_entry_index,
        },
    );
    try writer.print(
        "column_table={d}x{d} offsets={d} table_bytes={d} min_offset={d} max_offset={d} data_bytes={d}\n",
        .{
            room.background.column_table.width,
            room.background.column_table.depth,
            room.background.column_table.offset_count,
            room.background.column_table.table_byte_length,
            room.background.column_table.min_offset,
            room.background.column_table.max_offset,
            room.background.column_table.data_byte_length,
        },
    );
    try printUsedBlockSummary(writer, room.background.used_block_ids);
}

pub fn formatWindowTitleZ(allocator: std.mem.Allocator, room: RoomSnapshot) ![:0]u8 {
    const used_blocks = try formatUsedBlockSummaryAlloc(allocator, room.background.used_block_ids, 6);
    defer allocator.free(used_blocks);

    const title = try std.fmt.allocPrint(
        allocator,
        "Little Big Adventure 2 viewer scene={d} background={d} kind={s} loader={any} hero={d},{d},{d} objects={d} zones={d} tracks={d} cube={d} gri={d}(grm={d},bll={d}) grm={d} bll={d} blocks={s} columns={d}x{d}",
        .{
            room.scene.entry_index,
            room.background.entry_index,
            room.scene.scene_kind,
            room.scene.classic_loader_scene_number,
            room.scene.hero_start.x,
            room.scene.hero_start.y,
            room.scene.hero_start.z,
            room.scene.object_count,
            room.scene.zone_count,
            room.scene.track_count,
            room.background.linkage.remapped_cube_index,
            room.background.linkage.gri_entry_index,
            room.background.linkage.gri_my_grm,
            room.background.linkage.gri_my_bll,
            room.background.linkage.grm_entry_index,
            room.background.linkage.bll_entry_index,
            used_blocks,
            room.background.column_table.width,
            room.background.column_table.depth,
        },
    );
    defer allocator.free(title);

    return allocator.dupeZ(u8, title);
}

fn printUsedBlockSummary(writer: anytype, used_block_ids: []const u8) !void {
    try writer.print("used_block_ids={d} values=", .{used_block_ids.len});
    for (used_block_ids, 0..) |block_id, index| {
        if (index != 0) try writer.writeAll("|");
        try writer.print("{d}", .{block_id});
    }
    try writer.writeAll("\n");
}

fn formatUsedBlockSummaryAlloc(
    allocator: std.mem.Allocator,
    used_block_ids: []const u8,
    max_items: usize,
) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    const writer = output.writer(allocator);
    try writer.print("{d}[", .{used_block_ids.len});

    const item_count = @min(max_items, used_block_ids.len);
    for (used_block_ids[0..item_count], 0..) |block_id, index| {
        if (index != 0) try writer.writeAll("|");
        try writer.print("{d}", .{block_id});
    }
    if (item_count < used_block_ids.len) {
        if (item_count != 0) try writer.writeAll("|");
        try writer.writeAll("...");
    }
    try writer.writeAll("]");

    return output.toOwnedSlice(allocator);
}

test "viewer argument parsing requires explicit scene and background entries" {
    const parsed = try parseArgs(std.testing.allocator, &.{
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

test "viewer room snapshot keeps the canonical interior pair stable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), room.scene.entry_index);
    try std.testing.expectEqual(@as(?usize, 0), room.scene.classic_loader_scene_number);
    try std.testing.expectEqualStrings("interior", room.scene.scene_kind);
    try std.testing.expectEqual(@as(i16, 9724), room.scene.hero_start.x);
    try std.testing.expectEqual(@as(i16, 1024), room.scene.hero_start.y);
    try std.testing.expectEqual(@as(i16, 782), room.scene.hero_start.z);
    try std.testing.expectEqual(@as(usize, 9), room.scene.object_count);
    try std.testing.expectEqual(@as(usize, 10), room.scene.zone_count);
    try std.testing.expectEqual(@as(usize, 4), room.scene.track_count);

    try std.testing.expectEqual(@as(usize, 2), room.background.entry_index);
    try std.testing.expectEqual(@as(usize, 2), room.background.linkage.remapped_cube_index);
    try std.testing.expectEqual(@as(usize, 3), room.background.linkage.gri_entry_index);
    try std.testing.expectEqual(@as(u8, 0), room.background.linkage.gri_my_grm);
    try std.testing.expectEqual(@as(usize, 149), room.background.linkage.grm_entry_index);
    try std.testing.expectEqual(@as(u8, 1), room.background.linkage.gri_my_bll);
    try std.testing.expectEqual(@as(usize, 180), room.background.linkage.bll_entry_index);
    try std.testing.expectEqual(@as(usize, 105), room.background.used_block_ids.len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 7 }, room.background.used_block_ids[0..6]);
    try std.testing.expectEqual(@as(usize, 64), room.background.column_table.width);
    try std.testing.expectEqual(@as(usize, 64), room.background.column_table.depth);
    try std.testing.expectEqual(@as(usize, 4096), room.background.column_table.offset_count);
    try std.testing.expectEqual(@as(usize, 8192), room.background.column_table.table_byte_length);
    try std.testing.expect(room.background.column_table.data_byte_length > 0);
}

test "viewer window title carries the canonical room metadata" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try loadRoomSnapshot(allocator, resolved, 2, 2);
    defer room.deinit(allocator);

    const title = try formatWindowTitleZ(allocator, room);
    defer allocator.free(title);

    try std.testing.expect(std.mem.indexOf(u8, title, "scene=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "background=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "kind=interior") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "loader=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "hero=9724,1024,782") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "cube=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "gri=3(grm=0,bll=1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "grm=149") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "bll=180") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "blocks=105[1|2|3|4|5|7|...]") != null);
    try std.testing.expect(std.mem.indexOf(u8, title, "columns=64x64") != null);
}

test "viewer room snapshot rejects exterior scene entries" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectError(error.ViewerSceneMustBeInterior, loadRoomSnapshot(allocator, resolved, 44, 2));
}

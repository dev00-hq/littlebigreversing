const std = @import("std");
const hqr = @import("hqr.zig");
const paths_mod = @import("../foundation/paths.zig");

pub const FixtureManifestEntry = struct {
    target_id: []const u8,
    asset_path: []const u8,
    entry_index: usize,
    output_path: []const u8,
    sha256: []const u8,

    pub fn deinit(self: FixtureManifestEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.output_path);
        allocator.free(self.sha256);
    }
};

pub const FixtureTarget = struct {
    target_id: []const u8,
    asset_path: []const u8,
    entry_index: usize,
    physical_entry_index: ?usize = null,
};

pub const fixture_targets = [_]FixtureTarget{
    .{ .target_id = "interior-room-twinsens-house-scene", .asset_path = "SCENE.HQR", .entry_index = 2 },
    .{ .target_id = "interior-room-twinsens-house-background", .asset_path = "LBA_BKG.HQR", .entry_index = 2 },
    .{ .target_id = "exterior-area-citadel-cliffs-scene", .asset_path = "SCENE.HQR", .entry_index = 4 },
    .{ .target_id = "dialog-voice-holomap", .asset_path = "VOX/EN_GAM.VOX", .entry_index = 1 },
    .{ .target_id = "cutscene-ascenseu-video", .asset_path = "VIDEO/VIDEO.HQR", .entry_index = 1 },
    // The corpus evidence names the movie index as RESS.HQR[49], but the raw
    // container's last physical slot is an empty terminal marker. The payload
    // bytes live in physical slot 48.
    .{ .target_id = "cutscene-ascenseu-ress", .asset_path = "RESS.HQR", .entry_index = 49, .physical_entry_index = 48 },
};

const ManifestJson = struct {
    fixtures: []const FixtureManifestEntry,
};

pub fn generateFixtures(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths) ![]FixtureManifestEntry {
    try paths_mod.ensurePhase1WorkDirs(allocator, resolved);

    var entries: std.ArrayList(FixtureManifestEntry) = .empty;
    errdefer {
        for (entries.items) |entry| entry.deinit(allocator);
        entries.deinit(allocator);
    }

    for (fixture_targets) |target| {
        const asset_abs = try std.fs.path.join(allocator, &.{ resolved.asset_root, target.asset_path });
        defer allocator.free(asset_abs);

        const sanitized = try hqr.sanitizeRelativeAssetPath(allocator, target.asset_path);
        defer allocator.free(sanitized);

        const fixture_dir = try std.fs.path.join(allocator, &.{ resolved.work_root, "fixtures", sanitized });
        defer allocator.free(fixture_dir);
        try paths_mod.makePathAbsolute(fixture_dir);

        const output_path = try std.fmt.allocPrint(allocator, "{s}{c}{d}.bin", .{ fixture_dir, std.fs.path.sep, target.entry_index });
        defer allocator.free(output_path);

        const physical_entry_index = target.physical_entry_index orelse target.entry_index;
        const sha = try hqr.extractEntryToPath(allocator, asset_abs, physical_entry_index, output_path);
        errdefer allocator.free(sha);

        try entries.append(allocator, .{
            .target_id = target.target_id,
            .asset_path = target.asset_path,
            .entry_index = target.entry_index,
            .output_path = try std.fmt.allocPrint(
                allocator,
                "work/port/phase1/fixtures/{s}/{d}.bin",
                .{ sanitized, target.entry_index },
            ),
            .sha256 = sha,
        });
    }

    return entries.toOwnedSlice(allocator);
}

pub fn renderFixtureManifestJson(allocator: std.mem.Allocator, entries: []const FixtureManifestEntry) ![]u8 {
    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(ManifestJson{ .fixtures = entries });
    return allocator.dupe(u8, out.written());
}

test "fixture targets stay locked to phase0 selections" {
    try std.testing.expectEqual(@as(usize, 6), fixture_targets.len);
    try std.testing.expectEqualStrings("VOX/EN_GAM.VOX", fixture_targets[3].asset_path);
    try std.testing.expectEqual(@as(usize, 49), fixture_targets[5].entry_index);
}

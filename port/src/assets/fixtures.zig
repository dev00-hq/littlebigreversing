const std = @import("std");
const hqr = @import("hqr.zig");
const paths_mod = @import("../foundation/paths.zig");

fn tempDirAbsolutePathAlloc(allocator: std.mem.Allocator, tmp: *const std.testing.TmpDir, sub_path: []const u8) ![]u8 {
    const cwd = try std.process.currentPathAlloc(std.testing.io, allocator);
    defer allocator.free(cwd);
    return std.fs.path.join(allocator, &.{ cwd, ".zig-cache", "tmp", &tmp.sub_path, sub_path });
}

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
    .{ .target_id = "exterior-area-citadel-tavern-and-shop-scene", .asset_path = "SCENE.HQR", .entry_index = 44 },
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
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(ManifestJson{ .fixtures = entries });
    return allocator.dupe(u8, out.written());
}

fn generatedFixtureByTargetId(entries: []const FixtureManifestEntry, target_id: []const u8) ?FixtureManifestEntry {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.target_id, target_id)) return entry;
    }
    return null;
}

test "fixture targets stay locked to phase0 selections" {
    try std.testing.expectEqual(@as(usize, 6), fixture_targets.len);
    try std.testing.expectEqual(@as(usize, 44), fixture_targets[2].entry_index);
    try std.testing.expectEqualStrings("VOX/EN_GAM.VOX", fixture_targets[3].asset_path);
    try std.testing.expectEqual(@as(usize, 49), fixture_targets[5].entry_index);
    try std.testing.expectEqual(@as(?usize, 48), fixture_targets[5].physical_entry_index);
}

test "generated fixtures keep semantic entry indices and physical-slot overrides stable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const entries = try generateFixtures(allocator, resolved);
    defer {
        for (entries) |entry| entry.deinit(allocator);
        allocator.free(entries);
    }

    const ress_entry = generatedFixtureByTargetId(entries, "cutscene-ascenseu-ress") orelse return error.MissingFixtureTarget;
    try std.testing.expectEqualStrings("RESS.HQR", ress_entry.asset_path);
    try std.testing.expectEqual(@as(usize, 49), ress_entry.entry_index);
    try std.testing.expectEqualStrings("work/port/phase1/fixtures/RESS.HQR/49.bin", ress_entry.output_path);

    const archive_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "RESS.HQR" });
    defer allocator.free(archive_path);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_path = try tempDirAbsolutePathAlloc(allocator, &tmp, ".");
    defer allocator.free(output_path);
    const fixture_path = try std.fs.path.join(allocator, &.{ output_path, "48.bin" });
    defer allocator.free(fixture_path);

    const expected_sha = try hqr.extractEntryToPath(allocator, archive_path, 48, fixture_path);
    defer allocator.free(expected_sha);

    try std.testing.expectEqualStrings(expected_sha, ress_entry.sha256);
}

test "fixture manifest json keeps semantic entry indices stable" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const entries = try generateFixtures(allocator, resolved);
    defer {
        for (entries) |entry| entry.deinit(allocator);
        allocator.free(entries);
    }

    const json = try renderFixtureManifestJson(allocator, entries);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"target_id\": \"cutscene-ascenseu-ress\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"entry_index\": 49") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"output_path\": \"work/port/phase1/fixtures/RESS.HQR/49.bin\"") != null);
}

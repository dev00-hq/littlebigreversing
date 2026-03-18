const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");

pub const required_phase1_files = [_][]const u8{
    "SCENE.HQR",
    "LBA_BKG.HQR",
    "RESS.HQR",
    "BODY.HQR",
    "ANIM.HQR",
    "SPRITES.HQR",
    "TEXT.HQR",
    "VIDEO/VIDEO.HQR",
};

const locale_dirs = std.StaticStringMap([]const u8).initComptime(.{
    .{ "ENGLISH", "english" },
    .{ "FRENCH", "french" },
    .{ "GERMAN", "german" },
    .{ "ITALIAN", "italian" },
    .{ "SPANISH", "spanish" },
});

const vox_prefix_locales = std.StaticStringMap([]const u8).initComptime(.{
    .{ "DE", "german" },
    .{ "EN", "english" },
    .{ "ES", "spanish" },
    .{ "FR", "french" },
    .{ "GE", "german" },
    .{ "GR", "german" },
    .{ "IT", "italian" },
});

pub const AssetCatalogEntry = struct {
    relative_path: []const u8,
    asset_class: []const u8,
    locale_bucket: ?[]const u8,
    required_for_phase1: bool,
    size_bytes: u64,
    sha256: []const u8,

    pub fn deinit(self: AssetCatalogEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.relative_path);
        allocator.free(self.asset_class);
        if (self.locale_bucket) |locale| allocator.free(locale);
        allocator.free(self.sha256);
    }
};

pub const IslandPair = struct {
    stem: []const u8,
    ile_path: []const u8,
    obl_path: []const u8,

    pub fn deinit(self: IslandPair, allocator: std.mem.Allocator) void {
        allocator.free(self.stem);
        allocator.free(self.ile_path);
        allocator.free(self.obl_path);
    }
};

const CatalogJson = struct {
    asset_root: []const u8,
    inventory: []const AssetCatalogEntry,
};

pub fn validateExplicitRequirements(asset_root: []const u8) !void {
    for (required_phase1_files) |relative_path| {
        const full_path = try std.fs.path.join(std.heap.page_allocator, &.{ asset_root, relative_path });
        defer std.heap.page_allocator.free(full_path);

        const file = std.fs.openFileAbsolute(full_path, .{}) catch return error.MissingRequiredPhase1File;
        file.close();
    }
}

pub fn listRequiredVoxFiles(allocator: std.mem.Allocator, asset_root: []const u8) ![][]const u8 {
    const vox_root = try std.fs.path.join(allocator, &.{ asset_root, "VOX" });
    defer allocator.free(vox_root);

    var dir = try std.fs.openDirAbsolute(vox_root, .{ .iterate = true });
    defer dir.close();

    var vox_files: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (vox_files.items) |item| allocator.free(item);
        vox_files.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.ascii.endsWithIgnoreCase(entry.name, ".VOX")) continue;
        try vox_files.append(allocator, try std.fmt.allocPrint(allocator, "VOX/{s}", .{entry.name}));
    }

    if (vox_files.items.len == 0) return error.MissingVoxFiles;

    std.sort.block([]const u8, vox_files.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.ascii.lessThanIgnoreCase(lhs, rhs);
        }
    }.lessThan);

    return vox_files.toOwnedSlice(allocator);
}

pub fn listIslandPairs(allocator: std.mem.Allocator, asset_root: []const u8) ![]IslandPair {
    var dir = try std.fs.openDirAbsolute(asset_root, .{ .iterate = true });
    defer dir.close();

    var stem_map = std.StringHashMap(struct { has_ile: bool, has_obl: bool }).init(allocator);
    defer {
        var iter_keys = stem_map.keyIterator();
        while (iter_keys.next()) |key| allocator.free(key.*);
        stem_map.deinit();
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.ascii.endsWithIgnoreCase(entry.name, ".ILE") and !std.ascii.endsWithIgnoreCase(entry.name, ".OBL")) continue;

        const stem = std.fs.path.stem(entry.name);
        const owned_stem = try allocator.dupe(u8, stem);
        errdefer allocator.free(owned_stem);
        const result = try stem_map.getOrPut(owned_stem);
        if (!result.found_existing) {
            result.value_ptr.* = .{ .has_ile = false, .has_obl = false };
        } else {
            allocator.free(owned_stem);
        }

        if (std.ascii.endsWithIgnoreCase(entry.name, ".ILE")) {
            result.value_ptr.has_ile = true;
        } else {
            result.value_ptr.has_obl = true;
        }
    }

    if (stem_map.count() == 0) return error.MissingIslandPairs;

    var pairs: std.ArrayList(IslandPair) = .empty;
    errdefer {
        for (pairs.items) |pair| pair.deinit(allocator);
        pairs.deinit(allocator);
    }

    var pair_iter = stem_map.iterator();
    while (pair_iter.next()) |entry| {
        if (!entry.value_ptr.has_ile or !entry.value_ptr.has_obl) return error.IncompleteIslandPair;
        try pairs.append(allocator, .{
            .stem = try allocator.dupe(u8, entry.key_ptr.*),
            .ile_path = try std.fmt.allocPrint(allocator, "{s}.ILE", .{entry.key_ptr.*}),
            .obl_path = try std.fmt.allocPrint(allocator, "{s}.OBL", .{entry.key_ptr.*}),
        });
    }

    std.sort.block(IslandPair, pairs.items, {}, struct {
        fn lessThan(_: void, lhs: IslandPair, rhs: IslandPair) bool {
            return std.ascii.lessThanIgnoreCase(lhs.stem, rhs.stem);
        }
    }.lessThan);

    return pairs.toOwnedSlice(allocator);
}

pub fn generateAssetCatalog(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths) ![]AssetCatalogEntry {
    try validateExplicitRequirements(resolved.asset_root);
    const vox_files = try listRequiredVoxFiles(allocator, resolved.asset_root);
    defer {
        for (vox_files) |item| allocator.free(item);
        allocator.free(vox_files);
    }
    const island_pairs = try listIslandPairs(allocator, resolved.asset_root);
    defer {
        for (island_pairs) |pair| pair.deinit(allocator);
        allocator.free(island_pairs);
    }

    var asset_dir = try std.fs.openDirAbsolute(resolved.asset_root, .{ .iterate = true });
    defer asset_dir.close();
    var walker = try asset_dir.walk(allocator);
    defer walker.deinit();

    var inventory: std.ArrayList(AssetCatalogEntry) = .empty;
    errdefer {
        for (inventory.items) |entry| entry.deinit(allocator);
        inventory.deinit(allocator);
    }

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const normalized_path = try normalizeRelativePath(allocator, entry.path);
        defer allocator.free(normalized_path);

        const absolute_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, normalized_path });
        defer allocator.free(absolute_path);
        var file = try std.fs.openFileAbsolute(absolute_path, .{});
        defer file.close();
        const stat = try file.stat();

        try inventory.append(allocator, .{
            .relative_path = try allocator.dupe(u8, normalized_path),
            .asset_class = try allocator.dupe(u8, classifyAsset(normalized_path)),
            .locale_bucket = if (detectLocale(normalized_path)) |locale| try allocator.dupe(u8, locale) else null,
            .required_for_phase1 = isRequiredPhase1(normalized_path),
            .size_bytes = stat.size,
            .sha256 = try sha256FileAlloc(allocator, absolute_path),
        });
    }

    std.sort.block(AssetCatalogEntry, inventory.items, {}, struct {
        fn lessThan(_: void, lhs: AssetCatalogEntry, rhs: AssetCatalogEntry) bool {
            return std.ascii.lessThanIgnoreCase(lhs.relative_path, rhs.relative_path);
        }
    }.lessThan);

    try validateRequiredFlags(allocator, inventory.items, vox_files, island_pairs);
    return inventory.toOwnedSlice(allocator);
}

pub fn renderCatalogJson(allocator: std.mem.Allocator, inventory: []const AssetCatalogEntry) ![]u8 {
    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(CatalogJson{
        .asset_root = paths_mod.canonical_asset_root_relative,
        .inventory = inventory,
    });
    return allocator.dupe(u8, out.written());
}

fn validateRequiredFlags(
    allocator: std.mem.Allocator,
    inventory: []const AssetCatalogEntry,
    vox_files: [][]const u8,
    island_pairs: []const IslandPair,
) !void {
    var expected: std.ArrayList([]const u8) = .empty;
    defer {
        for (expected.items) |item| allocator.free(item);
        expected.deinit(allocator);
    }

    for (required_phase1_files) |path| try expected.append(allocator, try allocator.dupe(u8, path));
    for (vox_files) |path| try expected.append(allocator, try allocator.dupe(u8, path));
    for (island_pairs) |pair| {
        try expected.append(allocator, try allocator.dupe(u8, pair.ile_path));
        try expected.append(allocator, try allocator.dupe(u8, pair.obl_path));
    }

    std.sort.block([]const u8, expected.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.ascii.lessThanIgnoreCase(lhs, rhs);
        }
    }.lessThan);

    var flagged: std.ArrayList([]const u8) = .empty;
    defer flagged.deinit(allocator);
    for (inventory) |entry| {
        if (entry.required_for_phase1) try flagged.append(allocator, entry.relative_path);
    }
    std.sort.block([]const u8, flagged.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.ascii.lessThanIgnoreCase(lhs, rhs);
        }
    }.lessThan);

    if (flagged.items.len != expected.items.len) return error.RequiredPhase1DependencyDrift;
    for (flagged.items, expected.items) |lhs, rhs| {
        if (!std.ascii.eqlIgnoreCase(lhs, rhs)) return error.RequiredPhase1DependencyDrift;
    }
}

fn detectLocale(relative_path: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, relative_path, '/')) |slash| {
        const head = relative_path[0..slash];
        if (locale_dirs.get(head)) |locale| return locale;
    }
    if (std.mem.startsWith(u8, relative_path, "VOX/")) {
        const stem = std.fs.path.stem(relative_path[4..]);
        if (std.mem.indexOfScalar(u8, stem, '_')) |underscore| {
            return vox_prefix_locales.get(stem[0..underscore]);
        }
        return vox_prefix_locales.get(stem);
    }
    return null;
}

fn classifyAsset(relative_path: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(relative_path, "SCENE.HQR")) return "scene-hqr";
    if (std.ascii.eqlIgnoreCase(relative_path, "LBA_BKG.HQR")) return "background-hqr";
    if (std.ascii.eqlIgnoreCase(relative_path, "RESS.HQR")) return "resource-hqr";
    if (std.ascii.eqlIgnoreCase(relative_path, "BODY.HQR")) return "body-hqr";
    if (std.ascii.eqlIgnoreCase(relative_path, "ANIM.HQR")) return "animation-hqr";
    if (std.ascii.eqlIgnoreCase(relative_path, "SPRITES.HQR")) return "sprite-hqr";
    if (std.ascii.eqlIgnoreCase(relative_path, "TEXT.HQR")) return "text-hqr";
    if (std.ascii.eqlIgnoreCase(relative_path, "VIDEO/VIDEO.HQR")) return "video-hqr";
    if (std.ascii.endsWithIgnoreCase(relative_path, ".HQR")) return "hqr-container";
    if (std.ascii.endsWithIgnoreCase(relative_path, ".VOX")) return "voice-container";
    if (std.ascii.endsWithIgnoreCase(relative_path, ".ILE")) return "island-heightmap";
    if (std.ascii.endsWithIgnoreCase(relative_path, ".OBL")) return "island-objects";
    if (std.ascii.endsWithIgnoreCase(relative_path, ".SMK")) return "smacker-video";
    if (std.mem.startsWith(u8, relative_path, "VIDEO/")) return "video-support";
    if (std.mem.startsWith(u8, relative_path, "MUSIC/")) return "music-data";
    if (std.mem.startsWith(u8, relative_path, "CONFIG/")) return "config-data";
    if (std.ascii.endsWithIgnoreCase(relative_path, ".CFG") or std.ascii.endsWithIgnoreCase(relative_path, ".INI")) return "config-file";
    if (std.ascii.endsWithIgnoreCase(relative_path, ".DLL")) return "runtime-library";
    if (std.ascii.endsWithIgnoreCase(relative_path, ".EXE") or std.ascii.endsWithIgnoreCase(relative_path, ".BAT")) return "runtime-binary";
    return "other";
}

fn isRequiredPhase1(relative_path: []const u8) bool {
    for (required_phase1_files) |path| {
        if (std.ascii.eqlIgnoreCase(relative_path, path)) return true;
    }
    if (std.mem.startsWith(u8, relative_path, "VOX/") and std.ascii.endsWithIgnoreCase(relative_path, ".VOX")) return true;
    if (std.ascii.endsWithIgnoreCase(relative_path, ".ILE") or std.ascii.endsWithIgnoreCase(relative_path, ".OBL")) return true;
    return false;
}

fn sha256FileAlloc(allocator: std.mem.Allocator, absolute_path: []const u8) ![]const u8 {
    var file = try std.fs.openFileAbsolute(absolute_path, .{});
    defer file.close();

    var digest = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const read = try file.read(&buffer);
        if (read == 0) break;
        digest.update(buffer[0..read]);
    }

    var out: [32]u8 = undefined;
    digest.final(&out);
    const encoded = std.fmt.bytesToHex(out, .lower);
    return allocator.dupe(u8, &encoded);
}

fn normalizeRelativePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const copy = try allocator.dupe(u8, path);
    for (copy) |*char| {
        if (char.* == '\\') char.* = '/';
    }
    return copy;
}

fn writeTestAssetFile(allocator: std.mem.Allocator, dir: std.fs.Dir, asset_root: []const u8, relative_path: []const u8, data: []const u8) !void {
    const sub_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ asset_root, relative_path });
    defer allocator.free(sub_path);

    if (std.fs.path.dirname(sub_path)) |parent| try dir.makePath(parent);
    try dir.writeFile(.{ .sub_path = sub_path, .data = data });
}

fn expectCatalogEntryEqual(expected: AssetCatalogEntry, actual: AssetCatalogEntry) !void {
    try std.testing.expectEqualStrings(expected.relative_path, actual.relative_path);
    try std.testing.expectEqualStrings(expected.asset_class, actual.asset_class);
    if (expected.locale_bucket) |locale| {
        try std.testing.expect(actual.locale_bucket != null);
        try std.testing.expectEqualStrings(locale, actual.locale_bucket.?);
    } else {
        try std.testing.expect(actual.locale_bucket == null);
    }
    try std.testing.expectEqual(expected.required_for_phase1, actual.required_for_phase1);
    try std.testing.expectEqual(expected.size_bytes, actual.size_bytes);
    try std.testing.expectEqualStrings(expected.sha256, actual.sha256);
}

test "classification and locale detection follow phase0 policy" {
    try std.testing.expectEqualStrings("video-hqr", classifyAsset("VIDEO/VIDEO.HQR"));
    try std.testing.expectEqualStrings("voice-container", classifyAsset("VOX/EN_GAM.VOX"));
    try std.testing.expectEqualStrings("english", detectLocale("VOX/EN_GAM.VOX").?);
    try std.testing.expect(isRequiredPhase1("VOX/EN_GAM.VOX"));
    try std.testing.expect(isRequiredPhase1("ASCENCE.ILE"));
}

test "catalog generation is deterministic and json stable" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("assets");
    for (required_phase1_files) |relative_path| {
        try writeTestAssetFile(allocator, tmp.dir, "assets", relative_path, "phase1");
    }
    try writeTestAssetFile(allocator, tmp.dir, "assets", "VOX/FR_GAM.VOX", "voice-fr");
    try writeTestAssetFile(allocator, tmp.dir, "assets", "VOX/EN_GAM.VOX", "voice-en");
    try writeTestAssetFile(allocator, tmp.dir, "assets", "CITADEL.OBL", "island-obl");
    try writeTestAssetFile(allocator, tmp.dir, "assets", "CITADEL.ILE", "island-ile");
    try writeTestAssetFile(allocator, tmp.dir, "assets", "MUSIC/THEME_01.XMI", "music");

    const repo_root = try tmp.dir.realpathAlloc(allocator, ".");
    const asset_root = try tmp.dir.realpathAlloc(allocator, "assets");
    const work_root = try std.fs.path.join(allocator, &.{ repo_root, paths_mod.phase1_work_relative });
    const resolved = paths_mod.ResolvedPaths{
        .repo_root = repo_root,
        .asset_root = asset_root,
        .work_root = work_root,
    };
    defer resolved.deinit(allocator);

    const first = try generateAssetCatalog(allocator, resolved);
    defer {
        for (first) |entry| entry.deinit(allocator);
        allocator.free(first);
    }

    const second = try generateAssetCatalog(allocator, resolved);
    defer {
        for (second) |entry| entry.deinit(allocator);
        allocator.free(second);
    }

    try std.testing.expectEqual(first.len, second.len);
    for (first, second) |lhs, rhs| try expectCatalogEntryEqual(lhs, rhs);

    for (1..first.len) |index| {
        try std.testing.expect(!std.ascii.lessThanIgnoreCase(first[index].relative_path, first[index - 1].relative_path));
    }

    const json_first = try renderCatalogJson(allocator, first);
    defer allocator.free(json_first);
    const json_second = try renderCatalogJson(allocator, second);
    defer allocator.free(json_second);

    try std.testing.expectEqualStrings(json_first, json_second);
    try std.testing.expect(std.mem.indexOf(u8, json_first, "\"asset_root\": \"work/_innoextract_full/Speedrun/Windows/LBA2_cdrom/LBA2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_first, "\"relative_path\": \"CITADEL.ILE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_first, "\"relative_path\": \"VOX/FR_GAM.VOX\"") != null);
}

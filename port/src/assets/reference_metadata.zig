const std = @import("std");
const generated = @import("../generated/reference_metadata.zig");

pub const ResolvedEntryMetadata = struct {
    entry_type: ?[]const u8,
    entry_description: ?[]const u8,
};

pub fn lookupHqrEntryMetadata(relative_path: []const u8, entry_index: usize) ?ResolvedEntryMetadata {
    if (std.ascii.eqlIgnoreCase(relative_path, "BODY.HQR")) {
        return resolveEntryMetadata(generated.body_hqr_entries, entry_index);
    }

    if (normalizeVoxMetadataKey(relative_path)) |metadata_key| {
        if (std.mem.eql(u8, metadata_key, "VOX/XX_GAM.VOX")) {
            return resolveEntryMetadata(generated.xx_gam_vox_entries, entry_index);
        }
    }

    return null;
}

fn resolveEntryMetadata(entries: []const generated.EntryMetadata, entry_index: usize) ?ResolvedEntryMetadata {
    for (entries) |entry| {
        if (entry.entry_index != entry_index) continue;
        return .{
            .entry_type = entry.entry_type,
            .entry_description = entry.entry_description,
        };
    }
    return null;
}

fn normalizeVoxMetadataKey(relative_path: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, relative_path, "VOX/")) return null;
    if (!std.ascii.endsWithIgnoreCase(relative_path, ".VOX")) return null;

    const file_name = relative_path[4..];
    const underscore_index = std.mem.indexOfScalar(u8, file_name, '_') orelse return null;
    const suffix = file_name[underscore_index..];
    if (!std.ascii.eqlIgnoreCase(suffix, "_GAM.VOX")) return null;
    return "VOX/XX_GAM.VOX";
}

test "lookupHqrEntryMetadata resolves BODY.HQR entry descriptions" {
    const metadata = lookupHqrEntryMetadata("BODY.HQR", 1) orelse return error.MissingEntryMetadata;
    try std.testing.expectEqualStrings("mesh", metadata.entry_type.?);
    try std.testing.expectEqualStrings("Twinsen without tunic model", metadata.entry_description.?);
}

test "lookupHqrEntryMetadata normalizes locale-specific GAM voice archives" {
    const metadata = lookupHqrEntryMetadata("VOX/EN_GAM.VOX", 1) orelse return error.MissingEntryMetadata;
    try std.testing.expectEqualStrings("wave_audio", metadata.entry_type.?);
    try std.testing.expectEqualStrings("Voice for Holomap", metadata.entry_description.?);
}

test "lookupHqrEntryMetadata keeps metadata gaps optional" {
    try std.testing.expect(lookupHqrEntryMetadata("VOX/EN_GAM.VOX", 9) == null);
    try std.testing.expect(lookupHqrEntryMetadata("SCENE.HQR", 2) == null);
}

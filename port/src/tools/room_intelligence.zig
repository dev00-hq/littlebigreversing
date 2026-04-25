const std = @import("std");
const hqr = @import("../assets/hqr.zig");
const room_metadata = @import("../generated/room_metadata.zig");
const background_data = @import("../game_data/background.zig");
const life_audit = @import("../game_data/scene/life_audit.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const scene_data = @import("../game_data/scene.zig");
const room_state = @import("../runtime/room_state.zig");

const RoomMetadataEntry = room_metadata.RoomMetadataEntry;

pub const MetadataKind = enum {
    scene,
    background,

    pub fn displayName(self: MetadataKind) []const u8 {
        return switch (self) {
            .scene => "scene",
            .background => "background",
        };
    }

    pub fn sourcePath(self: MetadataKind) []const u8 {
        _ = self;
        return room_metadata.generated_relative_path;
    }

    fn entries(self: MetadataKind) []const RoomMetadataEntry {
        return switch (self) {
            .scene => room_metadata.scene_entries,
            .background => room_metadata.background_entries,
        };
    }
};

pub const Selector = union(enum) {
    entry: usize,
    name: []const u8,

    pub fn kindName(self: Selector) []const u8 {
        return switch (self) {
            .entry => "entry",
            .name => "name",
        };
    }
};

pub const RequestedSelectorKind = enum {
    entry,
    name,

    pub fn kindName(self: RequestedSelectorKind) []const u8 {
        return @tagName(self);
    }
};

pub const ResolvedSelection = struct {
    metadata_kind: MetadataKind,
    selector: Selector,
    resolved_entry_index: usize,
    resolved_friendly_name: ?[]u8,

    pub fn deinit(self: ResolvedSelection, allocator: std.mem.Allocator) void {
        if (self.resolved_friendly_name) |friendly_name| allocator.free(friendly_name);
    }

    pub fn selectorKindName(self: ResolvedSelection) []const u8 {
        return self.selector.kindName();
    }

    pub fn requestedEntryIndex(self: ResolvedSelection) ?usize {
        return switch (self.selector) {
            .entry => |entry_index| entry_index,
            .name => null,
        };
    }

    pub fn requestedName(self: ResolvedSelection) ?[]const u8 {
        return switch (self.selector) {
            .entry => null,
            .name => |name| name,
        };
    }
};

pub const SelectionRequest = struct {
    metadata_kind: MetadataKind,
    selector: ?Selector = null,
    selector_kind_hint: ?RequestedSelectorKind = null,
    requested_raw_value: ?[]const u8 = null,
};

pub fn resolveSceneSelectionAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    selector: Selector,
) !ResolvedSelection {
    return resolveSelectionAlloc(allocator, repo_root, .scene, selector);
}

pub fn resolveBackgroundSelectionAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    selector: Selector,
) !ResolvedSelection {
    return resolveSelectionAlloc(allocator, repo_root, .background, selector);
}

fn resolveSelectionAlloc(
    allocator: std.mem.Allocator,
    repo_root: []const u8,
    metadata_kind: MetadataKind,
    selector: Selector,
) !ResolvedSelection {
    _ = repo_root;
    return resolveSelectionFromEntriesAlloc(allocator, metadata_kind, selector, metadata_kind.entries());
}

fn resolveSelectionFromEntriesAlloc(
    allocator: std.mem.Allocator,
    metadata_kind: MetadataKind,
    selector: Selector,
    entries: []const RoomMetadataEntry,
) !ResolvedSelection {
    return switch (selector) {
        .entry => |entry_index| resolveEntrySelectionAlloc(allocator, metadata_kind, selector, entry_index, entries),
        .name => |name| resolveNameSelectionAlloc(allocator, metadata_kind, selector, name, entries),
    };
}

fn resolveEntrySelectionAlloc(
    allocator: std.mem.Allocator,
    metadata_kind: MetadataKind,
    selector: Selector,
    entry_index: usize,
    entries: []const RoomMetadataEntry,
) !ResolvedSelection {
    for (entries) |entry| {
        if (entry.entry_index != entry_index) continue;
        return .{
            .metadata_kind = metadata_kind,
            .selector = selector,
            .resolved_entry_index = entry_index,
            .resolved_friendly_name = try allocator.dupe(u8, entry.display_name),
        };
    }

    return .{
        .metadata_kind = metadata_kind,
        .selector = selector,
        .resolved_entry_index = entry_index,
        .resolved_friendly_name = null,
    };
}

fn resolveNameSelectionAlloc(
    allocator: std.mem.Allocator,
    metadata_kind: MetadataKind,
    selector: Selector,
    name: []const u8,
    entries: []const RoomMetadataEntry,
) !ResolvedSelection {
    const normalized_query = try normalizeSearchKeyAlloc(allocator, name);
    defer allocator.free(normalized_query);

    var exact_match: ?*const RoomMetadataEntry = null;
    var suffix_match: ?*const RoomMetadataEntry = null;
    var suffix_ambiguous = false;

    for (entries) |*entry| {
        if (std.mem.eql(u8, entry.normalized_name, normalized_query)) {
            if (exact_match != null) return metadataAmbiguousError(metadata_kind);
            exact_match = entry;
            continue;
        }

        if (!std.mem.endsWith(u8, entry.normalized_name, normalized_query)) continue;
        if (suffix_match == null) {
            suffix_match = entry;
        } else {
            suffix_ambiguous = true;
        }
    }

    if (exact_match) |record| {
        return .{
            .metadata_kind = metadata_kind,
            .selector = selector,
            .resolved_entry_index = record.entry_index,
            .resolved_friendly_name = try allocator.dupe(u8, record.display_name),
        };
    }
    if (suffix_ambiguous) return metadataAmbiguousError(metadata_kind);
    if (suffix_match) |record| {
        return .{
            .metadata_kind = metadata_kind,
            .selector = selector,
            .resolved_entry_index = record.entry_index,
            .resolved_friendly_name = try allocator.dupe(u8, record.display_name),
        };
    }
    return metadataUnknownError(metadata_kind);
}

fn metadataUnknownError(metadata_kind: MetadataKind) error{
    UnknownSceneName,
    AmbiguousSceneName,
    UnknownBackgroundName,
    AmbiguousBackgroundName,
} {
    return switch (metadata_kind) {
        .scene => error.UnknownSceneName,
        .background => error.UnknownBackgroundName,
    };
}

fn metadataAmbiguousError(metadata_kind: MetadataKind) error{
    UnknownSceneName,
    AmbiguousSceneName,
    UnknownBackgroundName,
    AmbiguousBackgroundName,
} {
    return switch (metadata_kind) {
        .scene => error.AmbiguousSceneName,
        .background => error.AmbiguousBackgroundName,
    };
}

fn normalizeSearchKeyAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var view = try std.unicode.Utf8View.init(input);
    var iterator = view.iterator();
    var normalized: std.ArrayList(u8) = .empty;
    errdefer normalized.deinit(allocator);

    var pending_space = false;
    while (iterator.nextCodepoint()) |codepoint| {
        const folded = foldCodepoint(codepoint);
        if (folded == 0) {
            pending_space = normalized.items.len != 0;
            continue;
        }

        if (pending_space and normalized.items.len != 0) {
            try normalized.append(allocator, ' ');
            pending_space = false;
        }
        try normalized.append(allocator, folded);
    }

    while (normalized.items.len != 0 and normalized.items[normalized.items.len - 1] == ' ') {
        _ = normalized.pop();
    }

    return normalized.toOwnedSlice(allocator);
}

fn foldCodepoint(codepoint: u21) u8 {
    return switch (codepoint) {
        'A'...'Z' => @as(u8, @intCast(codepoint + 32)),
        'a'...'z', '0'...'9' => @as(u8, @intCast(codepoint)),
        0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5 => 'a',
        0x00C7, 0x00E7 => 'c',
        0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00E8, 0x00E9, 0x00EA, 0x00EB => 'e',
        0x00CC, 0x00CD, 0x00CE, 0x00CF, 0x00EC, 0x00ED, 0x00EE, 0x00EF => 'i',
        0x00D1, 0x00F1 => 'n',
        0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6 => 'o',
        0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00F9, 0x00FA, 0x00FB, 0x00FC => 'u',
        0x00DD, 0x00FD, 0x00FF => 'y',
        else => 0,
    };
}

const SceneLifeValidationStatus = enum {
    decoded,
    unsupported_opcode,
};

const SceneKindValidationStatus = enum {
    interior,
    non_interior,
};

const FragmentZonesValidationStatus = enum {
    compatible,
    invalid_bounds,
    skipped,
};

pub const ValidationSnapshot = struct {
    scene_life_status: SceneLifeValidationStatus,
    unsupported_scene_life_hit: ?room_state.UnsupportedSceneLifeHit = null,
    scene_kind_status: SceneKindValidationStatus,
    fragment_zones_status: FragmentZonesValidationStatus,
    fragment_zones_skipped_reason: ?[]const u8 = null,
    fragment_zone_diagnostics: ?room_state.RoomFragmentZoneDiagnostics = null,
    viewer_loadable: bool,

    pub fn deinit(self: *ValidationSnapshot, allocator: std.mem.Allocator) void {
        if (self.fragment_zone_diagnostics) |diagnostics| diagnostics.deinit(allocator);
    }
};

pub fn validateSceneEntryIndex(
    allocator: std.mem.Allocator,
    asset_root: []const u8,
    entry_index: usize,
) !void {
    const scene_path = try std.fs.path.join(allocator, &.{ asset_root, "SCENE.HQR" });
    defer allocator.free(scene_path);

    var archive = try hqr.loadArchive(allocator, scene_path);
    defer archive.deinit(allocator);

    if (entry_index == 0 or entry_index > archive.entry_count) return error.UnknownSceneEntryIndex;
}

pub fn validateBackgroundEntryIndex(
    allocator: std.mem.Allocator,
    asset_root: []const u8,
    entry_index: usize,
) !void {
    const background_path = try std.fs.path.join(allocator, &.{ asset_root, "LBA_BKG.HQR" });
    defer allocator.free(background_path);

    const entry_count = try background_data.loadBackgroundEntryCount(allocator, background_path);
    if (entry_index >= entry_count) return error.UnknownBackgroundEntryIndex;
}

pub fn inspectValidation(
    allocator: std.mem.Allocator,
    scene: scene_data.SceneMetadata,
    background: background_data.BackgroundMetadata,
) !ValidationSnapshot {
    var validation: ValidationSnapshot = .{
        .scene_life_status = undefined,
        .scene_kind_status = if (std.mem.eql(u8, scene.sceneKind(), "interior")) .interior else .non_interior,
        .fragment_zones_status = .skipped,
        .viewer_loadable = false,
    };

    switch (try life_audit.validateSceneLifeBoundary(scene)) {
        .decoded => validation.scene_life_status = .decoded,
        .unsupported_life_blob => |hit| {
            validation.scene_life_status = .unsupported_opcode;
            validation.unsupported_scene_life_hit = hit;
            validation.fragment_zones_skipped_reason = "unsupported_scene_life";
            return validation;
        },
    }

    if (validation.scene_kind_status == .non_interior) {
        validation.fragment_zones_skipped_reason = "scene_must_be_interior";
        return validation;
    }

    const diagnostics = try room_state.buildRoomFragmentZoneDiagnosticsFromMetadataAssumingSupportedScene(allocator, scene, background);
    validation.fragment_zones_status = if (diagnostics.invalid_zone_count == 0) .compatible else .invalid_bounds;
    validation.viewer_loadable = diagnostics.invalid_zone_count == 0;
    validation.fragment_zone_diagnostics = diagnostics;
    return validation;
}

pub const PayloadView = struct {
    allocator: std.mem.Allocator,
    scene_selection: *const ResolvedSelection,
    background_selection: *const ResolvedSelection,
    scene: *const scene_data.SceneMetadata,
    background: *const background_data.BackgroundMetadata,
    validation: *const ValidationSnapshot,
    augmentation: ?*const room_state.RoomIntelligenceAugmentation = null,
};

pub const ErrorPayloadView = struct {
    scene_request: SelectionRequest,
    background_request: SelectionRequest,
    scene_selection: ?*const ResolvedSelection = null,
    background_selection: ?*const ResolvedSelection = null,
    phase: []const u8,
    kind: []const u8,
    target: []const u8,
};

pub fn stringifyPayloadAlloc(allocator: std.mem.Allocator, payload: PayloadView) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try writePayloadJson(allocator, &stringify, payload);
    return allocator.dupe(u8, out.written());
}

pub fn stringifyErrorPayloadAlloc(allocator: std.mem.Allocator, payload: ErrorPayloadView) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try writeErrorPayloadJson(&stringify, payload);
    return allocator.dupe(u8, out.written());
}

fn writePayloadJson(allocator: std.mem.Allocator, jw: anytype, payload: PayloadView) !void {
    try jw.beginObject();
    try jw.objectField("command");
    try jw.write("inspect-room-intelligence");
    try jw.objectField("status");
    try jw.write("ok");
    try jw.objectField("selection");
    try writeSelectionJson(jw, payload.scene_selection, payload.background_selection);
    try jw.objectField("scene");
    try writeSceneJson(allocator, jw, payload.scene, payload.validation.scene_life_status == .decoded);
    try jw.objectField("background");
    try writeBackgroundJson(jw, payload.background, payload.augmentation);
    try jw.objectField("validation");
    try writeValidationJson(jw, payload.validation);
    try jw.objectField("actors");
    try writeActorsJson(allocator, jw, payload.scene.objects, payload.validation.scene_life_status == .decoded);
    if (payload.augmentation) |augmentation| {
        try jw.objectField("fragment_zone_layout");
        try writeFragmentZonesJson(jw, augmentation.fragment_zones);
    }
    try jw.objectField("zones");
    try jw.write(payload.scene.zones);
    try jw.objectField("tracks");
    try jw.write(payload.scene.tracks);
    try jw.objectField("patches");
    try jw.write(payload.scene.patches);
    try jw.endObject();
}

fn writeErrorPayloadJson(jw: anytype, payload: ErrorPayloadView) !void {
    try jw.beginObject();
    try jw.objectField("command");
    try jw.write("inspect-room-intelligence");
    try jw.objectField("status");
    try jw.write("error");
    try jw.objectField("selection");
    try writeSelectionRequestJson(jw, payload.scene_request, payload.scene_selection, payload.background_request, payload.background_selection);
    try jw.objectField("error");
    try jw.beginObject();
    try jw.objectField("phase");
    try jw.write(payload.phase);
    try jw.objectField("kind");
    try jw.write(payload.kind);
    try jw.objectField("target");
    try jw.write(payload.target);
    try jw.endObject();
    try jw.endObject();
}

fn writeSelectionJson(jw: anytype, scene_selection: *const ResolvedSelection, background_selection: *const ResolvedSelection) !void {
    try jw.beginObject();
    try jw.objectField("scene");
    try writeResolvedSelectionJson(jw, scene_selection);
    try jw.objectField("background");
    try writeResolvedSelectionJson(jw, background_selection);
    try jw.endObject();
}

fn writeSelectionRequestJson(
    jw: anytype,
    scene_request: SelectionRequest,
    scene_selection: ?*const ResolvedSelection,
    background_request: SelectionRequest,
    background_selection: ?*const ResolvedSelection,
) !void {
    try jw.beginObject();
    try jw.objectField("scene");
    try writeSelectionStateJson(jw, scene_request, scene_selection);
    try jw.objectField("background");
    try writeSelectionStateJson(jw, background_request, background_selection);
    try jw.endObject();
}

fn writeSelectionStateJson(jw: anytype, request: SelectionRequest, resolved: ?*const ResolvedSelection) !void {
    try jw.beginObject();
    try jw.objectField("metadata_kind");
    try jw.write(request.metadata_kind.displayName());
    try jw.objectField("metadata_source");
    try jw.write(request.metadata_kind.sourcePath());
    try jw.objectField("selector_kind");
    if (request.selector) |selector| {
        try jw.write(selector.kindName());
    } else if (request.selector_kind_hint) |kind| {
        try jw.write(kind.kindName());
    } else {
        try jw.write(null);
    }
    try jw.objectField("requested_entry_index");
    if (request.selector) |selector| switch (selector) {
        .entry => |entry_index| try jw.write(entry_index),
        .name => try jw.write(null),
    } else {
        try jw.write(null);
    }
    try jw.objectField("requested_name");
    if (request.selector) |selector| switch (selector) {
        .entry => try jw.write(null),
        .name => |name| try jw.write(name),
    } else {
        try jw.write(null);
    }
    try jw.objectField("requested_raw_value");
    try jw.write(request.requested_raw_value);
    try jw.objectField("resolved_entry_index");
    if (resolved) |selection| {
        try jw.write(selection.resolved_entry_index);
    } else {
        try jw.write(null);
    }
    try jw.objectField("resolved_friendly_name");
    if (resolved) |selection| {
        try jw.write(selection.resolved_friendly_name);
    } else {
        try jw.write(null);
    }
    try jw.endObject();
}

fn writeResolvedSelectionJson(jw: anytype, selection: *const ResolvedSelection) !void {
    try jw.beginObject();
    try jw.objectField("metadata_kind");
    try jw.write(selection.metadata_kind.displayName());
    try jw.objectField("metadata_source");
    try jw.write(selection.metadata_kind.sourcePath());
    try jw.objectField("selector_kind");
    try jw.write(selection.selectorKindName());
    try jw.objectField("requested_entry_index");
    try jw.write(selection.requestedEntryIndex());
    try jw.objectField("requested_name");
    try jw.write(selection.requestedName());
    try jw.objectField("resolved_entry_index");
    try jw.write(selection.resolved_entry_index);
    try jw.objectField("resolved_friendly_name");
    try jw.write(selection.resolved_friendly_name);
    try jw.endObject();
}

fn writeSceneJson(allocator: std.mem.Allocator, jw: anytype, scene: *const scene_data.SceneMetadata, assume_life_decoded: bool) !void {
    try jw.beginObject();
    try jw.objectField("entry_index");
    try jw.write(scene.entry_index);
    try jw.objectField("classic_loader_scene_number");
    try jw.write(scene.classicLoaderSceneNumber());
    try jw.objectField("scene_kind");
    try jw.write(scene.sceneKind());
    try jw.objectField("counts");
    try writeSceneCountsJson(jw, scene);
    try jw.objectField("compressed_header");
    try jw.write(scene.compressed_header);
    try jw.objectField("header");
    try writeSceneHeaderJson(jw, scene);
    try jw.objectField("hero_start");
    try writeHeroStartJson(allocator, jw, scene.hero_start, assume_life_decoded);
    try jw.endObject();
}

fn writeSceneCountsJson(jw: anytype, scene: *const scene_data.SceneMetadata) !void {
    try jw.beginObject();
    try jw.objectField("header_object_count");
    try jw.write(scene.object_count);
    try jw.objectField("decoded_actor_count");
    try jw.write(scene.objects.len);
    try jw.objectField("hero_count");
    try jw.write(@as(usize, 1));
    try jw.objectField("header_object_count_includes_hero");
    try jw.write(true);
    try jw.objectField("decoded_actor_count_matches_header_minus_hero");
    try jw.write(scene.objects.len + 1 == scene.object_count);
    try jw.endObject();
}

fn writeSceneHeaderJson(jw: anytype, scene: *const scene_data.SceneMetadata) !void {
    try jw.beginObject();
    try jw.objectField("island");
    try jw.write(scene.island);
    try jw.objectField("cube_x");
    try jw.write(scene.cube_x);
    try jw.objectField("cube_y");
    try jw.write(scene.cube_y);
    try jw.objectField("shadow_level");
    try jw.write(scene.shadow_level);
    try jw.objectField("mode_labyrinth");
    try jw.write(scene.mode_labyrinth);
    try jw.objectField("cube_mode");
    try jw.write(scene.cube_mode);
    try jw.objectField("unused_header_byte");
    try jw.write(scene.unused_header_byte);
    try jw.objectField("alpha_light");
    try jw.write(scene.alpha_light);
    try jw.objectField("beta_light");
    try jw.write(scene.beta_light);
    try jw.objectField("ambient_samples");
    try jw.write(scene.ambient_samples);
    try jw.objectField("second_min");
    try jw.write(scene.second_min);
    try jw.objectField("second_ecart");
    try jw.write(scene.second_ecart);
    try jw.objectField("cube_jingle");
    try jw.write(scene.cube_jingle);
    try jw.objectField("checksum");
    try jw.write(scene.checksum);
    try jw.objectField("object_count");
    try jw.write(scene.object_count);
    try jw.objectField("zone_count");
    try jw.write(scene.zone_count);
    try jw.objectField("track_count");
    try jw.write(scene.track_count);
    try jw.objectField("patch_count");
    try jw.write(scene.patch_count);
    try jw.endObject();
}

fn writeValidationJson(jw: anytype, validation: *const ValidationSnapshot) !void {
    try jw.beginObject();
    try jw.objectField("viewer_loadable");
    try jw.write(validation.viewer_loadable);
    try jw.objectField("scene_life");
    try writeSceneLifeValidationJson(jw, validation);
    try jw.objectField("scene_kind");
    try writeSceneKindValidationJson(jw, validation);
    try jw.objectField("fragment_zones");
    try writeFragmentZonesValidationJson(jw, validation);
    try jw.endObject();
}

fn writeSceneLifeValidationJson(jw: anytype, validation: *const ValidationSnapshot) !void {
    try jw.beginObject();
    try jw.objectField("status");
    try jw.write(@tagName(validation.scene_life_status));
    if (validation.unsupported_scene_life_hit) |hit| {
        try jw.objectField("unsupported");
        try writeUnsupportedSceneLifeHitJson(jw, hit);
    }
    try jw.endObject();
}

fn writeUnsupportedSceneLifeHitJson(jw: anytype, hit: room_state.UnsupportedSceneLifeHit) !void {
    try jw.beginObject();
    try jw.objectField("scene_entry_index");
    try jw.write(hit.scene_entry_index);
    try jw.objectField("classic_loader_scene_number");
    try jw.write(hit.classic_loader_scene_number);
    try jw.objectField("scene_kind");
    try jw.write(hit.scene_kind);
    try jw.objectField("owner");
    try writeLifeBlobOwnerJson(jw, hit.owner);
    try jw.objectField("unsupported_opcode_mnemonic");
    try jw.write(hit.unsupported_opcode_mnemonic);
    try jw.objectField("unsupported_opcode_id");
    try jw.write(hit.unsupported_opcode_id);
    try jw.objectField("byte_offset");
    try jw.write(hit.byte_offset);
    try jw.endObject();
}

fn writeLifeBlobOwnerJson(jw: anytype, owner: life_audit.LifeBlobOwner) !void {
    try jw.beginObject();
    switch (owner) {
        .hero => {
            try jw.objectField("kind");
            try jw.write("hero");
        },
        .object => |object_index| {
            try jw.objectField("kind");
            try jw.write("object");
            try jw.objectField("object_index");
            try jw.write(object_index);
        },
    }
    try jw.endObject();
}

fn writeSceneKindValidationJson(jw: anytype, validation: *const ValidationSnapshot) !void {
    try jw.beginObject();
    try jw.objectField("status");
    try jw.write(@tagName(validation.scene_kind_status));
    try jw.objectField("expected_scene_kind");
    try jw.write("interior");
    try jw.endObject();
}

fn writeFragmentZonesValidationJson(jw: anytype, validation: *const ValidationSnapshot) !void {
    try jw.beginObject();
    try jw.objectField("status");
    try jw.write(@tagName(validation.fragment_zones_status));
    if (validation.fragment_zones_skipped_reason) |reason| {
        try jw.objectField("skipped_reason");
        try jw.write(reason);
    }
    if (validation.fragment_zone_diagnostics) |diagnostics| {
        try jw.objectField("fragment_count");
        try jw.write(diagnostics.fragment_count);
        try jw.objectField("grm_zone_count");
        try jw.write(diagnostics.grm_zone_count);
        try jw.objectField("compatible_zone_count");
        try jw.write(diagnostics.compatible_zone_count);
        try jw.objectField("invalid_zone_count");
        try jw.write(diagnostics.invalid_zone_count);
        try jw.objectField("first_invalid_zone_index");
        try jw.write(diagnostics.first_invalid_zone_index);
        try jw.objectField("zones");
        try jw.write(diagnostics.zones);
    }
    try jw.endObject();
}

fn writeHeroStartJson(allocator: std.mem.Allocator, jw: anytype, hero_start: scene_data.HeroStart, assume_life_decoded: bool) !void {
    try jw.beginObject();
    try jw.objectField("position");
    try jw.write(.{ .x = hero_start.x, .y = hero_start.y, .z = hero_start.z });
    try jw.objectField("track");
    try writeTrackProgramJson(jw, hero_start.track.bytes, hero_start.track_instructions);
    try jw.objectField("life");
    try writeLifeProgramJson(allocator, jw, hero_start.life.bytes, assume_life_decoded);
    try jw.endObject();
}

fn writeBackgroundJson(
    jw: anytype,
    background: *const background_data.BackgroundMetadata,
    augmentation: ?*const room_state.RoomIntelligenceAugmentation,
) !void {
    try jw.beginObject();
    try jw.objectField("entry_index");
    try jw.write(background.entry_index);
    try jw.objectField("header_entry_index");
    try jw.write(background.header_entry_index);
    try jw.objectField("compressed_header");
    try jw.write(background.header_compressed_header);
    try jw.objectField("bkg_header");
    try jw.write(background.bkg_header);
    try jw.objectField("tab_all_cube_entry_index");
    try jw.write(background.tab_all_cube_entry_index);
    try jw.objectField("tab_all_cube_entry_count");
    try jw.write(background.tab_all_cube_entry_count);
    try jw.objectField("tab_all_cube");
    try jw.write(background.tab_all_cube);
    try jw.objectField("linkage");
    try jw.write(.{
        .remapped_cube_index = background.remapped_cube_index,
        .gri_entry_index = background.gri_entry_index,
        .gri_my_grm = background.gri_header.my_grm,
        .grm_entry_index = background.grm_entry_index,
        .gri_my_bll = background.gri_header.my_bll,
        .bll_entry_index = background.bll_entry_index,
    });
    try jw.objectField("used_blocks");
    try writeUsedBlocksJson(jw, background.used_blocks.raw_bytes, background.used_blocks.used_block_ids);
    try jw.objectField("column_table");
    try jw.write(background.column_table);
    try jw.objectField("composition");
    if (augmentation) |resolved_augmentation| {
        try writeCompositionJson(jw, resolved_augmentation.composition, background.composition.grid.summary());
    } else {
        try jw.write(background.composition.grid.summary());
    }
    try jw.objectField("layout_library");
    try jw.write(background.composition.library.summary());
    try jw.objectField("fragments");
    try jw.write(background.composition.fragments);
    try jw.objectField("bricks");
    try jw.write(background.composition.bricks);
    try jw.endObject();
}

fn writeCompositionJson(
    jw: anytype,
    composition: room_state.CompositionSnapshot,
    grid_summary: background_data.GridCompositionSummary,
) !void {
    try jw.beginObject();
    try jw.objectField("width");
    try jw.write(grid_summary.width);
    try jw.objectField("depth");
    try jw.write(grid_summary.depth);
    try jw.objectField("cell_count");
    try jw.write(grid_summary.cell_count);
    try jw.objectField("unique_offset_count");
    try jw.write(grid_summary.unique_offset_count);
    try jw.objectField("occupied_cell_count");
    try jw.write(composition.occupied_cell_count);
    try jw.objectField("occupied_bounds");
    try jw.write(composition.occupied_bounds);
    try jw.objectField("layout_count");
    try jw.write(composition.layout_count);
    try jw.objectField("max_layout_block_count");
    try jw.write(composition.max_layout_block_count);
    try jw.objectField("floor_type_counts");
    try jw.write(composition.floor_type_counts);
    try jw.objectField("max_total_height");
    try jw.write(composition.max_total_height);
    try jw.objectField("max_stack_depth");
    try jw.write(composition.max_stack_depth);
    try jw.objectField("height_grid");
    try writeByteArrayJson(jw, composition.height_grid);
    try jw.objectField("tiles");
    try writeCompositionTilesJson(jw, composition.tiles);
    try jw.endObject();
}

fn writeCompositionTilesJson(jw: anytype, tiles: []const room_state.CompositionTileSnapshot) !void {
    try jw.beginArray();
    for (tiles) |tile| {
        try jw.beginObject();
        try jw.objectField("x");
        try jw.write(tile.x);
        try jw.objectField("z");
        try jw.write(tile.z);
        try jw.objectField("total_height");
        try jw.write(tile.total_height);
        try jw.objectField("stack_depth");
        try jw.write(tile.stack_depth);
        try jw.objectField("top_floor_type");
        try jw.write(tile.top_floor_type);
        try jw.objectField("top_shape");
        try jw.write(tile.top_shape);
        try jw.objectField("top_shape_class");
        try jw.write(@tagName(tile.top_shape_class));
        try jw.objectField("top_brick_index");
        try jw.write(tile.top_brick_index);
        try jw.endObject();
    }
    try jw.endArray();
}

fn writeFragmentZonesJson(jw: anytype, fragment_zones: []const room_state.FragmentZoneSnapshot) !void {
    try jw.beginArray();
    for (fragment_zones) |zone| {
        try jw.beginObject();
        try jw.objectField("zone_index");
        try jw.write(zone.zone_index);
        try jw.objectField("zone_num");
        try jw.write(zone.zone_num);
        try jw.objectField("grm_index");
        try jw.write(zone.grm_index);
        try jw.objectField("fragment_entry_index");
        try jw.write(zone.fragment_entry_index);
        try jw.objectField("initially_on");
        try jw.write(zone.initially_on);
        try jw.objectField("y_min");
        try jw.write(zone.y_min);
        try jw.objectField("y_max");
        try jw.write(zone.y_max);
        try jw.objectField("origin_x");
        try jw.write(zone.origin_x);
        try jw.objectField("origin_z");
        try jw.write(zone.origin_z);
        try jw.objectField("width");
        try jw.write(zone.width);
        try jw.objectField("height");
        try jw.write(zone.height);
        try jw.objectField("depth");
        try jw.write(zone.depth);
        try jw.objectField("footprint_cell_count");
        try jw.write(zone.footprint_cell_count);
        try jw.objectField("non_empty_cell_count");
        try jw.write(zone.non_empty_cell_count);
        try jw.objectField("cells");
        try writeFragmentZoneCellsJson(jw, zone.cells);
        try jw.endObject();
    }
    try jw.endArray();
}

fn writeFragmentZoneCellsJson(jw: anytype, cells: []const room_state.FragmentZoneCellSnapshot) !void {
    try jw.beginArray();
    for (cells) |cell| {
        try jw.beginObject();
        try jw.objectField("x");
        try jw.write(cell.x);
        try jw.objectField("z");
        try jw.write(cell.z);
        try jw.objectField("has_non_empty");
        try jw.write(cell.has_non_empty);
        try jw.objectField("stack_depth");
        try jw.write(cell.stack_depth);
        try jw.objectField("top_floor_type");
        try jw.write(cell.top_floor_type);
        try jw.objectField("top_shape");
        try jw.write(cell.top_shape);
        try jw.objectField("top_shape_class");
        try jw.write(@tagName(cell.top_shape_class));
        try jw.objectField("top_brick_index");
        try jw.write(cell.top_brick_index);
        try jw.endObject();
    }
    try jw.endArray();
}

fn writeActorsJson(allocator: std.mem.Allocator, jw: anytype, actors: []const scene_data.SceneObject, assume_life_decoded: bool) !void {
    try jw.beginArray();
    for (actors) |actor| {
        try writeActorJson(allocator, jw, actor, assume_life_decoded);
    }
    try jw.endArray();
}

fn writeActorJson(allocator: std.mem.Allocator, jw: anytype, actor: scene_data.SceneObject, assume_life_decoded: bool) !void {
    try jw.beginObject();
    try jw.objectField("array_index");
    try jw.write(actor.index - 1);
    try jw.objectField("index");
    try jw.write(actor.index);
    try jw.objectField("scene_object_index");
    try jw.write(actor.index);
    try jw.objectField("raw");
    try writeActorRawJson(jw, actor);
    try jw.objectField("mapped");
    try writeActorMappedJson(jw, actor);
    try jw.objectField("track");
    try writeTrackProgramJson(jw, actor.track.bytes, actor.track_instructions);
    try jw.objectField("life");
    try writeLifeProgramJson(allocator, jw, actor.life.bytes, assume_life_decoded);
    try jw.endObject();
}

fn writeActorRawJson(jw: anytype, actor: scene_data.SceneObject) !void {
    try jw.beginObject();
    try jw.objectField("flags");
    try jw.write(actor.flags);
    try jw.objectField("file3d_index");
    try jw.write(actor.file3d_index);
    try jw.objectField("gen_body");
    try jw.write(actor.gen_body);
    try jw.objectField("gen_anim");
    try jw.write(actor.gen_anim);
    try jw.objectField("sprite");
    try jw.write(actor.sprite);
    try jw.objectField("x");
    try jw.write(actor.x);
    try jw.objectField("y");
    try jw.write(actor.y);
    try jw.objectField("z");
    try jw.write(actor.z);
    try jw.objectField("hit_force");
    try jw.write(actor.hit_force);
    try jw.objectField("option_flags");
    try jw.write(actor.option_flags);
    try jw.objectField("beta");
    try jw.write(actor.beta);
    try jw.objectField("speed_rotation");
    try jw.write(actor.speed_rotation);
    try jw.objectField("move");
    try jw.write(actor.move);
    try jw.objectField("info");
    try jw.write(actor.info);
    try jw.objectField("info1");
    try jw.write(actor.info1);
    try jw.objectField("info2");
    try jw.write(actor.info2);
    try jw.objectField("info3");
    try jw.write(actor.info3);
    try jw.objectField("bonus_count");
    try jw.write(actor.bonus_count);
    try jw.objectField("dominant_color");
    try jw.write(actor.dominant_color);
    try jw.objectField("armor");
    try jw.write(actor.armor);
    try jw.objectField("life_points");
    try jw.write(actor.life_points);
    try jw.objectField("anim_3ds_index");
    try jw.write(actor.anim_3ds_index);
    try jw.objectField("anim_3ds_fps");
    try jw.write(actor.anim_3ds_fps);
    try jw.endObject();
}

fn writeActorMappedJson(jw: anytype, actor: scene_data.SceneObject) !void {
    try jw.beginObject();
    try jw.objectField("position");
    try jw.write(.{ .x = actor.x, .y = actor.y, .z = actor.z });
    try jw.objectField("render_source");
    try jw.write(.{
        .file3d_index = actor.file3d_index,
        .gen_body = actor.gen_body,
        .gen_anim = actor.gen_anim,
        .sprite = actor.sprite,
        .anim_3ds_index = actor.anim_3ds_index,
        .anim_3ds_fps = actor.anim_3ds_fps,
    });
    try jw.objectField("movement");
    try jw.write(.{
        .move = actor.move,
        .beta = actor.beta,
        .speed_rotation = actor.speed_rotation,
    });
    try jw.objectField("combat");
    try jw.write(.{
        .hit_force = actor.hit_force,
        .armor = actor.armor,
        .life_points = actor.life_points,
        .bonus_count = actor.bonus_count,
    });
    try jw.objectField("flag_words");
    try writeFlagWordsJson(jw, actor.flags, @bitCast(actor.option_flags));
    try jw.objectField("info_fields");
    try jw.write(.{
        .info = actor.info,
        .info1 = actor.info1,
        .info2 = actor.info2,
        .info3 = actor.info3,
    });
    try jw.objectField("dominant_color");
    try jw.write(actor.dominant_color);
    try jw.endObject();
}

fn writeFlagWordsJson(jw: anytype, flags: u32, option_flags: u16) !void {
    try jw.beginObject();
    try jw.objectField("flags");
    try writeFlagWordJson(jw, u32, flags);
    try jw.objectField("option_flags");
    try writeFlagWordJson(jw, u16, option_flags);
    try jw.endObject();
}

fn writeFlagWordJson(jw: anytype, comptime Int: type, value: Int) !void {
    const bits = @typeInfo(Int).int.bits;
    try jw.beginObject();
    try jw.objectField("raw_unsigned");
    try jw.write(value);
    try jw.objectField("bit_width");
    try jw.write(bits);
    try jw.objectField("set_bits");
    try jw.beginArray();
    var bit_index: usize = 0;
    while (bit_index < bits) : (bit_index += 1) {
        if (((@as(u64, value) >> @intCast(bit_index)) & 1) == 0) continue;
        try jw.write(bit_index);
    }
    try jw.endArray();
    try jw.endObject();
}

fn writeTrackProgramJson(jw: anytype, bytes: []const u8, instructions: []const scene_data.TrackInstruction) !void {
    try jw.beginObject();
    try jw.objectField("byte_length");
    try jw.write(bytes.len);
    try jw.objectField("bytes");
    try writeByteArrayJson(jw, bytes);
    try jw.objectField("instruction_count");
    try jw.write(instructions.len);
    try jw.objectField("instructions");
    try jw.write(instructions);
    try jw.endObject();
}

fn writeLifeProgramJson(allocator: std.mem.Allocator, jw: anytype, bytes: []const u8, assume_decoded: bool) !void {
    const decoded_audit: ?life_program.LifeProgramAudit = if (assume_decoded)
        .{
            .instruction_count = undefined,
            .decoded_byte_length = bytes.len,
            .status = .decoded,
        }
    else
        null;
    const audit = decoded_audit orelse life_program.auditLifeProgram(bytes);
    try jw.beginObject();
    try jw.objectField("byte_length");
    try jw.write(bytes.len);
    try jw.objectField("bytes");
    try writeByteArrayJson(jw, bytes);
    try jw.objectField("instructions");
    if (assume_decoded) {
        const instructions = try life_program.decodeLifeProgram(allocator, bytes);
        defer allocator.free(instructions);
        try writeLifeInstructionsJson(jw, instructions);
        try jw.objectField("audit");
        try writeLifeAuditJson(jw, .{
            .instruction_count = instructions.len,
            .decoded_byte_length = bytes.len,
            .status = .decoded,
        });
    } else switch (audit.status) {
        .decoded => {
            const instructions = try life_program.decodeLifeProgram(allocator, bytes);
            defer allocator.free(instructions);
            try writeLifeInstructionsJson(jw, instructions);
            try jw.objectField("audit");
            try writeLifeAuditJson(jw, audit);
        },
        else => {
            try jw.write(null);
            try jw.objectField("audit");
            try writeLifeAuditJson(jw, audit);
        },
    }
    try jw.endObject();
}

fn writeLifeInstructionsJson(jw: anytype, instructions: []const life_program.LifeInstruction) !void {
    try jw.beginArray();
    for (instructions) |instruction| {
        try writeLifeInstructionJson(jw, instruction);
    }
    try jw.endArray();
}

fn writeLifeInstructionJson(jw: anytype, instruction: life_program.LifeInstruction) !void {
    try jw.beginObject();
    try jw.objectField("offset");
    try jw.write(instruction.offset);
    try jw.objectField("opcode");
    try jw.write(@intFromEnum(instruction.opcode));
    try jw.objectField("mnemonic");
    try jw.write(instruction.opcode.mnemonic());
    try jw.objectField("byte_length");
    try jw.write(instruction.byte_length);
    try jw.objectField("operands");
    try writeLifeOperandsJson(jw, instruction.operands);
    if (instruction.semanticOperand()) |semantic| {
        try jw.objectField("semantic");
        try writeLifeSemanticJson(jw, semantic);
    }
    try jw.endObject();
}

fn writeLifeOperandsJson(jw: anytype, operands: life_program.LifeOperands) !void {
    try jw.beginObject();
    switch (operands) {
        .none => {
            try jw.objectField("kind");
            try jw.write("none");
            try jw.objectField("value");
            try jw.beginObject();
            try jw.endObject();
        },
        .u8_value => |value| {
            try jw.objectField("kind");
            try jw.write("u8_value");
            try jw.objectField("value");
            try jw.write(value);
        },
        .i8_value => |value| {
            try jw.objectField("kind");
            try jw.write("i8_value");
            try jw.objectField("value");
            try jw.write(value);
        },
        .u16_value => |value| {
            try jw.objectField("kind");
            try jw.write("u16_value");
            try jw.objectField("value");
            try jw.write(value);
        },
        .i16_value => |value| {
            try jw.objectField("kind");
            try jw.write("i16_value");
            try jw.objectField("value");
            try jw.write(value);
        },
        .u8_pair => |value| {
            try jw.objectField("kind");
            try jw.write("u8_pair");
            try jw.objectField("value");
            try jw.write(value);
        },
        .u8_i8 => |value| {
            try jw.objectField("kind");
            try jw.write("u8_i8");
            try jw.objectField("value");
            try jw.write(value);
        },
        .u8_i16 => |value| {
            try jw.objectField("kind");
            try jw.write("u8_i16");
            try jw.objectField("value");
            try jw.write(value);
        },
        .i16_u8 => |value| {
            try jw.objectField("kind");
            try jw.write("i16_u8");
            try jw.objectField("value");
            try jw.write(value);
        },
        .u8_u16 => |value| {
            try jw.objectField("kind");
            try jw.write("u8_u16");
            try jw.objectField("value");
            try jw.write(value);
        },
        .u8_u16_i16 => |value| {
            try jw.objectField("kind");
            try jw.write("u8_u16_i16");
            try jw.objectField("value");
            try jw.write(value);
        },
        .u8_u8_u8_i16 => |value| {
            try jw.objectField("kind");
            try jw.write("u8_u8_u8_i16");
            try jw.objectField("value");
            try jw.write(value);
        },
        .i16_u8_i16 => |value| {
            try jw.objectField("kind");
            try jw.write("i16_u8_i16");
            try jw.objectField("value");
            try jw.write(value);
        },
        .i16_i16_u8_i16 => |value| {
            try jw.objectField("kind");
            try jw.write("i16_i16_u8_i16");
            try jw.objectField("value");
            try jw.write(value);
        },
        .move => |value| {
            try jw.objectField("kind");
            try jw.write("move");
            try jw.objectField("value");
            try jw.write(value);
        },
        .move_obj => |value| {
            try jw.objectField("kind");
            try jw.write("move_obj");
            try jw.objectField("value");
            try jw.write(value);
        },
        .string => |value| {
            try jw.objectField("kind");
            try jw.write("string");
            try jw.objectField("value");
            try jw.write(value);
        },
        .condition => |value| {
            try jw.objectField("kind");
            try jw.write("condition");
            try jw.objectField("value");
            try writeLifeConditionJson(jw, value);
        },
        .switch_expr => |value| {
            try jw.objectField("kind");
            try jw.write("switch_expr");
            try jw.objectField("value");
            try writeLifeSwitchExpressionJson(jw, value);
        },
        .case_branch => |value| {
            try jw.objectField("kind");
            try jw.write("case_branch");
            try jw.objectField("value");
            try writeLifeCaseBranchJson(jw, value);
        },
    }
    try jw.endObject();
}

fn writeLifeConditionJson(jw: anytype, value: life_program.LifeCondition) !void {
    try jw.beginObject();
    try jw.objectField("function");
    try writeLifeFunctionCallJson(jw, value.function);
    try jw.objectField("comparison");
    try writeLifeTestJson(jw, value.comparison);
    try jw.objectField("jump_offset");
    try jw.write(value.jump_offset);
    try jw.endObject();
}

fn writeLifeSemanticJson(jw: anytype, semantic: life_program.LifeInstructionSemantic) !void {
    try jw.beginObject();
    switch (semantic) {
        .move_mode => |value| {
            try jw.objectField("kind");
            try jw.write("move_mode");
            try jw.objectField("value");
            try jw.write(value);
        },
        .move_mode_obj => |value| {
            try jw.objectField("kind");
            try jw.write("move_mode_obj");
            try jw.objectField("value");
            try jw.write(value);
        },
        .hero_behaviour => |value| {
            try jw.objectField("kind");
            try jw.write("hero_behaviour");
            try jw.objectField("value");
            try jw.write(value);
        },
        .can_fall => |value| {
            try jw.objectField("kind");
            try jw.write("can_fall");
            try jw.objectField("value");
            try jw.write(value);
        },
        .brick_collision => |value| {
            try jw.objectField("kind");
            try jw.write("brick_collision");
            try jw.objectField("value");
            try jw.write(value);
        },
        .binary_toggle => |value| {
            try jw.objectField("kind");
            try jw.write("binary_toggle");
            try jw.objectField("value");
            try jw.write(value);
        },
        .buggy_init => |value| {
            try jw.objectField("kind");
            try jw.write("buggy_init");
            try jw.objectField("value");
            try jw.write(value);
        },
        .zone_toggle => |value| {
            try jw.objectField("kind");
            try jw.write("zone_toggle");
            try jw.objectField("value");
            try jw.write(value);
        },
        .pcx_message => |value| {
            try jw.objectField("kind");
            try jw.write("pcx_message");
            try jw.objectField("value");
            try jw.write(value);
        },
    }
    try jw.endObject();
}

fn writeLifeSwitchExpressionJson(jw: anytype, value: life_program.LifeSwitchExpression) !void {
    try jw.beginObject();
    try jw.objectField("function");
    try writeLifeFunctionCallJson(jw, value.function);
    try jw.endObject();
}

fn writeLifeCaseBranchJson(jw: anytype, value: life_program.LifeCaseBranch) !void {
    try jw.beginObject();
    try jw.objectField("jump_offset");
    try jw.write(value.jump_offset);
    try jw.objectField("switch_return_type");
    try writeLifeReturnTypeJson(jw, value.switch_return_type);
    try jw.objectField("comparison");
    try writeLifeTestJson(jw, value.comparison);
    try jw.endObject();
}

fn writeLifeFunctionCallJson(jw: anytype, value: life_program.LifeFunctionCall) !void {
    try jw.beginObject();
    try jw.objectField("offset");
    try jw.write(value.offset);
    try jw.objectField("function");
    try jw.write(@intFromEnum(value.function));
    try jw.objectField("mnemonic");
    try jw.write(value.function.mnemonic());
    try jw.objectField("byte_length");
    try jw.write(value.byte_length);
    try jw.objectField("return_type");
    try writeLifeReturnTypeJson(jw, value.return_type);
    try jw.objectField("operands");
    try writeLifeFunctionOperandsJson(jw, value.operands);
    try jw.endObject();
}

fn writeLifeFunctionOperandsJson(jw: anytype, operands: life_program.LifeFunctionOperands) !void {
    try jw.beginObject();
    switch (operands) {
        .none => {
            try jw.objectField("kind");
            try jw.write("none");
            try jw.objectField("value");
            try jw.beginObject();
            try jw.endObject();
        },
        .u8_value => |value| {
            try jw.objectField("kind");
            try jw.write("u8_value");
            try jw.objectField("value");
            try jw.write(value);
        },
    }
    try jw.endObject();
}

fn writeLifeTestJson(jw: anytype, value: life_program.LifeTest) !void {
    try jw.beginObject();
    try jw.objectField("offset");
    try jw.write(value.offset);
    try jw.objectField("comparator");
    try jw.write(@intFromEnum(value.comparator));
    try jw.objectField("mnemonic");
    try jw.write(value.comparator.mnemonic());
    try jw.objectField("byte_length");
    try jw.write(value.byte_length);
    try jw.objectField("return_type");
    try writeLifeReturnTypeJson(jw, value.return_type);
    try jw.objectField("literal");
    try writeLifeTestLiteralJson(jw, value.literal);
    try jw.endObject();
}

fn writeLifeTestLiteralJson(jw: anytype, literal: life_program.LifeTestLiteral) !void {
    try jw.beginObject();
    switch (literal) {
        .s8_value => |value| {
            try jw.objectField("kind");
            try jw.write("s8_value");
            try jw.objectField("value");
            try jw.write(value);
        },
        .u8_value => |value| {
            try jw.objectField("kind");
            try jw.write("u8_value");
            try jw.objectField("value");
            try jw.write(value);
        },
        .s16_value => |value| {
            try jw.objectField("kind");
            try jw.write("s16_value");
            try jw.objectField("value");
            try jw.write(value);
        },
        .string => |value| {
            try jw.objectField("kind");
            try jw.write("string");
            try jw.objectField("value");
            try jw.write(value);
        },
    }
    try jw.endObject();
}

fn writeLifeReturnTypeJson(jw: anytype, return_type: life_program.LifeReturnType) !void {
    try jw.beginObject();
    try jw.objectField("id");
    try jw.write(@intFromEnum(return_type));
    try jw.objectField("mnemonic");
    try jw.write(return_type.mnemonic());
    try jw.endObject();
}

fn writeLifeAuditJson(jw: anytype, audit: life_program.LifeProgramAudit) !void {
    try jw.beginObject();
    try jw.objectField("status");
    try jw.write(lifeAuditStatusName(audit.status));
    try jw.objectField("instruction_count");
    try jw.write(audit.instruction_count);
    try jw.objectField("decoded_byte_length");
    try jw.write(audit.decoded_byte_length);

    switch (audit.status) {
        .unsupported_opcode => |hit| {
            try jw.objectField("unsupported");
            try jw.write(.{
                .opcode_id = hit.opcode_id,
                .mnemonic = hit.opcode.mnemonic(),
                .offset = hit.offset,
            });
        },
        .unknown_opcode => |hit| {
            try jw.objectField("failure");
            try jw.write(.{
                .kind = lifeAuditStatusName(audit.status),
                .opcode_id = hit.opcode_id,
                .offset = hit.offset,
            });
        },
        .truncated_operand,
        .malformed_string_operand,
        .missing_switch_context,
        .unknown_life_function,
        .unknown_life_comparator,
        => {
            try jw.objectField("failure");
            try jw.write(.{ .kind = lifeAuditStatusName(audit.status) });
        },
        .decoded => {},
    }

    try jw.endObject();
}

fn lifeAuditStatusName(status: life_program.LifeProgramAuditStatus) []const u8 {
    return switch (status) {
        .decoded => "decoded",
        .unsupported_opcode => "unsupported_opcode",
        .unknown_opcode => "unknown_opcode",
        .truncated_operand => "truncated_operand",
        .malformed_string_operand => "malformed_string_operand",
        .missing_switch_context => "missing_switch_context",
        .unknown_life_function => "unknown_life_function",
        .unknown_life_comparator => "unknown_life_comparator",
    };
}

fn writeUsedBlocksJson(jw: anytype, raw_bytes: [32]u8, values: []const u8) !void {
    try jw.beginObject();
    try jw.objectField("raw_bytes");
    try jw.write(raw_bytes);
    try jw.objectField("count");
    try jw.write(values.len);
    try jw.objectField("values");
    try writeByteArrayJson(jw, values);
    try jw.endObject();
}

fn writeByteArrayJson(jw: anytype, bytes: []const u8) !void {
    try jw.beginArray();
    for (bytes) |byte| try jw.write(byte);
    try jw.endArray();
}

fn testMetadataEntry(
    entry_index: usize,
    display_name: []const u8,
    normalized_name: []const u8,
) RoomMetadataEntry {
    return .{
        .entry_index = entry_index,
        .display_name = display_name,
        .normalized_name = normalized_name,
    };
}

fn expectGeneratedEntriesUseRuntimeNormalization(
    allocator: std.mem.Allocator,
    entries: []const RoomMetadataEntry,
) !void {
    for (entries) |entry| {
        const normalized = try normalizeSearchKeyAlloc(allocator, entry.display_name);
        defer allocator.free(normalized);
        try std.testing.expectEqualStrings(entry.normalized_name, normalized);
    }
}

test "generated room metadata normalized names stay in sync with runtime normalization" {
    try expectGeneratedEntriesUseRuntimeNormalization(std.testing.allocator, room_metadata.scene_entries);
    try expectGeneratedEntriesUseRuntimeNormalization(std.testing.allocator, room_metadata.background_entries);
}

test "scene metadata resolution supports exact friendly-name matches" {
    const entries = [_]RoomMetadataEntry{
        testMetadataEntry(2, "Scene 0: Citadel Island, Twinsen's house", "scene 0 citadel island twinsen s house"),
        testMetadataEntry(3, "Scene 1: Desert Island, Tavern", "scene 1 desert island tavern"),
    };
    const selection = try resolveSelectionFromEntriesAlloc(
        std.testing.allocator,
        .scene,
        .{ .name = "Scene 0: Citadel Island, Twinsen's house" },
        &entries,
    );
    defer selection.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), selection.resolved_entry_index);
    try std.testing.expectEqualStrings("Scene 0: Citadel Island, Twinsen's house", selection.resolved_friendly_name.?);
}

test "background metadata resolution supports suffix friendly-name matches" {
    const entries = [_]RoomMetadataEntry{
        testMetadataEntry(2, "Grid 0: Citadel Island, Twinsen's house", "grid 0 citadel island twinsen s house"),
        testMetadataEntry(3, "Grid 1: Desert Island, Tavern", "grid 1 desert island tavern"),
    };
    const selection = try resolveSelectionFromEntriesAlloc(
        std.testing.allocator,
        .background,
        .{ .name = "Tavern" },
        &entries,
    );
    defer selection.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), selection.resolved_entry_index);
    try std.testing.expectEqualStrings("Grid 1: Desert Island, Tavern", selection.resolved_friendly_name.?);
}

test "metadata resolution rejects ambiguous suffix matches" {
    const entries = [_]RoomMetadataEntry{
        testMetadataEntry(2, "Scene 0: Desert Island, Tavern", "scene 0 desert island tavern"),
        testMetadataEntry(3, "Scene 1: Rebellion Island, Tavern", "scene 1 rebellion island tavern"),
    };
    try std.testing.expectError(
        error.AmbiguousSceneName,
        resolveSelectionFromEntriesAlloc(
            std.testing.allocator,
            .scene,
            .{ .name = "Tavern" },
            &entries,
        ),
    );
}

test "metadata resolution rejects unknown friendly names" {
    const entries = [_]RoomMetadataEntry{
        testMetadataEntry(2, "Grid 0: Citadel Island, Twinsen's house", "grid 0 citadel island twinsen s house"),
    };
    try std.testing.expectError(
        error.UnknownBackgroundName,
        resolveSelectionFromEntriesAlloc(
            std.testing.allocator,
            .background,
            .{ .name = "Does Not Exist" },
            &entries,
        ),
    );
}

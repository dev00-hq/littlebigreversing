const std = @import("std");
const builtin = @import("builtin");
const diagnostics = @import("../foundation/diagnostics.zig");
const process = @import("../foundation/process.zig");
const paths_mod = @import("../foundation/paths.zig");
const catalog = @import("../assets/catalog.zig");
const fixtures = @import("../assets/fixtures.zig");
const hqr = @import("../assets/hqr.zig");
const reference_metadata = @import("../assets/reference_metadata.zig");
const background_data = @import("../game_data/background.zig");
const scene_data = @import("../game_data/scene.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const life_audit = @import("../game_data/scene/life_audit.zig");
const locomotion = @import("../runtime/locomotion.zig");
const runtime_query = @import("../runtime/world_query.zig");
const runtime_session = @import("../runtime/session.zig");
const runtime_transition = @import("../runtime/transition.zig");
const room_entry_state = @import("../runtime/room_entry_state.zig");
const room_state = @import("../runtime/room_state.zig");
const zone_effects = @import("../runtime/zone_effects.zig");
const room_intelligence = @import("room_intelligence.zig");
const room_fixtures = if (builtin.is_test) @import("../testing/room_fixtures.zig") else struct {};

const Command = enum {
    inventory_assets,
    inspect_hqr,
    inspect_background,
    extract_entry,
    inspect_scene,
    inspect_room,
    inspect_room_transitions,
    inspect_room_intelligence,
    inspect_room_fragment_zones,
    audit_life_programs,
    rank_decoded_interior_candidates,
    triage_same_index_decoded_interior_candidates,
    inspect_life_catalog,
    inspect_life_program,
    generate_fixtures,
    validate_phase1,
};

const ParsedArgs = struct {
    command: Command,
    asset_root_override: ?[]u8,
    output_path: ?[]const u8 = null,
    relative_path: ?[]const u8,
    entry_index: ?usize,
    background_entry_index: ?usize,
    scene_name: ?[]const u8 = null,
    background_name: ?[]const u8 = null,
    audit_scene_entry_indices: ?[]usize,
    audit_all_scene_entries: bool,
    life_program_owner: ?life_audit.LifeBlobOwner,
    output_json: bool,

    fn deinit(self: ParsedArgs, allocator: std.mem.Allocator) void {
        if (self.asset_root_override) |value| allocator.free(value);
        if (self.audit_scene_entry_indices) |value| allocator.free(value);
    }

    fn lifeAuditSelection(self: ParsedArgs) life_audit.AuditSceneSelection {
        if (self.audit_scene_entry_indices) |scene_entry_indices| {
            return .{ .explicit_entries = scene_entry_indices };
        }
        if (self.audit_all_scene_entries) return .{ .all_scene_entries = {} };
        return .{ .canonical = {} };
    }

    fn lifeAuditSelectionMode(self: ParsedArgs) []const u8 {
        if (self.audit_scene_entry_indices != null) return "explicit_entries";
        if (self.audit_all_scene_entries) return "all_scene_entries";
        return "canonical";
    }
};

const RoomHeroStartSummary = struct {
    x: i16,
    y: i16,
    z: i16,
    track_byte_length: u16,
    life_byte_length: u16,
};

const RoomSceneSummary = struct {
    entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    hero_start: RoomHeroStartSummary,
    object_count: usize,
    zone_count: usize,
    track_count: usize,
    patch_count: usize,
};

const inspect_room_intelligence_timings_env_var = "LBA2_INSPECT_ROOM_INTELLIGENCE_TIMINGS";

const InspectRoomIntelligenceTimings = struct {
    enabled: bool,
    output_path: ?[]const u8,
    start_ns: u64 = 0,
    phase_start_ns: u64 = 0,
    selection_ns: u64 = 0,
    scene_load_ns: u64 = 0,
    background_load_ns: u64 = 0,
    validation_ns: u64 = 0,
    augmentation_ns: u64 = 0,
    augmentation_ran: bool = false,
    serialization_ns: u64 = 0,

    fn init(allocator: std.mem.Allocator, output_path: ?[]const u8) !InspectRoomIntelligenceTimings {
        if (!(try inspectRoomIntelligenceTimingsEnabled(allocator))) {
            return .{
                .enabled = false,
                .output_path = output_path,
            };
        }

        return .{
            .enabled = true,
            .output_path = output_path,
            .start_ns = nowNs(),
        };
    }

    fn markSelection(self: *InspectRoomIntelligenceTimings) void {
        if (!self.enabled) return;
        self.selection_ns = self.finishPhase();
    }

    fn markSceneLoad(self: *InspectRoomIntelligenceTimings) void {
        if (!self.enabled) return;
        self.scene_load_ns = self.finishPhase();
    }

    fn markBackgroundLoad(self: *InspectRoomIntelligenceTimings) void {
        if (!self.enabled) return;
        self.background_load_ns = self.finishPhase();
    }

    fn markValidation(self: *InspectRoomIntelligenceTimings) void {
        if (!self.enabled) return;
        self.validation_ns = self.finishPhase();
    }

    fn markAugmentation(self: *InspectRoomIntelligenceTimings) void {
        if (!self.enabled) return;
        self.augmentation_ran = true;
        self.augmentation_ns = self.finishPhase();
    }

    fn markSerialization(self: *InspectRoomIntelligenceTimings) void {
        if (!self.enabled) return;
        self.serialization_ns = self.finishPhase();
    }

    fn flush(self: *InspectRoomIntelligenceTimings) void {
        if (!self.enabled) return;

        var stderr_buffer: [512]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
        const stderr = &stderr_writer.interface;
        stderr.print(
            "inspect_room_intelligence_timings env_var={s} output={s} selection_ms={d} scene_load_ms={d} background_load_ms={d} validation_ms={d} augmentation_ms={d} augmentation_ran={} serialization_ms={d} total_ms={d}\n",
            .{
                inspect_room_intelligence_timings_env_var,
                if (self.output_path != null) "file" else "stdout",
                self.selection_ns / std.time.ns_per_ms,
                self.scene_load_ns / std.time.ns_per_ms,
                self.background_load_ns / std.time.ns_per_ms,
                self.validation_ns / std.time.ns_per_ms,
                self.augmentation_ns / std.time.ns_per_ms,
                self.augmentation_ran,
                self.serialization_ns / std.time.ns_per_ms,
                (nowNs() - self.start_ns) / std.time.ns_per_ms,
            },
        ) catch return;
        stderr.flush() catch return;
    }

    fn finishPhase(self: *InspectRoomIntelligenceTimings) u64 {
        const now = nowNs() - self.start_ns;
        const elapsed = now - self.phase_start_ns;
        self.phase_start_ns = now;
        return elapsed;
    }
};

fn nowNs() u64 {
    const timestamp = std.Io.Clock.Timestamp.now(process.currentIo(), .awake);
    return @intCast(timestamp.raw.nanoseconds);
}

fn inspectRoomIntelligenceTimingsEnabled(allocator: std.mem.Allocator) !bool {
    _ = allocator;
    const value = process.currentEnv().get(inspect_room_intelligence_timings_env_var) orelse return false;

    return !std.mem.eql(u8, value, "0") and !std.ascii.eqlIgnoreCase(value, "false");
}

const RoomBackgroundLinkageSummary = struct {
    remapped_cube_index: usize,
    gri_entry_index: usize,
    gri_my_grm: u8,
    grm_entry_index: usize,
    gri_my_bll: u8,
    bll_entry_index: usize,
};

const RoomUsedBlocksSummary = struct {
    count: usize,
    values: []const u8,
};

const RoomColumnTableSummary = struct {
    width: usize,
    depth: usize,
    offset_count: usize,
    table_byte_length: usize,
    data_byte_length: usize,
    min_offset: u16,
    max_offset: u16,
};

const RoomCompositionSummary = struct {
    occupied_cell_count: usize,
    occupied_bounds: ?background_data.GridBounds,
    layout_count: usize,
    max_layout_block_count: usize,
};

const RoomFragmentSummary = struct {
    fragment_count: usize,
    footprint_cell_count: usize,
    non_empty_cell_count: usize,
    max_height: u8,
};

const RoomBrickPreviewSummary = struct {
    palette_entry_index: usize,
    preview_count: usize,
    max_preview_width: u8,
    max_preview_height: u8,
    total_opaque_pixel_count: usize,
};

const RoomBackgroundSummary = struct {
    entry_index: usize,
    linkage: RoomBackgroundLinkageSummary,
    used_blocks: RoomUsedBlocksSummary,
    column_table: RoomColumnTableSummary,
    composition: RoomCompositionSummary,
    fragments: RoomFragmentSummary,
    bricks: RoomBrickPreviewSummary,
};

const RoomInspectionPayload = struct {
    command: []const u8,
    scene: RoomSceneSummary,
    background: RoomBackgroundSummary,
};

const RoomTransitionWorldPositionSummary = struct {
    x: i32,
    y: i32,
    z: i32,
};

const RoomTransitionGridCellSummary = struct {
    x: usize,
    z: usize,
};

const RoomTransitionRawCellSummary = struct {
    world_x: i32,
    world_z: i32,
    cell: ?RoomTransitionGridCellSummary,
    status: []const u8,
    occupied: bool,
    surface_top_y: ?i32,
    surface_total_height: ?u8,
    surface_stack_depth: ?u8,
    surface_floor_type: ?u8,
    surface_shape_class: ?[]const u8,
    standability: ?[]const u8,
};

const RoomTransitionOccupiedCoverageSummary = struct {
    relation: []const u8,
    occupied_bounds: ?room_state.CompositionBoundsSnapshot,
    x_cells_from_bounds: usize,
    z_cells_from_bounds: usize,
};

const RoomTransitionWorldBoundsSummary = struct {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
};

const RoomTransitionDiagnosticCandidateSummary = struct {
    cell: RoomTransitionGridCellSummary,
    world_bounds: RoomTransitionWorldBoundsSummary,
    surface_top_y: i32,
    surface_total_height: u8,
    surface_stack_depth: u8,
    surface_floor_type: u8,
    surface_shape_class: []const u8,
    standability: []const u8,
    x_distance: i32,
    z_distance: i32,
    distance_sq: i64,
};

const RoomTransitionPostLoadDiagnosticsSummary = struct {
    move_target_status: []const u8,
    shadow_adjustment_failure: ?[]const u8,
    provisional_world_position: RoomTransitionWorldPositionSummary,
    raw_cell: RoomTransitionRawCellSummary,
    occupied_coverage: RoomTransitionOccupiedCoverageSummary,
    nearest_occupied: ?RoomTransitionDiagnosticCandidateSummary,
    nearest_standable: ?RoomTransitionDiagnosticCandidateSummary,
};

const RoomTransitionRuntimeEffectSummary = struct {
    little_keys_before: u8,
    little_keys_after: u8,
    triggered_room_transition: bool,
    secret_room_door_event: ?[]const u8,
    pending_destination_cube: ?i16,
    pending_destination_world_position: ?RoomTransitionWorldPositionSummary,
    result: ?[]const u8,
    rejection_reason: ?[]const u8,
    destination_scene_entry_index: ?usize,
    destination_background_entry_index: ?usize,
    hero_position: ?RoomTransitionWorldPositionSummary,
    post_load_diagnostics: ?RoomTransitionPostLoadDiagnosticsSummary,
};

const RoomTransitionProbeSummary = struct {
    source_kind: []const u8,
    source_zone_index: usize,
    source_zone_num: i16,
    destination_cube: i16,
    destination_world_position_kind: []const u8,
    destination_world_position: RoomTransitionWorldPositionSummary,
    yaw: i32,
    test_brick: bool,
    dont_readjust_twinsen: bool,
    result: []const u8,
    rejection_reason: ?[]const u8,
    destination_scene_entry_index: ?usize,
    destination_background_entry_index: ?usize,
    hero_position: RoomTransitionWorldPositionSummary,
    post_load_diagnostics: ?RoomTransitionPostLoadDiagnosticsSummary,
    runtime_probe_position: ?RoomTransitionWorldPositionSummary,
    runtime_no_key_effect: ?RoomTransitionRuntimeEffectSummary,
    runtime_with_key_effect: ?RoomTransitionRuntimeEffectSummary,
};

const RoomTransitionInspectionPayload = struct {
    command: []const u8,
    source_scene_entry_index: usize,
    source_background_entry_index: usize,
    transition_count: usize,
    transitions: []const RoomTransitionProbeSummary,
};

const RoomFragmentZoneDiagnosticSummary = struct {
    zone_index: usize,
    zone_num: i16,
    grm_index: i32,
    initially_on: bool,
    issue: []const u8,
    fragment_entry_index: ?usize,
    fragment_dimensions: ?room_state.FragmentDimensionsSnapshot,
    x_axis: room_state.FragmentZoneAxisDiagnostic,
    y_axis: room_state.FragmentZoneAxisDiagnostic,
    z_axis: room_state.FragmentZoneAxisDiagnostic,
};

const RoomFragmentZoneDiagnosticsPayload = struct {
    command: []const u8,
    scene_entry_index: usize,
    background_entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    fragment_count: usize,
    grm_zone_count: usize,
    compatible_zone_count: usize,
    invalid_zone_count: usize,
    first_invalid_zone_index: ?usize,
    zones: []const RoomFragmentZoneDiagnosticSummary,
};

const RankedDecodedInteriorCandidateSummary = struct {
    rank: usize,
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    blob_count: usize,
    object_count: usize,
    zone_count: usize,
    track_count: usize,
    patch_count: usize,
    is_current_supported_baseline: bool,
};

const RankedDecodedInteriorCandidatesPayload = struct {
    command: []const u8,
    ranking_basis: []const []const u8,
    candidate_count: usize,
    current_supported_baseline_scene_entry_index: usize,
    current_supported_baseline_rank: usize,
    current_supported_baseline_is_top_candidate: bool,
    top_candidate: RankedDecodedInteriorCandidateSummary,
    current_supported_baseline: RankedDecodedInteriorCandidateSummary,
    candidates: []const RankedDecodedInteriorCandidateSummary,
};

const SameIndexDecodedInteriorCandidateTriageSummary = struct {
    rank: usize,
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    blob_count: usize,
    object_count: usize,
    zone_count: usize,
    track_count: usize,
    patch_count: usize,
    is_current_supported_baseline: bool,
    fragment_count: usize,
    grm_zone_count: usize,
    compatible_zone_count: usize,
    invalid_zone_count: usize,
    first_invalid_zone_index: ?usize,
    first_invalid_issue: ?[]const u8,
    first_invalid_axis: ?[]const u8,
    first_invalid_failure_reason: ?[]const u8,
    first_invalid_zone_num: ?i16,
    first_invalid_grm_index: ?i32,
    first_invalid_fragment_entry_index: ?usize,
    compatible: bool,
};

const SameIndexDecodedInteriorCandidateTriagePayload = struct {
    command: []const u8,
    ranking_basis: []const []const u8,
    candidate_count: usize,
    compatible_candidate_count: usize,
    compatible_candidate_count_above_baseline: usize,
    current_supported_baseline_scene_entry_index: usize,
    current_supported_baseline_rank: usize,
    current_supported_baseline: SameIndexDecodedInteriorCandidateTriageSummary,
    highest_ranked_compatible_candidate: ?SameIndexDecodedInteriorCandidateTriageSummary,
    highest_ranked_compatible_candidate_outranks_current_supported_baseline: bool,
    highest_ranked_compatible_candidate_above_baseline: ?SameIndexDecodedInteriorCandidateTriageSummary,
    highest_ranked_fragment_bearing_compatible_candidate: ?SameIndexDecodedInteriorCandidateTriageSummary,
    highest_ranked_fragment_bearing_compatible_candidate_outranks_current_supported_baseline: bool,
    highest_ranked_fragment_bearing_compatible_candidate_above_baseline: ?SameIndexDecodedInteriorCandidateTriageSummary,
    candidates: []const SameIndexDecodedInteriorCandidateTriageSummary,
};

const FirstInvalidFragmentZoneSummary = struct {
    zone_index: usize,
    zone_num: i16,
    grm_index: i32,
    fragment_entry_index: ?usize,
    issue: []const u8,
    axis: []const u8,
    failure_reason: []const u8,
};

const InspectHqrEntryPayload = struct {
    index: usize,
    offset: u32,
    byte_length: u32,
    sha256: []const u8,
    entry_type: ?[]const u8,
    entry_description: ?[]const u8,
};

const InspectHqrPayload = struct {
    asset_path: []const u8,
    entry_count: usize,
    entries: []InspectHqrEntryPayload,
};

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const parsed = parseArgs(allocator, args) catch |err| {
        if (try maybeEmitInspectRoomIntelligenceParseFailure(allocator, args, err)) {
            return error.MachineReadableReported;
        }
        return err;
    };
    defer parsed.deinit(allocator);

    const resolved = try paths_mod.resolveFromExecutable(allocator, parsed.asset_root_override);
    defer resolved.deinit(allocator);

    switch (parsed.command) {
        .inventory_assets => try inventoryAssets(allocator, resolved),
        .inspect_hqr => try inspectHqr(allocator, resolved, parsed.relative_path.?, parsed.output_json),
        .inspect_background => try inspectBackground(allocator, resolved, parsed.entry_index.?, parsed.output_json),
        .extract_entry => try extractEntry(allocator, resolved, parsed.relative_path.?, parsed.entry_index.?),
        .inspect_scene => try inspectScene(allocator, resolved, parsed.entry_index.?, parsed.output_json),
        .inspect_room => try inspectRoom(allocator, resolved, parsed.entry_index.?, parsed.background_entry_index.?, parsed.output_json),
        .inspect_room_transitions => try inspectRoomTransitions(allocator, resolved, parsed.entry_index.?, parsed.background_entry_index.?, parsed.output_json),
        .inspect_room_intelligence => try inspectRoomIntelligence(allocator, resolved, parsed),
        .inspect_room_fragment_zones => try inspectRoomFragmentZones(allocator, resolved, parsed.entry_index.?, parsed.background_entry_index.?, parsed.output_json),
        .audit_life_programs => try auditLifePrograms(allocator, resolved, parsed),
        .rank_decoded_interior_candidates => try rankDecodedInteriorCandidates(allocator, resolved, parsed.output_json),
        .triage_same_index_decoded_interior_candidates => try triageSameIndexDecodedInteriorCandidates(allocator, resolved, parsed.output_json),
        .inspect_life_catalog => try inspectLifeCatalog(allocator, parsed.output_json),
        .inspect_life_program => try inspectLifeProgram(allocator, resolved, parsed),
        .generate_fixtures => try generateFixtures(allocator, resolved),
        .validate_phase1 => try validatePhase1(allocator, resolved),
    }
}

const InspectRoomIntelligenceParseContext = struct {
    scene_request: room_intelligence.SelectionRequest = .{ .metadata_kind = .scene },
    background_request: room_intelligence.SelectionRequest = .{ .metadata_kind = .background },
    output_path: ?[]const u8 = null,
    malformed_target: ?[]const u8 = null,
};

fn maybeEmitInspectRoomIntelligenceParseFailure(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    err: anyerror,
) !bool {
    const context = inspectRoomIntelligenceParseContextFromArgs(args) orelse return false;
    try emitInspectRoomIntelligenceFailure(
        allocator,
        context.output_path,
        .{
            .scene_request = context.scene_request,
            .background_request = context.background_request,
            .phase = "parse",
            .kind = @errorName(err),
            .target = inspectRoomIntelligenceParseErrorTarget(context, err),
        },
    );
    return true;
}

fn recordEntrySelectorToken(
    request: *room_intelligence.SelectionRequest,
    raw_value: ?[]const u8,
    malformed_target: *?[]const u8,
    target_name: []const u8,
) void {
    if (request.selector != null or request.selector_kind_hint != null or request.requested_raw_value != null) return;

    request.selector_kind_hint = .entry;
    request.requested_raw_value = null;
    if (raw_value) |value| {
        const parsed = std.fmt.parseInt(usize, value, 10) catch {
            request.requested_raw_value = value;
            if (malformed_target.* == null) malformed_target.* = target_name;
            return;
        };
        request.selector = .{ .entry = parsed };
    }
}

fn inspectRoomIntelligenceParseContextFromArgs(args: []const []const u8) ?InspectRoomIntelligenceParseContext {
    var command_index: usize = 0;
    while (command_index < args.len and std.mem.startsWith(u8, args[command_index], "--")) {
        if (!std.mem.eql(u8, args[command_index], "--asset-root")) return null;
        if (command_index + 1 >= args.len) return null;
        command_index += 2;
    }

    if (command_index >= args.len) return null;
    if (!std.mem.eql(u8, args[command_index], "inspect-room-intelligence")) return null;

    var context: InspectRoomIntelligenceParseContext = .{};
    var index = command_index + 1;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--scene-entry")) {
            recordEntrySelectorToken(
                &context.scene_request,
                if (index + 1 < args.len) args[index + 1] else null,
                &context.malformed_target,
                "scene",
            );
            index += if (index + 1 < args.len) 2 else 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--scene-name")) {
            if (context.scene_request.selector == null and context.scene_request.selector_kind_hint == null and context.scene_request.requested_raw_value == null) {
                context.scene_request.selector_kind_hint = .name;
                context.scene_request.requested_raw_value = null;
                if (index + 1 < args.len) context.scene_request.selector = .{ .name = args[index + 1] };
            }
            index += if (index + 1 < args.len) 2 else 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--background-entry")) {
            recordEntrySelectorToken(
                &context.background_request,
                if (index + 1 < args.len) args[index + 1] else null,
                &context.malformed_target,
                "background",
            );
            index += if (index + 1 < args.len) 2 else 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--background-name")) {
            if (context.background_request.selector == null and context.background_request.selector_kind_hint == null and context.background_request.requested_raw_value == null) {
                context.background_request.selector_kind_hint = .name;
                context.background_request.requested_raw_value = null;
                if (index + 1 < args.len) context.background_request.selector = .{ .name = args[index + 1] };
            }
            index += if (index + 1 < args.len) 2 else 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--out")) {
            if (index + 1 < args.len and context.output_path == null) context.output_path = args[index + 1];
            index += if (index + 1 < args.len) 2 else 1;
            continue;
        }
        index += 1;
    }

    return context;
}

fn inspectRoomIntelligenceParseErrorTarget(context: InspectRoomIntelligenceParseContext, err: anyerror) []const u8 {
    return switch (err) {
        error.MissingSceneSelector,
        error.ConflictingSceneSelector,
        error.DuplicateSceneSelector,
        error.MissingSceneEntryIndex,
        error.MissingSceneName,
        => "scene",
        error.MissingBackgroundSelector,
        error.ConflictingBackgroundSelector,
        error.DuplicateBackgroundSelector,
        error.MissingBackgroundEntryIndex,
        error.MissingBackgroundName,
        => "background",
        error.InvalidCharacter,
        error.Overflow,
        => context.malformed_target orelse "command",
        else => "command",
    };
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    if (args.len == 0) return error.MissingCommand;

    var asset_root_override: ?[]u8 = null;
    errdefer if (asset_root_override) |value| allocator.free(value);

    var command_index: usize = 0;
    while (command_index < args.len and std.mem.startsWith(u8, args[command_index], "--")) {
        if (!std.mem.eql(u8, args[command_index], "--asset-root")) return error.UnknownOption;
        if (command_index + 1 >= args.len) return error.MissingAssetRootValue;
        asset_root_override = try allocator.dupe(u8, args[command_index + 1]);
        command_index += 2;
    }

    if (command_index >= args.len) return error.MissingCommand;
    const command_name = args[command_index];

    if (std.mem.eql(u8, command_name, "inventory-assets")) {
        return .{ .command = .inventory_assets, .asset_root_override = asset_root_override, .relative_path = null, .entry_index = null, .background_entry_index = null, .audit_scene_entry_indices = null, .audit_all_scene_entries = false, .life_program_owner = null, .output_json = false };
    }
    if (std.mem.eql(u8, command_name, "inspect-hqr")) {
        if (command_index + 1 >= args.len) return error.MissingRelativePath;
        var output_json = false;
        for (args[(command_index + 2)..]) |arg| {
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
            } else {
                return error.UnknownOption;
            }
        }
        return .{
            .command = .inspect_hqr,
            .asset_root_override = asset_root_override,
            .relative_path = args[command_index + 1],
            .entry_index = null,
            .background_entry_index = null,
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "extract-entry")) {
        if (command_index + 2 >= args.len) return error.MissingEntryIndex;
        return .{
            .command = .extract_entry,
            .asset_root_override = asset_root_override,
            .relative_path = args[command_index + 1],
            .entry_index = try std.fmt.parseInt(usize, args[command_index + 2], 10),
            .background_entry_index = null,
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = false,
        };
    }
    if (std.mem.eql(u8, command_name, "inspect-background")) {
        if (command_index + 1 >= args.len) return error.MissingEntryIndex;
        var output_json = false;
        for (args[(command_index + 2)..]) |arg| {
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
            } else {
                return error.UnknownOption;
            }
        }
        return .{
            .command = .inspect_background,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = try std.fmt.parseInt(usize, args[command_index + 1], 10),
            .background_entry_index = null,
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "inspect-scene")) {
        if (command_index + 1 >= args.len) return error.MissingEntryIndex;
        var output_json = false;
        for (args[(command_index + 2)..]) |arg| {
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
            } else {
                return error.UnknownOption;
            }
        }
        return .{
            .command = .inspect_scene,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = try std.fmt.parseInt(usize, args[command_index + 1], 10),
            .background_entry_index = null,
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "inspect-room")) {
        if (command_index + 1 >= args.len) return error.MissingSceneEntryIndex;
        if (command_index + 2 >= args.len) return error.MissingBackgroundEntryIndex;
        var output_json = false;
        for (args[(command_index + 3)..]) |arg| {
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
            } else {
                return error.UnknownOption;
            }
        }
        return .{
            .command = .inspect_room,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = try std.fmt.parseInt(usize, args[command_index + 1], 10),
            .background_entry_index = try std.fmt.parseInt(usize, args[command_index + 2], 10),
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "inspect-room-transitions")) {
        if (command_index + 1 >= args.len) return error.MissingSceneEntryIndex;
        if (command_index + 2 >= args.len) return error.MissingBackgroundEntryIndex;
        var output_json = false;
        for (args[(command_index + 3)..]) |arg| {
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
            } else {
                return error.UnknownOption;
            }
        }
        return .{
            .command = .inspect_room_transitions,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = try std.fmt.parseInt(usize, args[command_index + 1], 10),
            .background_entry_index = try std.fmt.parseInt(usize, args[command_index + 2], 10),
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "inspect-room-intelligence")) {
        var scene_entry_index: ?usize = null;
        var background_entry_index: ?usize = null;
        var scene_name: ?[]const u8 = null;
        var background_name: ?[]const u8 = null;
        var output_path: ?[]const u8 = null;

        var index = command_index + 1;
        while (index < args.len) {
            const arg = args[index];
            if (std.mem.eql(u8, arg, "--scene-entry")) {
                if (scene_name != null) return error.ConflictingSceneSelector;
                if (scene_entry_index != null) return error.DuplicateSceneSelector;
                if (index + 1 >= args.len) return error.MissingSceneEntryIndex;
                scene_entry_index = try std.fmt.parseInt(usize, args[index + 1], 10);
                index += 2;
            } else if (std.mem.eql(u8, arg, "--scene-name")) {
                if (scene_entry_index != null) return error.ConflictingSceneSelector;
                if (scene_name != null) return error.DuplicateSceneSelector;
                if (index + 1 >= args.len) return error.MissingSceneName;
                scene_name = args[index + 1];
                index += 2;
            } else if (std.mem.eql(u8, arg, "--background-entry")) {
                if (background_name != null) return error.ConflictingBackgroundSelector;
                if (background_entry_index != null) return error.DuplicateBackgroundSelector;
                if (index + 1 >= args.len) return error.MissingBackgroundEntryIndex;
                background_entry_index = try std.fmt.parseInt(usize, args[index + 1], 10);
                index += 2;
            } else if (std.mem.eql(u8, arg, "--background-name")) {
                if (background_entry_index != null) return error.ConflictingBackgroundSelector;
                if (background_name != null) return error.DuplicateBackgroundSelector;
                if (index + 1 >= args.len) return error.MissingBackgroundName;
                background_name = args[index + 1];
                index += 2;
            } else if (std.mem.eql(u8, arg, "--out")) {
                if (output_path != null) return error.DuplicateOutputPath;
                if (index + 1 >= args.len) return error.MissingOutputPath;
                output_path = args[index + 1];
                index += 2;
            } else {
                return error.UnknownOption;
            }
        }

        return .{
            .command = .inspect_room_intelligence,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = if (scene_entry_index == null and scene_name == null) return error.MissingSceneSelector else scene_entry_index,
            .background_entry_index = if (background_entry_index == null and background_name == null) return error.MissingBackgroundSelector else background_entry_index,
            .output_path = output_path,
            .scene_name = scene_name,
            .background_name = background_name,
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = false,
        };
    }
    if (std.mem.eql(u8, command_name, "inspect-room-fragment-zones")) {
        if (command_index + 1 >= args.len) return error.MissingSceneEntryIndex;
        if (command_index + 2 >= args.len) return error.MissingBackgroundEntryIndex;
        var output_json = false;
        for (args[(command_index + 3)..]) |arg| {
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
            } else {
                return error.UnknownOption;
            }
        }
        return .{
            .command = .inspect_room_fragment_zones,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = try std.fmt.parseInt(usize, args[command_index + 1], 10),
            .background_entry_index = try std.fmt.parseInt(usize, args[command_index + 2], 10),
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "audit-life-programs")) {
        var output_json = false;
        var audit_all_scene_entries = false;
        var scene_entry_indices: std.ArrayList(usize) = .empty;
        errdefer scene_entry_indices.deinit(allocator);

        var index = command_index + 1;
        while (index < args.len) {
            const arg = args[index];
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--all-scene-entries")) {
                if (scene_entry_indices.items.len != 0) return error.ConflictingAuditSceneSelection;
                audit_all_scene_entries = true;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--scene-entry")) {
                if (audit_all_scene_entries) return error.ConflictingAuditSceneSelection;
                if (index + 1 >= args.len) return error.MissingSceneEntryIndex;
                const entry_index = try std.fmt.parseInt(usize, args[index + 1], 10);
                try appendSceneEntry(&scene_entry_indices, allocator, entry_index);
                index += 2;
            } else {
                return error.UnknownOption;
            }
        }

        return .{
            .command = .audit_life_programs,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = null,
            .background_entry_index = null,
            .audit_scene_entry_indices = if (audit_all_scene_entries or scene_entry_indices.items.len == 0) null else try scene_entry_indices.toOwnedSlice(allocator),
            .audit_all_scene_entries = audit_all_scene_entries,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "rank-decoded-interior-candidates")) {
        var output_json = false;
        for (args[(command_index + 1)..]) |arg| {
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
            } else {
                return error.UnknownOption;
            }
        }
        return .{
            .command = .rank_decoded_interior_candidates,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = null,
            .background_entry_index = null,
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "triage-same-index-decoded-interior-candidates")) {
        var output_json = false;
        for (args[(command_index + 1)..]) |arg| {
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
            } else {
                return error.UnknownOption;
            }
        }
        return .{
            .command = .triage_same_index_decoded_interior_candidates,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = null,
            .background_entry_index = null,
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "inspect-life-catalog")) {
        var output_json = false;
        for (args[(command_index + 1)..]) |arg| {
            if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
            } else {
                return error.UnknownOption;
            }
        }
        return .{
            .command = .inspect_life_catalog,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = null,
            .background_entry_index = null,
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = null,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "inspect-life-program")) {
        var scene_entry_index: ?usize = null;
        var output_json = false;
        var life_owner: life_audit.LifeBlobOwner = .{ .hero = {} };
        var has_object_selector = false;

        var index = command_index + 1;
        while (index < args.len) {
            const arg = args[index];
            if (std.mem.eql(u8, arg, "--scene-entry")) {
                if (scene_entry_index != null) return error.DuplicateSceneEntrySelector;
                if (index + 1 >= args.len) return error.MissingSceneEntryIndex;
                scene_entry_index = try std.fmt.parseInt(usize, args[index + 1], 10);
                index += 2;
            } else if (std.mem.eql(u8, arg, "--object-index")) {
                if (has_object_selector) return error.DuplicateObjectIndexSelector;
                if (index + 1 >= args.len) return error.MissingObjectIndex;
                life_owner = .{ .object = try std.fmt.parseInt(usize, args[index + 1], 10) };
                has_object_selector = true;
                index += 2;
            } else if (std.mem.eql(u8, arg, "--json")) {
                output_json = true;
                index += 1;
            } else {
                return error.UnknownOption;
            }
        }

        return .{
            .command = .inspect_life_program,
            .asset_root_override = asset_root_override,
            .relative_path = null,
            .entry_index = scene_entry_index orelse return error.MissingSceneEntryIndex,
            .background_entry_index = null,
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
            .life_program_owner = life_owner,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "generate-fixtures")) {
        return .{ .command = .generate_fixtures, .asset_root_override = asset_root_override, .relative_path = null, .entry_index = null, .background_entry_index = null, .audit_scene_entry_indices = null, .audit_all_scene_entries = false, .life_program_owner = null, .output_json = false };
    }
    if (std.mem.eql(u8, command_name, "validate-phase1")) {
        return .{ .command = .validate_phase1, .asset_root_override = asset_root_override, .relative_path = null, .entry_index = null, .background_entry_index = null, .audit_scene_entry_indices = null, .audit_all_scene_entries = false, .life_program_owner = null, .output_json = false };
    }
    return error.UnknownCommand;
}

fn inventoryAssets(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths) !void {
    try paths_mod.ensurePhase1WorkDirs(allocator, resolved);
    const inventory = try catalog.generateAssetCatalog(allocator, resolved);
    defer {
        for (inventory) |entry| entry.deinit(allocator);
        allocator.free(inventory);
    }

    const json = try catalog.renderCatalogJson(allocator, inventory);
    defer allocator.free(json);

    const output_path = try std.fs.path.join(allocator, &.{ resolved.work_root, "asset_catalog.json" });
    defer allocator.free(output_path);
    try writeJson(output_path, json);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "status", .value = "ok" },
        .{ .key = "command", .value = "inventory-assets" },
        .{ .key = "output", .value = "work/port/phase1/asset_catalog.json" },
    });
    try stderr.flush();
}

fn inspectHqr(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths, relative_path: []const u8, output_json: bool) !void {
    const absolute_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, relative_path });
    defer allocator.free(absolute_path);

    const archive = try hqr.loadArchive(allocator, absolute_path);
    defer archive.deinit(allocator);

    if (output_json) {
        const payload = try buildInspectHqrPayloadAlloc(allocator, relative_path, archive.entries);
        defer allocator.free(payload.entries);
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try stderr.print("asset_path={s} entry_count={d}\n", .{ relative_path, archive.entry_count });
    for (archive.entries) |entry| {
        try stderr.print("index={d} offset={d} byte_length={d} sha256={s}\n", .{
            entry.index,
            entry.offset,
            entry.byte_length,
            entry.sha256,
        });
    }
    try stderr.flush();
}

fn buildInspectHqrPayloadAlloc(
    allocator: std.mem.Allocator,
    relative_path: []const u8,
    entries: []const hqr.HqrEntry,
) !InspectHqrPayload {
    const payload_entries = try allocator.alloc(InspectHqrEntryPayload, entries.len);
    errdefer allocator.free(payload_entries);

    for (entries, payload_entries) |entry, *payload_entry| {
        const metadata = reference_metadata.lookupHqrEntryMetadata(relative_path, entry.index);
        payload_entry.* = .{
            .index = entry.index,
            .offset = entry.offset,
            .byte_length = entry.byte_length,
            .sha256 = entry.sha256,
            .entry_type = if (metadata) |value| value.entry_type else null,
            .entry_description = if (metadata) |value| value.entry_description else null,
        };
    }

    return .{
        .asset_path = relative_path,
        .entry_count = entries.len,
        .entries = payload_entries,
    };
}

fn extractEntry(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths, relative_path: []const u8, entry_index: usize) !void {
    try paths_mod.ensurePhase1WorkDirs(allocator, resolved);
    const absolute_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, relative_path });
    defer allocator.free(absolute_path);

    const sanitized = try hqr.sanitizeRelativeAssetPath(allocator, relative_path);
    defer allocator.free(sanitized);
    const output_dir = try std.fs.path.join(allocator, &.{ resolved.work_root, "extracted", sanitized });
    defer allocator.free(output_dir);
    try paths_mod.makePathAbsolute(output_dir);

    const output_path = try std.fmt.allocPrint(allocator, "{s}{c}{d}.bin", .{ output_dir, std.fs.path.sep, entry_index });
    defer allocator.free(output_path);
    const sha = try hqr.extractEntryToPath(allocator, absolute_path, entry_index, output_path);
    defer allocator.free(sha);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "status", .value = "ok" },
        .{ .key = "command", .value = "extract-entry" },
        .{ .key = "sha256", .value = sha },
    });
    try stderr.flush();
}

fn inspectBackground(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths, entry_index: usize, output_json: bool) !void {
    const absolute_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "LBA_BKG.HQR" });
    defer allocator.free(absolute_path);

    const metadata = try background_data.loadBackgroundMetadata(allocator, absolute_path, entry_index);
    defer metadata.deinit(allocator);

    if (output_json) {
        const payload = .{
            .entry_index = metadata.entry_index,
            .header_entry_index = metadata.header_entry_index,
            .header_compressed_header = metadata.header_compressed_header,
            .bkg_header = metadata.bkg_header,
            .tab_all_cube_entry_index = metadata.tab_all_cube_entry_index,
            .tab_all_cube_compressed_header = metadata.tab_all_cube_compressed_header,
            .tab_all_cube_entry_count = metadata.tab_all_cube_entry_count,
            .tab_all_cube = metadata.tab_all_cube,
            .remapped_cube_index = metadata.remapped_cube_index,
            .gri_entry_index = metadata.gri_entry_index,
            .gri_compressed_header = metadata.gri_compressed_header,
            .gri_header = metadata.gri_header,
            .used_blocks = metadata.used_blocks,
            .column_table = metadata.column_table,
            .grm_entry_index = metadata.grm_entry_index,
            .bll_entry_index = metadata.bll_entry_index,
            .bll_compressed_header = metadata.bll_compressed_header,
            .bll = metadata.bll,
            .composition = metadata.composition,
        };
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "command", .value = "inspect-background" },
        .{ .key = "asset_path", .value = "LBA_BKG.HQR" },
    });
    try stderr.print(
        "entry_index={d} header_entry_index={d} remapped_cube_index={d} gri_entry_index={d} grm_entry_index={d} bll_entry_index={d}\n",
        .{
            metadata.entry_index,
            metadata.header_entry_index,
            metadata.remapped_cube_index,
            metadata.gri_entry_index,
            metadata.grm_entry_index,
            metadata.bll_entry_index,
        },
    );
    try stderr.print(
        "bkg_header gri_start={d} grm_start={d} bll_start={d} brk_start={d} max_brk={d} forbiden_brick={d} max_size_gri={d} max_size_bll={d} max_size_brick_cube={d} max_size_mask_brick_cube={d}\n",
        .{
            metadata.bkg_header.gri_start,
            metadata.bkg_header.grm_start,
            metadata.bkg_header.bll_start,
            metadata.bkg_header.brk_start,
            metadata.bkg_header.max_brk,
            metadata.bkg_header.forbiden_brick,
            metadata.bkg_header.max_size_gri,
            metadata.bkg_header.max_size_bll,
            metadata.bkg_header.max_size_brick_cube,
            metadata.bkg_header.max_size_mask_brick_cube,
        },
    );
    try stderr.print(
        "tab_all_cube entry_index={d} entry_count={d} type_id={d} num={d}\n",
        .{
            metadata.tab_all_cube_entry_index,
            metadata.tab_all_cube_entry_count,
            metadata.tab_all_cube.type_id,
            metadata.tab_all_cube.num,
        },
    );
    try stderr.print(
        "gri my_bll={d} my_grm={d} used_block_count={d} column_table={d}x{d} min_offset={d} max_offset={d} data_bytes={d}\n",
        .{
            metadata.gri_header.my_bll,
            metadata.gri_header.my_grm,
            metadata.used_blocks.used_block_ids.len,
            metadata.column_table.width,
            metadata.column_table.depth,
            metadata.column_table.min_offset,
            metadata.column_table.max_offset,
            metadata.column_table.data_byte_length,
        },
    );
    if (metadata.composition.grid.reference_bounds) |bounds| {
        try stderr.print(
            "composition occupied_cells={d} unique_offsets={d} layouts={d} max_layout_blocks={d} bounds=x:{d}..{d} z:{d}..{d}\n",
            .{
                metadata.composition.grid.referenced_cell_count,
                metadata.composition.grid.unique_offset_count,
                metadata.composition.library.layouts.len,
                metadata.composition.library.max_layout_block_count,
                bounds.min_x,
                bounds.max_x,
                bounds.min_z,
                bounds.max_z,
            },
        );
    } else {
        try stderr.print(
            "composition occupied_cells={d} unique_offsets={d} layouts={d} max_layout_blocks={d} bounds=none\n",
            .{
                metadata.composition.grid.referenced_cell_count,
                metadata.composition.grid.unique_offset_count,
                metadata.composition.library.layouts.len,
                metadata.composition.library.max_layout_block_count,
            },
        );
    }
    try stderr.print(
        "fragments count={d} footprint_cells={d} non_empty_cells={d} max_height={d}\n",
        .{
            metadata.composition.fragments.fragments.len,
            metadata.composition.fragments.footprint_cell_count,
            metadata.composition.fragments.non_empty_cell_count,
            metadata.composition.fragments.max_height,
        },
    );
    try stderr.print(
        "brick_previews palette_entry_index={d} count={d} max_preview={d}x{d} opaque_pixels={d}\n",
        .{
            metadata.composition.bricks.palette_entry_index,
            metadata.composition.bricks.previews.len,
            metadata.composition.bricks.max_preview_width,
            metadata.composition.bricks.max_preview_height,
            metadata.composition.bricks.total_opaque_pixel_count,
        },
    );
    try printUsedBlockSummary(stderr, metadata.used_blocks.used_block_ids);
    try stderr.print(
        "bll block_count={d} table_bytes={d} first_block_offset={d} last_block_offset={d}\n",
        .{
            metadata.bll.block_count,
            metadata.bll.table_byte_length,
            metadata.bll.first_block_offset,
            metadata.bll.last_block_offset,
        },
    );
    try stderr.flush();
}

fn inspectScene(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths, entry_index: usize, output_json: bool) !void {
    const absolute_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(absolute_path);

    const scene = try scene_data.loadSceneMetadata(allocator, absolute_path, entry_index);
    defer scene.deinit(allocator);

    if (output_json) {
        const payload = .{
            .entry_index = scene.entry_index,
            .classic_loader_scene_number = scene.classicLoaderSceneNumber(),
            .scene_kind = scene.sceneKind(),
            .compressed_header = scene.compressed_header,
            .island = scene.island,
            .cube_x = scene.cube_x,
            .cube_y = scene.cube_y,
            .shadow_level = scene.shadow_level,
            .mode_labyrinth = scene.mode_labyrinth,
            .cube_mode = scene.cube_mode,
            .unused_header_byte = scene.unused_header_byte,
            .alpha_light = scene.alpha_light,
            .beta_light = scene.beta_light,
            .ambient_samples = &scene.ambient_samples,
            .second_min = scene.second_min,
            .second_ecart = scene.second_ecart,
            .cube_jingle = scene.cube_jingle,
            .hero_start = scene.hero_start,
            .checksum = scene.checksum,
            .object_count = scene.object_count,
            .zone_count = scene.zone_count,
            .track_count = scene.track_count,
            .patch_count = scene.patch_count,
            .objects = scene.objects,
            .zones = scene.zones,
            .tracks = scene.tracks,
            .patches = scene.patches,
        };
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "command", .value = "inspect-scene" },
        .{ .key = "asset_path", .value = "SCENE.HQR" },
        .{ .key = "scene_kind", .value = scene.sceneKind() },
    });
    if (scene.classicLoaderSceneNumber()) |loader_scene_number| {
        try stderr.print(
            "entry_index={d} classic_loader_scene_number={d} cube_mode={d} island={d} cube_x={d} cube_y={d} object_count={d} zone_count={d} track_count={d} patch_count={d}\n",
            .{ scene.entry_index, loader_scene_number, scene.cube_mode, scene.island, scene.cube_x, scene.cube_y, scene.object_count, scene.zone_count, scene.track_count, scene.patch_count },
        );
    } else {
        try stderr.print(
            "entry_index={d} classic_loader_scene_number=reserved-header cube_mode={d} island={d} cube_x={d} cube_y={d} object_count={d} zone_count={d} track_count={d} patch_count={d}\n",
            .{ scene.entry_index, scene.cube_mode, scene.island, scene.cube_x, scene.cube_y, scene.object_count, scene.zone_count, scene.track_count, scene.patch_count },
        );
    }
    try stderr.print(
        "hero_x={d} hero_y={d} hero_z={d} hero_track_bytes={d} hero_life_bytes={d}\n",
        .{ scene.hero_start.x, scene.hero_start.y, scene.hero_start.z, scene.hero_start.trackByteLength(), scene.hero_start.lifeByteLength() },
    );
    try printTrackInstructionSummary(stderr, "hero_track_instructions", scene.hero_start.track_instructions);

    for (scene.objects) |object| {
        try stderr.print(
            "object_index={d} flags={d} file3d_index={d} gen_body={d} gen_anim={d} sprite={d} x={d} y={d} z={d} move={d} track_bytes={d} life_bytes={d}\n",
            .{ object.index, object.flags, object.file3d_index, object.gen_body, object.gen_anim, object.sprite, object.x, object.y, object.z, object.move, object.trackByteLength(), object.lifeByteLength() },
        );
        try stderr.print("object_index={d} ", .{object.index});
        try printTrackInstructionSummary(stderr, "track_instructions", object.track_instructions);
    }
    for (scene.zones) |zone| {
        try printZone(stderr, zone);
    }
    for (scene.tracks) |track| {
        try stderr.print("track_index={d} x={d} y={d} z={d}\n", .{ track.index, track.x, track.y, track.z });
    }
    for (scene.patches) |patch| {
        try stderr.print("patch_size={d} patch_offset={d}\n", .{ patch.size, patch.offset });
    }
    try stderr.flush();
}

fn inspectRoom(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
    output_json: bool,
) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const room = room_state.loadRoomSnapshot(allocator, resolved, scene_entry_index, background_entry_index) catch |err| {
        if (err == error.ViewerUnsupportedSceneLife) {
            const hit = try room_state.inspectUnsupportedSceneLifeHit(allocator, resolved, scene_entry_index);
            try printUnsupportedSceneLifeDiagnostic(stderr, scene_entry_index, background_entry_index, hit);
            try stderr.flush();
        } else if (err == error.InvalidFragmentZoneBounds) {
            const diagnostics_snapshot = try room_state.inspectRoomFragmentZoneDiagnostics(allocator, resolved, scene_entry_index, background_entry_index);
            defer diagnostics_snapshot.deinit(allocator);
            try printFragmentZoneBoundsDiagnostic(stderr, diagnostics_snapshot);
            try stderr.flush();
        }
        return err;
    };
    defer room.deinit(allocator);

    const payload = buildRoomInspectionPayload(&room);
    if (output_json) {
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }
    try diagnostics.printLine(stderr, &.{
        .{ .key = "command", .value = "inspect-room" },
        .{ .key = "scene_asset_path", .value = "SCENE.HQR" },
        .{ .key = "background_asset_path", .value = "LBA_BKG.HQR" },
        .{ .key = "scene_kind", .value = payload.scene.scene_kind },
    });
    try stderr.print(
        "scene_entry_index={d} background_entry_index={d} classic_loader_scene_number={any} hero_x={d} hero_y={d} hero_z={d} hero_track_bytes={d} hero_life_bytes={d} object_count={d} zone_count={d} track_count={d} patch_count={d}\n",
        .{
            payload.scene.entry_index,
            payload.background.entry_index,
            payload.scene.classic_loader_scene_number,
            payload.scene.hero_start.x,
            payload.scene.hero_start.y,
            payload.scene.hero_start.z,
            payload.scene.hero_start.track_byte_length,
            payload.scene.hero_start.life_byte_length,
            payload.scene.object_count,
            payload.scene.zone_count,
            payload.scene.track_count,
            payload.scene.patch_count,
        },
    );
    try stderr.print(
        "remapped_cube_index={d} gri_entry_index={d} gri_my_grm={d} grm_entry_index={d} gri_my_bll={d} bll_entry_index={d}\n",
        .{
            payload.background.linkage.remapped_cube_index,
            payload.background.linkage.gri_entry_index,
            payload.background.linkage.gri_my_grm,
            payload.background.linkage.grm_entry_index,
            payload.background.linkage.gri_my_bll,
            payload.background.linkage.bll_entry_index,
        },
    );
    try stderr.print(
        "column_table={d}x{d} offsets={d} table_bytes={d} min_offset={d} max_offset={d} data_bytes={d}\n",
        .{
            payload.background.column_table.width,
            payload.background.column_table.depth,
            payload.background.column_table.offset_count,
            payload.background.column_table.table_byte_length,
            payload.background.column_table.min_offset,
            payload.background.column_table.max_offset,
            payload.background.column_table.data_byte_length,
        },
    );
    if (payload.background.composition.occupied_bounds) |bounds| {
        try stderr.print(
            "composition occupied_cells={d} layouts={d} max_layout_blocks={d} bounds=x:{d}..{d} z:{d}..{d}\n",
            .{
                payload.background.composition.occupied_cell_count,
                payload.background.composition.layout_count,
                payload.background.composition.max_layout_block_count,
                bounds.min_x,
                bounds.max_x,
                bounds.min_z,
                bounds.max_z,
            },
        );
    } else {
        try stderr.print(
            "composition occupied_cells={d} layouts={d} max_layout_blocks={d} bounds=none\n",
            .{
                payload.background.composition.occupied_cell_count,
                payload.background.composition.layout_count,
                payload.background.composition.max_layout_block_count,
            },
        );
    }
    try stderr.print(
        "fragments count={d} footprint_cells={d} non_empty_cells={d} max_height={d}\n",
        .{
            payload.background.fragments.fragment_count,
            payload.background.fragments.footprint_cell_count,
            payload.background.fragments.non_empty_cell_count,
            payload.background.fragments.max_height,
        },
    );
    try stderr.print(
        "brick_previews palette_entry_index={d} count={d} max_preview={d}x{d} opaque_pixels={d}\n",
        .{
            payload.background.bricks.palette_entry_index,
            payload.background.bricks.preview_count,
            payload.background.bricks.max_preview_width,
            payload.background.bricks.max_preview_height,
            payload.background.bricks.total_opaque_pixel_count,
        },
    );
    try printUsedBlockSummary(stderr, payload.background.used_blocks.values);
    try stderr.flush();
}

fn inspectRoomTransitions(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
    output_json: bool,
) !void {
    const payload = try buildRoomTransitionInspectionPayload(
        allocator,
        resolved,
        scene_entry_index,
        background_entry_index,
    );
    defer allocator.free(payload.transitions);

    if (output_json) {
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "command", .value = "inspect-room-transitions" },
        .{ .key = "scene_asset_path", .value = "SCENE.HQR" },
        .{ .key = "background_asset_path", .value = "LBA_BKG.HQR" },
    });
    try stderr.print(
        "source_scene_entry_index={d} source_background_entry_index={d} transition_count={d}\n",
        .{ payload.source_scene_entry_index, payload.source_background_entry_index, payload.transition_count },
    );
    for (payload.transitions) |transition| {
        try stderr.print(
            "source_kind={s} source_zone_index={d} source_zone_num={d} destination_cube={d} result={s} rejection_reason={s} destination_scene_entry_index={any} destination_background_entry_index={any} post_load_target_status={s} post_load_shadow_adjustment_failure={s} provisional_x={d} provisional_y={d} provisional_z={d} hero_x={d} hero_y={d} hero_z={d} runtime_no_key_event={s} runtime_no_key_result={s} runtime_no_key_after={d} runtime_with_key_event={s} runtime_with_key_result={s} runtime_with_key_after={d}\n",
            .{
                transition.source_kind,
                transition.source_zone_index,
                transition.source_zone_num,
                transition.destination_cube,
                transition.result,
                transition.rejection_reason orelse "none",
                transition.destination_scene_entry_index,
                transition.destination_background_entry_index,
                if (transition.post_load_diagnostics) |diagnostics_summary| diagnostics_summary.move_target_status else "none",
                if (transition.post_load_diagnostics) |diagnostics_summary| diagnostics_summary.shadow_adjustment_failure orelse "none" else "none",
                if (transition.post_load_diagnostics) |diagnostics_summary| diagnostics_summary.provisional_world_position.x else transition.destination_world_position.x,
                if (transition.post_load_diagnostics) |diagnostics_summary| diagnostics_summary.provisional_world_position.y else transition.destination_world_position.y,
                if (transition.post_load_diagnostics) |diagnostics_summary| diagnostics_summary.provisional_world_position.z else transition.destination_world_position.z,
                transition.hero_position.x,
                transition.hero_position.y,
                transition.hero_position.z,
                runtimeEffectEventName(transition.runtime_no_key_effect),
                runtimeEffectResultName(transition.runtime_no_key_effect),
                runtimeEffectLittleKeysAfter(transition.runtime_no_key_effect),
                runtimeEffectEventName(transition.runtime_with_key_effect),
                runtimeEffectResultName(transition.runtime_with_key_effect),
                runtimeEffectLittleKeysAfter(transition.runtime_with_key_effect),
            },
        );
    }
    try stderr.flush();
}

fn inspectRoomIntelligence(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    parsed: ParsedArgs,
) !void {
    var phase_timings = try InspectRoomIntelligenceTimings.init(allocator, parsed.output_path);
    defer phase_timings.flush();

    const scene_selector: room_intelligence.Selector = if (parsed.scene_name) |scene_name|
        .{ .name = scene_name }
    else
        .{ .entry = parsed.entry_index.? };
    const background_selector: room_intelligence.Selector = if (parsed.background_name) |background_name|
        .{ .name = background_name }
    else
        .{ .entry = parsed.background_entry_index.? };
    const scene_request: room_intelligence.SelectionRequest = .{
        .metadata_kind = .scene,
        .selector = scene_selector,
    };
    const background_request: room_intelligence.SelectionRequest = .{
        .metadata_kind = .background,
        .selector = background_selector,
    };

    var scene_selection = room_intelligence.resolveSceneSelectionAlloc(allocator, resolved.repo_root, scene_selector) catch |err| {
        try emitInspectRoomIntelligenceFailure(
            allocator,
            parsed.output_path,
            .{
                .scene_request = scene_request,
                .background_request = background_request,
                .phase = "scene_selection",
                .kind = @errorName(err),
                .target = "scene",
            },
        );
        return error.MachineReadableReported;
    };
    defer scene_selection.deinit(allocator);

    var background_selection = room_intelligence.resolveBackgroundSelectionAlloc(allocator, resolved.repo_root, background_selector) catch |err| {
        try emitInspectRoomIntelligenceFailure(
            allocator,
            parsed.output_path,
            .{
                .scene_request = scene_request,
                .background_request = background_request,
                .scene_selection = &scene_selection,
                .phase = "background_selection",
                .kind = @errorName(err),
                .target = "background",
            },
        );
        return error.MachineReadableReported;
    };
    defer background_selection.deinit(allocator);
    phase_timings.markSelection();

    const scene_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(scene_path);
    const scene = scene_data.loadSceneMetadata(allocator, scene_path, scene_selection.resolved_entry_index) catch |err| {
        const normalized = normalizeInspectRoomIntelligenceSceneLoadError(scene_selector, err);
        try emitInspectRoomIntelligenceFailure(
            allocator,
            parsed.output_path,
            .{
                .scene_request = scene_request,
                .background_request = background_request,
                .scene_selection = &scene_selection,
                .background_selection = &background_selection,
                .phase = "scene_load",
                .kind = @errorName(normalized),
                .target = "scene",
            },
        );
        return error.MachineReadableReported;
    };
    defer scene.deinit(allocator);
    phase_timings.markSceneLoad();

    const background_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "LBA_BKG.HQR" });
    defer allocator.free(background_path);
    const background = background_data.loadBackgroundMetadata(allocator, background_path, background_selection.resolved_entry_index) catch |err| {
        const normalized = normalizeInspectRoomIntelligenceBackgroundLoadError(background_selector, err);
        try emitInspectRoomIntelligenceFailure(
            allocator,
            parsed.output_path,
            .{
                .scene_request = scene_request,
                .background_request = background_request,
                .scene_selection = &scene_selection,
                .background_selection = &background_selection,
                .phase = "background_load",
                .kind = @errorName(normalized),
                .target = "background",
            },
        );
        return error.MachineReadableReported;
    };
    defer background.deinit(allocator);
    phase_timings.markBackgroundLoad();

    var validation = room_intelligence.inspectValidation(
        allocator,
        scene,
        background,
    ) catch |err| {
        try emitInspectRoomIntelligenceFailure(
            allocator,
            parsed.output_path,
            .{
                .scene_request = scene_request,
                .background_request = background_request,
                .scene_selection = &scene_selection,
                .background_selection = &background_selection,
                .phase = "validation",
                .kind = @errorName(err),
                .target = "room",
            },
        );
        return error.MachineReadableReported;
    };
    defer validation.deinit(allocator);
    phase_timings.markValidation();

    const augmentation = if (validation.viewer_loadable) blk: {
        const resolved_augmentation = room_state.buildRoomIntelligenceAugmentation(allocator, scene, background) catch |err| {
            try emitInspectRoomIntelligenceFailure(
                allocator,
                parsed.output_path,
                .{
                    .scene_request = scene_request,
                    .background_request = background_request,
                    .scene_selection = &scene_selection,
                    .background_selection = &background_selection,
                    .phase = "augmentation",
                    .kind = @errorName(err),
                    .target = "room",
                },
            );
            return error.MachineReadableReported;
        };
        phase_timings.markAugmentation();
        break :blk resolved_augmentation;
    } else null;
    defer if (augmentation) |resolved_augmentation| resolved_augmentation.deinit(allocator);

    const payload: room_intelligence.PayloadView = .{
        .allocator = allocator,
        .scene_selection = &scene_selection,
        .background_selection = &background_selection,
        .scene = &scene,
        .background = &background,
        .validation = &validation,
        .augmentation = if (augmentation) |*resolved_augmentation| resolved_augmentation else null,
    };
    const json = room_intelligence.stringifyPayloadAlloc(allocator, payload) catch |err| {
        try emitInspectRoomIntelligenceFailure(
            allocator,
            parsed.output_path,
            .{
                .scene_request = scene_request,
                .background_request = background_request,
                .scene_selection = &scene_selection,
                .background_selection = &background_selection,
                .phase = "serialization",
                .kind = @errorName(err),
                .target = "room",
            },
        );
        return error.MachineReadableReported;
    };
    defer allocator.free(json);
    try writeInspectRoomIntelligenceJson(parsed.output_path, json);
    phase_timings.markSerialization();
}

fn emitInspectRoomIntelligenceFailure(
    allocator: std.mem.Allocator,
    output_path: ?[]const u8,
    payload: room_intelligence.ErrorPayloadView,
) !void {
    const json = try room_intelligence.stringifyErrorPayloadAlloc(allocator, payload);
    defer allocator.free(json);
    try writeInspectRoomIntelligenceJson(output_path, json);
}

fn writeInspectRoomIntelligenceJson(output_path: ?[]const u8, json: []const u8) !void {
    if (output_path) |path| {
        try writeJson(path, json);
    } else {
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
    }
}

fn normalizeInspectRoomIntelligenceSceneLoadError(selector: room_intelligence.Selector, err: anyerror) anyerror {
    return switch (err) {
        error.EntryIndexOutOfRange => switch (selector) {
            .entry => error.UnknownSceneEntryIndex,
            .name => err,
        },
        else => err,
    };
}

fn normalizeInspectRoomIntelligenceBackgroundLoadError(selector: room_intelligence.Selector, err: anyerror) anyerror {
    return switch (err) {
        error.InvalidBackgroundEntryIndex => switch (selector) {
            .entry => error.UnknownBackgroundEntryIndex,
            .name => err,
        },
        else => err,
    };
}

fn inspectRoomFragmentZones(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
    output_json: bool,
) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const diagnostics_snapshot = room_state.inspectRoomFragmentZoneDiagnostics(allocator, resolved, scene_entry_index, background_entry_index) catch |err| {
        if (err == error.ViewerUnsupportedSceneLife) {
            const hit = try room_state.inspectUnsupportedSceneLifeHit(allocator, resolved, scene_entry_index);
            try printUnsupportedSceneLifeDiagnostic(stderr, scene_entry_index, background_entry_index, hit);
            try stderr.flush();
        }
        return err;
    };
    defer diagnostics_snapshot.deinit(allocator);

    const payload = try buildRoomFragmentZoneDiagnosticsPayload(allocator, diagnostics_snapshot);
    defer allocator.free(payload.zones);

    if (output_json) {
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    try diagnostics.printLine(stderr, &.{
        .{ .key = "command", .value = "inspect-room-fragment-zones" },
        .{ .key = "scene_kind", .value = payload.scene_kind },
    });
    try stderr.print(
        "scene_entry_index={d} background_entry_index={d} classic_loader_scene_number={any} fragment_count={d} grm_zone_count={d} compatible_zone_count={d} invalid_zone_count={d} first_invalid_zone_index={any}\n",
        .{
            payload.scene_entry_index,
            payload.background_entry_index,
            payload.classic_loader_scene_number,
            payload.fragment_count,
            payload.grm_zone_count,
            payload.compatible_zone_count,
            payload.invalid_zone_count,
            payload.first_invalid_zone_index,
        },
    );
    for (payload.zones) |zone| {
        var fragment_dimensions_buffer: [32]u8 = undefined;
        try stderr.print(
            "zone_index={d} zone_num={d} grm_index={d} initially_on={} issue={s} fragment_entry_index={any} fragment_dimensions={s} x_bounds={d}..{d} x_origin_aligned={any} x_origin_remainder={any} x_floor={any}/{any} x_ceil={any}/{any} x_cells={any} y_bounds={d}..{d} y_span_aligned={} y_span_remainder={any} y_cells={any} z_bounds={d}..{d} z_origin_aligned={any} z_origin_remainder={any} z_floor={any}/{any} z_ceil={any}/{any} z_cells={any}\n",
            .{
                zone.zone_index,
                zone.zone_num,
                zone.grm_index,
                zone.initially_on,
                zone.issue,
                zone.fragment_entry_index,
                formatOptionalFragmentDimensions(&fragment_dimensions_buffer, zone.fragment_dimensions),
                zone.x_axis.min_value,
                zone.x_axis.max_value,
                zone.x_axis.origin_aligned,
                zone.x_axis.origin_remainder,
                zone.x_axis.origin_floor_value,
                zone.x_axis.origin_floor_cell,
                zone.x_axis.origin_ceil_value,
                zone.x_axis.origin_ceil_cell,
                zone.x_axis.cell_count,
                zone.y_axis.min_value,
                zone.y_axis.max_value,
                zone.y_axis.span_aligned,
                zone.y_axis.span_remainder,
                zone.y_axis.cell_count,
                zone.z_axis.min_value,
                zone.z_axis.max_value,
                zone.z_axis.origin_aligned,
                zone.z_axis.origin_remainder,
                zone.z_axis.origin_floor_value,
                zone.z_axis.origin_floor_cell,
                zone.z_axis.origin_ceil_value,
                zone.z_axis.origin_ceil_cell,
                zone.z_axis.cell_count,
            },
        );
    }
    try stderr.flush();
}

fn buildRoomInspectionPayload(room: *const room_state.RoomSnapshot) RoomInspectionPayload {
    return .{
        .command = "inspect-room",
        .scene = .{
            .entry_index = room.scene.entry_index,
            .classic_loader_scene_number = room.scene.classic_loader_scene_number,
            .scene_kind = room.scene.scene_kind,
            .hero_start = .{
                .x = room.scene.hero_start.x,
                .y = room.scene.hero_start.y,
                .z = room.scene.hero_start.z,
                .track_byte_length = room.scene.hero_start.track_byte_length,
                .life_byte_length = room.scene.hero_start.life_byte_length,
            },
            .object_count = room.scene.object_count,
            .zone_count = room.scene.zone_count,
            .track_count = room.scene.track_count,
            .patch_count = room.scene.patch_count,
        },
        .background = .{
            .entry_index = room.background.entry_index,
            .linkage = .{
                .remapped_cube_index = room.background.linkage.remapped_cube_index,
                .gri_entry_index = room.background.linkage.gri_entry_index,
                .gri_my_grm = room.background.linkage.gri_my_grm,
                .grm_entry_index = room.background.linkage.grm_entry_index,
                .gri_my_bll = room.background.linkage.gri_my_bll,
                .bll_entry_index = room.background.linkage.bll_entry_index,
            },
            .used_blocks = .{
                .count = room.background.used_block_ids.len,
                .values = room.background.used_block_ids,
            },
            .column_table = .{
                .width = room.background.column_table.width,
                .depth = room.background.column_table.depth,
                .offset_count = room.background.column_table.offset_count,
                .table_byte_length = room.background.column_table.table_byte_length,
                .data_byte_length = room.background.column_table.data_byte_length,
                .min_offset = room.background.column_table.min_offset,
                .max_offset = room.background.column_table.max_offset,
            },
            .composition = .{
                .occupied_cell_count = room.background.composition.occupied_cell_count,
                .occupied_bounds = if (room.background.composition.occupied_bounds) |bounds| .{
                    .min_x = bounds.min_x,
                    .max_x = bounds.max_x,
                    .min_z = bounds.min_z,
                    .max_z = bounds.max_z,
                } else null,
                .layout_count = room.background.composition.layout_count,
                .max_layout_block_count = room.background.composition.max_layout_block_count,
            },
            .fragments = .{
                .fragment_count = room.background.fragments.fragment_count,
                .footprint_cell_count = room.background.fragments.footprint_cell_count,
                .non_empty_cell_count = room.background.fragments.non_empty_cell_count,
                .max_height = room.background.fragments.max_height,
            },
            .bricks = .{
                .palette_entry_index = room.background.bricks.palette_entry_index,
                .preview_count = room.background.bricks.previews.len,
                .max_preview_width = room.background.bricks.max_preview_width,
                .max_preview_height = room.background.bricks.max_preview_height,
                .total_opaque_pixel_count = room.background.bricks.total_opaque_pixel_count,
            },
        },
    };
}

fn buildRoomTransitionInspectionPayload(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
) !RoomTransitionInspectionPayload {
    var source_room = try room_state.loadRoomSnapshot(allocator, resolved, scene_entry_index, background_entry_index);
    defer source_room.deinit(allocator);

    var transition_count: usize = 0;
    for (source_room.scene.zones) |zone| {
        if (zone.kind == .change_cube) transition_count += 1;
    }
    if (zone_effects.secretRoomCellarReturnProbePosition(scene_entry_index, background_entry_index) != null) {
        transition_count += 1;
    }

    const transitions = try allocator.alloc(RoomTransitionProbeSummary, transition_count);
    errdefer allocator.free(transitions);

    var transition_index: usize = 0;
    for (source_room.scene.zones) |zone| {
        if (zone.kind != .change_cube) continue;
        transitions[transition_index] = try inspectSingleRoomTransition(
            allocator,
            resolved,
            scene_entry_index,
            background_entry_index,
            zone,
        );
        transition_index += 1;
    }
    if (zone_effects.secretRoomCellarReturnProbePosition(scene_entry_index, background_entry_index)) |probe_position| {
        transitions[transition_index] = try inspectSecretRoomCellarReturnTransition(
            allocator,
            resolved,
            scene_entry_index,
            background_entry_index,
            probe_position,
        );
        transition_index += 1;
    }

    return .{
        .command = "inspect-room-transitions",
        .source_scene_entry_index = scene_entry_index,
        .source_background_entry_index = background_entry_index,
        .transition_count = transitions.len,
        .transitions = transitions,
    };
}

fn inspectSingleRoomTransition(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
    zone: room_state.ZoneBoundsSnapshot,
) !RoomTransitionProbeSummary {
    const semantics = switch (zone.semantics) {
        .change_cube => |value| value,
        else => return error.ExpectedChangeCubeZoneSemantics,
    };
    const destination_world_position = locomotion.WorldPointSnapshot{
        .x = semantics.destination_x,
        .y = semantics.destination_y,
        .z = semantics.destination_z,
    };
    const resolved_destination_entries = room_state.resolveGuardedTransitionRoomEntriesForCube(
        allocator,
        resolved,
        semantics.destination_cube,
    ) catch |err| switch (err) {
        error.UnsupportedDestinationCube => null,
        else => return err,
    };

    var room = try room_state.loadRoomSnapshot(allocator, resolved, scene_entry_index, background_entry_index);
    defer room.deinit(allocator);

    var current_session = try runtime_session.Session.initWithObjects(
        allocator,
        heroStartWorldPoint(&room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
    defer current_session.deinit(allocator);
    room_entry_state.applyRoomEntryState(&room, &current_session);

    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    const pre_transition_locomotion_status = locomotion_status;
    const runtime_probe_position = zone_effects.secretRoomHouseDoorProbePosition(scene_entry_index, background_entry_index, zone);
    const runtime_no_key_effect: ?RoomTransitionRuntimeEffectSummary = if (runtime_probe_position) |probe_position|
        try inspectRoomTransitionRuntimeEffect(
            allocator,
            resolved,
            scene_entry_index,
            background_entry_index,
            probe_position,
            0,
            &.{zone},
        )
    else
        null;
    const runtime_with_key_effect: ?RoomTransitionRuntimeEffectSummary = if (runtime_probe_position) |probe_position|
        try inspectRoomTransitionRuntimeEffect(
            allocator,
            resolved,
            scene_entry_index,
            background_entry_index,
            probe_position,
            1,
            &.{zone},
        )
    else
        null;
    try current_session.setPendingRoomTransition(.{
        .source_zone_index = zone.index,
        .destination_cube = semantics.destination_cube,
        .destination_world_position_kind = .provisional_zone_relative,
        .destination_world_position = destination_world_position,
        .yaw = semantics.yaw,
        .test_brick = semantics.test_brick,
        .dont_readjust_twinsen = semantics.dont_readjust_twinsen,
    });

    const transition_result = try runtime_transition.applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        pre_transition_locomotion_status,
    );

    return switch (transition_result) {
        .committed => |value| .{
            .source_kind = "decoded_change_cube",
            .source_zone_index = zone.index,
            .source_zone_num = zone.num,
            .destination_cube = semantics.destination_cube,
            .destination_world_position_kind = "provisional_zone_relative",
            .destination_world_position = roomTransitionWorldPositionSummary(destination_world_position),
            .yaw = semantics.yaw,
            .test_brick = semantics.test_brick,
            .dont_readjust_twinsen = semantics.dont_readjust_twinsen,
            .result = "committed",
            .rejection_reason = null,
            .destination_scene_entry_index = value.destination_scene_entry_index,
            .destination_background_entry_index = value.destination_background_entry_index,
            .hero_position = roomTransitionWorldPositionSummary(value.hero_position),
            .post_load_diagnostics = null,
            .runtime_probe_position = if (runtime_probe_position) |probe_position| roomTransitionWorldPositionSummary(probe_position) else null,
            .runtime_no_key_effect = runtime_no_key_effect,
            .runtime_with_key_effect = runtime_with_key_effect,
        },
        .rejected => |value| .{
            .source_kind = "decoded_change_cube",
            .source_zone_index = zone.index,
            .source_zone_num = zone.num,
            .destination_cube = semantics.destination_cube,
            .destination_world_position_kind = "provisional_zone_relative",
            .destination_world_position = roomTransitionWorldPositionSummary(destination_world_position),
            .yaw = semantics.yaw,
            .test_brick = semantics.test_brick,
            .dont_readjust_twinsen = semantics.dont_readjust_twinsen,
            .result = "rejected",
            .rejection_reason = @tagName(value.reason),
            .destination_scene_entry_index = if (resolved_destination_entries) |entries| entries.scene_entry_index else null,
            .destination_background_entry_index = if (resolved_destination_entries) |entries| entries.background_entry_index else null,
            .hero_position = roomTransitionWorldPositionSummary(value.hero_position),
            .post_load_diagnostics = if (value.post_load_adjustment_failure) |failure| roomTransitionPostLoadDiagnosticsSummary(failure) else null,
            .runtime_probe_position = if (runtime_probe_position) |probe_position| roomTransitionWorldPositionSummary(probe_position) else null,
            .runtime_no_key_effect = runtime_no_key_effect,
            .runtime_with_key_effect = runtime_with_key_effect,
        },
    };
}

fn inspectSecretRoomCellarReturnTransition(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
    probe_position: locomotion.WorldPointSnapshot,
) !RoomTransitionProbeSummary {
    const runtime_no_key_effect = try inspectRoomTransitionRuntimeEffect(
        allocator,
        resolved,
        scene_entry_index,
        background_entry_index,
        probe_position,
        0,
        &.{},
    );
    const runtime_with_key_effect = try inspectRoomTransitionRuntimeEffect(
        allocator,
        resolved,
        scene_entry_index,
        background_entry_index,
        probe_position,
        1,
        &.{},
    );
    const pending_destination_cube = runtime_no_key_effect.pending_destination_cube orelse return error.MissingRuntimeSyntheticTransition;
    const pending_destination_world_position = runtime_no_key_effect.pending_destination_world_position orelse return error.MissingRuntimeSyntheticTransition;
    const hero_position = runtime_no_key_effect.hero_position orelse return error.MissingRuntimeSyntheticTransition;

    return .{
        .source_kind = "runtime_synthetic",
        .source_zone_index = 0,
        .source_zone_num = 0,
        .destination_cube = pending_destination_cube,
        .destination_world_position_kind = "provisional_zone_relative",
        .destination_world_position = pending_destination_world_position,
        .yaw = 0,
        .test_brick = false,
        .dont_readjust_twinsen = false,
        .result = runtime_no_key_effect.result orelse return error.MissingRuntimeSyntheticTransition,
        .rejection_reason = runtime_no_key_effect.rejection_reason,
        .destination_scene_entry_index = runtime_no_key_effect.destination_scene_entry_index,
        .destination_background_entry_index = runtime_no_key_effect.destination_background_entry_index,
        .hero_position = hero_position,
        .post_load_diagnostics = runtime_no_key_effect.post_load_diagnostics,
        .runtime_probe_position = roomTransitionWorldPositionSummary(probe_position),
        .runtime_no_key_effect = runtime_no_key_effect,
        .runtime_with_key_effect = runtime_with_key_effect,
    };
}

fn inspectRoomTransitionRuntimeEffect(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    scene_entry_index: usize,
    background_entry_index: usize,
    probe_position: locomotion.WorldPointSnapshot,
    little_keys_before: u8,
    zones: []const room_state.ZoneBoundsSnapshot,
) !RoomTransitionRuntimeEffectSummary {
    var room = try room_state.loadRoomSnapshot(allocator, resolved, scene_entry_index, background_entry_index);
    defer room.deinit(allocator);

    var current_session = try runtime_session.Session.initWithObjects(
        allocator,
        heroStartWorldPoint(&room),
        room.scene.objects,
        room.scene.object_behavior_seeds,
    );
    defer current_session.deinit(allocator);
    room_entry_state.applyRoomEntryState(&room, &current_session);
    current_session.setHeroWorldPosition(probe_position);
    current_session.setLittleKeyCount(little_keys_before);

    var locomotion_status = try locomotion.inspectCurrentStatus(&room, current_session);
    const pre_transition_locomotion_status = locomotion_status;
    const effect_summary = try zone_effects.applyContainingZoneEffects(&room, &current_session, zones);
    const pending_transition = current_session.pendingRoomTransition();
    const pending_destination_cube: ?i16 = if (pending_transition) |transition| transition.destination_cube else null;
    const pending_destination_world_position: ?RoomTransitionWorldPositionSummary = if (pending_transition) |transition|
        roomTransitionWorldPositionSummary(transition.destination_world_position)
    else
        null;

    if (!effect_summary.triggered_room_transition) {
        return .{
            .little_keys_before = little_keys_before,
            .little_keys_after = current_session.littleKeyCount(),
            .triggered_room_transition = false,
            .secret_room_door_event = secretRoomDoorEventName(effect_summary.secret_room_door_event),
            .pending_destination_cube = pending_destination_cube,
            .pending_destination_world_position = pending_destination_world_position,
            .result = null,
            .rejection_reason = null,
            .destination_scene_entry_index = null,
            .destination_background_entry_index = null,
            .hero_position = null,
            .post_load_diagnostics = null,
        };
    }
    _ = pending_transition orelse return error.MissingRuntimePendingRoomTransition;

    const transition_result = try runtime_transition.applyPendingRoomTransition(
        allocator,
        resolved,
        &room,
        &current_session,
        &locomotion_status,
        pre_transition_locomotion_status,
    );

    return switch (transition_result) {
        .committed => |value| .{
            .little_keys_before = little_keys_before,
            .little_keys_after = current_session.littleKeyCount(),
            .triggered_room_transition = true,
            .secret_room_door_event = secretRoomDoorEventName(effect_summary.secret_room_door_event),
            .pending_destination_cube = pending_destination_cube,
            .pending_destination_world_position = pending_destination_world_position,
            .result = "committed",
            .rejection_reason = null,
            .destination_scene_entry_index = value.destination_scene_entry_index,
            .destination_background_entry_index = value.destination_background_entry_index,
            .hero_position = roomTransitionWorldPositionSummary(value.hero_position),
            .post_load_diagnostics = null,
        },
        .rejected => |value| .{
            .little_keys_before = little_keys_before,
            .little_keys_after = current_session.littleKeyCount(),
            .triggered_room_transition = true,
            .secret_room_door_event = secretRoomDoorEventName(effect_summary.secret_room_door_event),
            .pending_destination_cube = pending_destination_cube,
            .pending_destination_world_position = pending_destination_world_position,
            .result = "rejected",
            .rejection_reason = @tagName(value.reason),
            .destination_scene_entry_index = null,
            .destination_background_entry_index = null,
            .hero_position = roomTransitionWorldPositionSummary(value.hero_position),
            .post_load_diagnostics = if (value.post_load_adjustment_failure) |failure| roomTransitionPostLoadDiagnosticsSummary(failure) else null,
        },
    };
}

fn secretRoomDoorEventName(event: ?zone_effects.SecretRoomDoorEvent) ?[]const u8 {
    return if (event) |value| @tagName(value) else null;
}

fn runtimeEffectEventName(effect: ?RoomTransitionRuntimeEffectSummary) []const u8 {
    if (effect) |value| return value.secret_room_door_event orelse "none";
    return "none";
}

fn runtimeEffectResultName(effect: ?RoomTransitionRuntimeEffectSummary) []const u8 {
    if (effect) |value| {
        if (!value.triggered_room_transition) return "no_transition";
        return value.result orelse "pending";
    }
    return "none";
}

fn runtimeEffectLittleKeysAfter(effect: ?RoomTransitionRuntimeEffectSummary) i16 {
    if (effect) |value| return @intCast(value.little_keys_after);
    return -1;
}

fn roomTransitionPostLoadDiagnosticsSummary(
    failure: runtime_transition.PostLoadAdjustmentFailure,
) RoomTransitionPostLoadDiagnosticsSummary {
    return .{
        .move_target_status = @tagName(failure.move_target_status),
        .shadow_adjustment_failure = if (failure.shadow_adjustment_failure) |shadow_failure| @tagName(shadow_failure) else null,
        .provisional_world_position = roomTransitionWorldPositionSummary(failure.provisional_world_position),
        .raw_cell = roomTransitionRawCellSummary(failure.raw_cell),
        .occupied_coverage = roomTransitionOccupiedCoverageSummary(failure.occupied_coverage),
        .nearest_occupied = if (failure.nearest_occupied) |candidate| roomTransitionDiagnosticCandidateSummary(candidate) else null,
        .nearest_standable = if (failure.nearest_standable) |candidate| roomTransitionDiagnosticCandidateSummary(candidate) else null,
    };
}

fn heroStartWorldPoint(room: *const room_state.RoomSnapshot) locomotion.WorldPointSnapshot {
    return .{
        .x = room.scene.hero_start.x,
        .y = room.scene.hero_start.y,
        .z = room.scene.hero_start.z,
    };
}

fn roomTransitionWorldPositionSummary(
    position: locomotion.WorldPointSnapshot,
) RoomTransitionWorldPositionSummary {
    return .{
        .x = position.x,
        .y = position.y,
        .z = position.z,
    };
}

fn roomTransitionRawCellSummary(
    probe: runtime_query.WorldPointCellProbe,
) RoomTransitionRawCellSummary {
    return .{
        .world_x = probe.world_x,
        .world_z = probe.world_z,
        .cell = if (probe.cell) |cell| .{ .x = cell.x, .z = cell.z } else null,
        .status = @tagName(probe.status),
        .occupied = probe.occupied,
        .surface_top_y = if (probe.surface) |surface| surface.top_y else null,
        .surface_total_height = if (probe.surface) |surface| surface.total_height else null,
        .surface_stack_depth = if (probe.surface) |surface| surface.stack_depth else null,
        .surface_floor_type = if (probe.surface) |surface| surface.top_floor_type else null,
        .surface_shape_class = if (probe.surface) |surface| @tagName(surface.top_shape_class) else null,
        .standability = if (probe.standability) |standability| @tagName(standability) else null,
    };
}

fn roomTransitionOccupiedCoverageSummary(
    coverage: runtime_query.OccupiedCoverageProbe,
) RoomTransitionOccupiedCoverageSummary {
    return .{
        .relation = @tagName(coverage.relation),
        .occupied_bounds = coverage.occupied_bounds,
        .x_cells_from_bounds = coverage.x_cells_from_bounds,
        .z_cells_from_bounds = coverage.z_cells_from_bounds,
    };
}

fn roomTransitionDiagnosticCandidateSummary(
    candidate: runtime_query.DiagnosticCandidate,
) RoomTransitionDiagnosticCandidateSummary {
    return .{
        .cell = .{ .x = candidate.cell.x, .z = candidate.cell.z },
        .world_bounds = .{
            .min_x = candidate.world_bounds.min_x,
            .max_x = candidate.world_bounds.max_x,
            .min_z = candidate.world_bounds.min_z,
            .max_z = candidate.world_bounds.max_z,
        },
        .surface_top_y = candidate.surface.top_y,
        .surface_total_height = candidate.surface.total_height,
        .surface_stack_depth = candidate.surface.stack_depth,
        .surface_floor_type = candidate.surface.top_floor_type,
        .surface_shape_class = @tagName(candidate.surface.top_shape_class),
        .standability = @tagName(candidate.standability),
        .x_distance = candidate.x_distance,
        .z_distance = candidate.z_distance,
        .distance_sq = candidate.distance_sq,
    };
}

fn buildRoomFragmentZoneDiagnosticsPayload(
    allocator: std.mem.Allocator,
    diagnostics_snapshot: room_state.RoomFragmentZoneDiagnostics,
) !RoomFragmentZoneDiagnosticsPayload {
    const zones = try allocator.alloc(RoomFragmentZoneDiagnosticSummary, diagnostics_snapshot.zones.len);
    errdefer allocator.free(zones);

    for (diagnostics_snapshot.zones, zones) |zone, *slot| {
        slot.* = .{
            .zone_index = zone.zone_index,
            .zone_num = zone.zone_num,
            .grm_index = zone.grm_index,
            .initially_on = zone.initially_on,
            .issue = @tagName(zone.issue),
            .fragment_entry_index = zone.fragment_entry_index,
            .fragment_dimensions = zone.fragment_dimensions,
            .x_axis = zone.x_axis,
            .y_axis = zone.y_axis,
            .z_axis = zone.z_axis,
        };
    }

    return .{
        .command = "inspect-room-fragment-zones",
        .scene_entry_index = diagnostics_snapshot.scene_entry_index,
        .background_entry_index = diagnostics_snapshot.background_entry_index,
        .classic_loader_scene_number = diagnostics_snapshot.classic_loader_scene_number,
        .scene_kind = diagnostics_snapshot.scene_kind,
        .fragment_count = diagnostics_snapshot.fragment_count,
        .grm_zone_count = diagnostics_snapshot.grm_zone_count,
        .compatible_zone_count = diagnostics_snapshot.compatible_zone_count,
        .invalid_zone_count = diagnostics_snapshot.invalid_zone_count,
        .first_invalid_zone_index = diagnostics_snapshot.first_invalid_zone_index,
        .zones = zones,
    };
}

fn auditLifePrograms(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths, parsed: ParsedArgs) !void {
    const absolute_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(absolute_path);

    const scene_entry_indices = try life_audit.resolveSceneEntryIndicesAlloc(allocator, absolute_path, parsed.lifeAuditSelection());
    defer allocator.free(scene_entry_indices);

    const audits = try life_audit.auditSceneLifeProgramsForEntryIndices(allocator, absolute_path, scene_entry_indices);
    defer allocator.free(audits);

    const unsupported_summary = try buildUnsupportedLifeSummary(allocator, audits);
    defer allocator.free(unsupported_summary);
    const scene_entry_summary = try formatSceneEntryIndicesAlloc(allocator, scene_entry_indices);
    defer allocator.free(scene_entry_summary);

    var unsupported_blob_count: usize = 0;
    for (audits) |audit| {
        if (audit.status == .unsupported_opcode) unsupported_blob_count += 1;
    }

    if (parsed.output_json) {
        const json_samples = try buildLifeAuditJsonSamples(allocator, audits);
        defer allocator.free(json_samples);

        const payload = .{
            .asset_path = "SCENE.HQR",
            .selection_mode = parsed.lifeAuditSelectionMode(),
            .scene_entry_indices = scene_entry_indices,
            .blob_count = audits.len,
            .unsupported_blob_count = unsupported_blob_count,
            .unsupported_unique_opcode_count = unsupported_summary.len,
            .unsupported_opcodes = unsupported_summary,
            .samples = json_samples,
        };
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "command", .value = "audit-life-programs" },
        .{ .key = "asset_path", .value = "SCENE.HQR" },
    });
    try stderr.print(
        "selection_mode={s} scene_entries={s} blob_count={d} unsupported_blobs={d} unsupported_unique_opcodes={d}\n",
        .{ parsed.lifeAuditSelectionMode(), scene_entry_summary, audits.len, unsupported_blob_count, unsupported_summary.len },
    );
    if (unsupported_summary.len == 0) {
        try stderr.writeAll("unsupported_opcodes=none\n");
    } else {
        try stderr.writeAll("unsupported_opcodes=");
        for (unsupported_summary, 0..) |entry, index| {
            if (index != 0) try stderr.writeAll("|");
            try stderr.writeAll(entry.mnemonic);
        }
        try stderr.writeAll("\n");
    }

    for (audits) |audit| {
        switch (audit.status) {
            .unsupported_opcode => |unsupported| {
                try stderr.print(
                    "scene_entry_index={d} classic_loader_scene_number={any} scene_kind={s} owner={s} object_index={any} life_bytes={d} decoded_instructions={d} decoded_bytes={d} unsupported_opcode={s} opcode_id={d} offset={d}\n",
                    .{
                        audit.scene_entry_index,
                        audit.classic_loader_scene_number,
                        audit.scene_kind,
                        lifeOwnerKind(audit.owner),
                        lifeOwnerObjectIndex(audit.owner),
                        audit.life_byte_length,
                        audit.instruction_count,
                        audit.decoded_byte_length,
                        unsupported.opcode.mnemonic(),
                        unsupported.opcode_id,
                        unsupported.offset,
                    },
                );
            },
            .unknown_opcode => |unknown| {
                try stderr.print(
                    "scene_entry_index={d} classic_loader_scene_number={any} scene_kind={s} owner={s} object_index={any} life_bytes={d} decoded_instructions={d} decoded_bytes={d} status=unknown_opcode opcode_id={d} offset={d}\n",
                    .{
                        audit.scene_entry_index,
                        audit.classic_loader_scene_number,
                        audit.scene_kind,
                        lifeOwnerKind(audit.owner),
                        lifeOwnerObjectIndex(audit.owner),
                        audit.life_byte_length,
                        audit.instruction_count,
                        audit.decoded_byte_length,
                        unknown.opcode_id,
                        unknown.offset,
                    },
                );
            },
            .truncated_operand,
            .malformed_string_operand,
            .missing_switch_context,
            .unknown_life_function,
            .unknown_life_comparator,
            => {
                try stderr.print(
                    "scene_entry_index={d} classic_loader_scene_number={any} scene_kind={s} owner={s} object_index={any} life_bytes={d} decoded_instructions={d} decoded_bytes={d} status={s}\n",
                    .{
                        audit.scene_entry_index,
                        audit.classic_loader_scene_number,
                        audit.scene_kind,
                        lifeOwnerKind(audit.owner),
                        lifeOwnerObjectIndex(audit.owner),
                        audit.life_byte_length,
                        audit.instruction_count,
                        audit.decoded_byte_length,
                        lifeAuditStatusName(audit.status),
                    },
                );
            },
            .decoded => {},
        }
    }
    try stderr.flush();
}

fn rankDecodedInteriorCandidates(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    output_json: bool,
) !void {
    const absolute_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(absolute_path);

    const ranked = try life_audit.rankDecodedInteriorSceneCandidates(allocator, absolute_path);
    defer allocator.free(ranked);
    if (ranked.len == 0) return error.NoDecodedInteriorSceneCandidates;

    const payload = try buildRankedDecodedInteriorCandidatesPayload(allocator, ranked);
    defer allocator.free(payload.candidates);

    if (output_json) {
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "command", .value = "rank-decoded-interior-candidates" },
        .{ .key = "asset_path", .value = "SCENE.HQR" },
    });
    try stderr.print(
        "ranking_basis={s} candidate_count={d} current_supported_baseline_scene_entry_index={d} current_supported_baseline_rank={d} current_supported_baseline_is_top_candidate={}\n",
        .{
            formatRankingBasis(),
            payload.candidate_count,
            payload.current_supported_baseline_scene_entry_index,
            payload.current_supported_baseline_rank,
            payload.current_supported_baseline_is_top_candidate,
        },
    );
    try printRankedDecodedInteriorCandidate(stderr, "top_candidate", payload.top_candidate);
    try printRankedDecodedInteriorCandidate(stderr, "current_supported_baseline", payload.current_supported_baseline);
    for (payload.candidates) |candidate| {
        try printRankedDecodedInteriorCandidate(stderr, "candidate", candidate);
    }
    try stderr.flush();
}

fn triageSameIndexDecodedInteriorCandidates(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    output_json: bool,
) !void {
    const absolute_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(absolute_path);

    const ranked = try life_audit.rankDecodedInteriorSceneCandidates(allocator, absolute_path);
    defer allocator.free(ranked);
    if (ranked.len == 0) return error.NoDecodedInteriorSceneCandidates;

    const payload = try buildSameIndexDecodedInteriorCandidateTriagePayload(allocator, resolved, ranked);
    defer allocator.free(payload.candidates);

    if (output_json) {
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try printSameIndexDecodedInteriorCandidateTriagePayload(stderr, payload);
    try stderr.flush();
}

fn printUnsupportedSceneLifeDiagnostic(
    writer: anytype,
    scene_entry_index: usize,
    background_entry_index: usize,
    hit: room_state.UnsupportedSceneLifeHit,
) !void {
    var classic_loader_scene_number_buffer: [16]u8 = undefined;
    var object_index_buffer: [16]u8 = undefined;
    try writer.print(
        "event=room_load_rejected scene_entry_index={d} background_entry_index={d} reason=unsupported_life_blob classic_loader_scene_number={s} scene_kind={s} unsupported_life_owner_kind={s} unsupported_life_object_index={s} unsupported_life_opcode_name={s} unsupported_life_opcode_id={d} unsupported_life_offset={d}\n",
        .{
            scene_entry_index,
            background_entry_index,
            formatOptionalUsize(&classic_loader_scene_number_buffer, hit.classic_loader_scene_number),
            hit.scene_kind,
            lifeOwnerKind(hit.owner),
            formatOptionalUsize(&object_index_buffer, lifeOwnerObjectIndex(hit.owner)),
            hit.unsupported_opcode_mnemonic,
            hit.unsupported_opcode_id,
            hit.byte_offset,
        },
    );
}

fn printFragmentZoneBoundsDiagnostic(
    writer: anytype,
    diagnostics_snapshot: room_state.RoomFragmentZoneDiagnostics,
) !void {
    var classic_loader_scene_number_buffer: [16]u8 = undefined;
    try writer.print(
        "event=room_load_rejected scene_entry_index={d} background_entry_index={d} reason=invalid_fragment_zone_bounds classic_loader_scene_number={s} scene_kind={s} invalid_fragment_zone_issue_count={d}\n",
        .{
            diagnostics_snapshot.scene_entry_index,
            diagnostics_snapshot.background_entry_index,
            formatOptionalUsize(&classic_loader_scene_number_buffer, diagnostics_snapshot.classic_loader_scene_number),
            diagnostics_snapshot.scene_kind,
            diagnostics_snapshot.invalid_zone_count,
        },
    );

    for (diagnostics_snapshot.zones) |zone| {
        if (zone.issue == .compatible) continue;

        if (fragmentZoneAxisDiagnostic(zone)) |axis| {
            try writer.print(
                "event=fragment_zone_validation_issue scene_entry_index={d} background_entry_index={d} zone_index={d} zone_num={d} grm_index={d} fragment_entry_index={any} axis={s} min_value={d} max_value={d} unit={d} failure_reason={s} issue={s} origin_floor_value={any} origin_floor_cell={any} origin_floor_delta={any} origin_ceil_value={any} origin_ceil_cell={any} origin_ceil_delta={any}\n",
                .{
                    diagnostics_snapshot.scene_entry_index,
                    diagnostics_snapshot.background_entry_index,
                    zone.zone_index,
                    zone.zone_num,
                    zone.grm_index,
                    zone.fragment_entry_index,
                    fragmentZoneIssueAxisName(zone.issue),
                    axis.min_value,
                    axis.max_value,
                    axis.unit,
                    fragmentZoneFailureReasonName(zone.issue, axis),
                    @tagName(zone.issue),
                    axis.origin_floor_value,
                    axis.origin_floor_cell,
                    axis.origin_floor_delta,
                    axis.origin_ceil_value,
                    axis.origin_ceil_cell,
                    axis.origin_ceil_delta,
                },
            );
        } else {
            try writer.print(
                "event=fragment_zone_validation_issue scene_entry_index={d} background_entry_index={d} zone_index={d} zone_num={d} grm_index={d} fragment_entry_index={any} axis=none failure_reason={s} issue={s}\n",
                .{
                    diagnostics_snapshot.scene_entry_index,
                    diagnostics_snapshot.background_entry_index,
                    zone.zone_index,
                    zone.zone_num,
                    zone.grm_index,
                    zone.fragment_entry_index,
                    fragmentZoneNonAxisFailureReasonName(zone.issue),
                    @tagName(zone.issue),
                },
            );
        }
    }
}

fn fragmentZoneAxisDiagnostic(
    zone: room_state.FragmentZoneCompatibilityDiagnostic,
) ?room_state.FragmentZoneAxisDiagnostic {
    return switch (zone.issue) {
        .invalid_x_axis_origin, .invalid_x_axis_span => zone.x_axis,
        .invalid_y_axis_span => zone.y_axis,
        .invalid_z_axis_origin, .invalid_z_axis_span => zone.z_axis,
        else => null,
    };
}

fn fragmentZoneIssueAxisName(issue: room_state.FragmentZoneCompatibilityIssue) []const u8 {
    return switch (issue) {
        .invalid_x_axis_origin, .invalid_x_axis_span => "x",
        .invalid_y_axis_span => "y",
        .invalid_z_axis_origin, .invalid_z_axis_span => "z",
        else => "none",
    };
}

fn fragmentZoneFailureReasonName(
    issue: room_state.FragmentZoneCompatibilityIssue,
    axis: room_state.FragmentZoneAxisDiagnostic,
) []const u8 {
    return switch (issue) {
        .invalid_x_axis_origin,
        .invalid_z_axis_origin,
        => if (axis.origin_remainder == null) "negative_min" else "misaligned_min",
        .invalid_x_axis_span,
        .invalid_y_axis_span,
        .invalid_z_axis_span,
        => if (!axis.span_non_negative) "reversed_bounds" else "misaligned_span",
        else => "unknown",
    };
}

fn fragmentZoneNonAxisFailureReasonName(issue: room_state.FragmentZoneCompatibilityIssue) []const u8 {
    return switch (issue) {
        .invalid_fragment_zone_index => "invalid_fragment_zone_index",
        .fragment_zone_index_out_of_range => "fragment_zone_index_out_of_range",
        .footprint_mismatch => "footprint_mismatch",
        else => "unknown",
    };
}

fn buildRankedDecodedInteriorCandidatesPayload(
    allocator: std.mem.Allocator,
    ranked: []const life_audit.RankedDecodedInteriorSceneCandidate,
) !RankedDecodedInteriorCandidatesPayload {
    const current_supported_baseline_scene_entry_index: usize = 19;
    const candidates = try buildRankedDecodedInteriorCandidateSummaries(allocator, ranked, current_supported_baseline_scene_entry_index);
    errdefer allocator.free(candidates);

    const baseline_index = life_audit.findRankedDecodedInteriorSceneCandidateIndex(ranked, current_supported_baseline_scene_entry_index) orelse return error.MissingCurrentSupportedBaselineCandidate;

    return .{
        .command = "rank-decoded-interior-candidates",
        .ranking_basis = &life_audit.ranked_decoded_interior_scene_candidate_basis,
        .candidate_count = candidates.len,
        .current_supported_baseline_scene_entry_index = current_supported_baseline_scene_entry_index,
        .current_supported_baseline_rank = baseline_index + 1,
        .current_supported_baseline_is_top_candidate = baseline_index == 0,
        .top_candidate = candidates[0],
        .current_supported_baseline = candidates[baseline_index],
        .candidates = candidates,
    };
}

fn buildSameIndexDecodedInteriorCandidateTriagePayload(
    allocator: std.mem.Allocator,
    resolved: paths_mod.ResolvedPaths,
    ranked: []const life_audit.RankedDecodedInteriorSceneCandidate,
) !SameIndexDecodedInteriorCandidateTriagePayload {
    const current_supported_baseline_scene_entry_index: usize = 19;
    var summaries: std.ArrayList(SameIndexDecodedInteriorCandidateTriageSummary) = .empty;
    defer summaries.deinit(allocator);

    for (ranked, 0..) |candidate, index| {
        const diagnostics_snapshot = try room_state.inspectRoomFragmentZoneDiagnostics(
            allocator,
            resolved,
            candidate.scene_entry_index,
            candidate.scene_entry_index,
        );
        defer diagnostics_snapshot.deinit(allocator);

        const summary = buildSameIndexDecodedInteriorCandidateTriageSummary(
            index + 1,
            candidate,
            diagnostics_snapshot,
            current_supported_baseline_scene_entry_index,
        );

        try summaries.append(allocator, summary);
    }

    return buildSameIndexDecodedInteriorCandidateTriagePayloadFromSummaries(
        allocator,
        current_supported_baseline_scene_entry_index,
        summaries.items,
    );
}

fn buildSameIndexDecodedInteriorCandidateTriagePayloadFromSummaries(
    allocator: std.mem.Allocator,
    current_supported_baseline_scene_entry_index: usize,
    summaries: []const SameIndexDecodedInteriorCandidateTriageSummary,
) !SameIndexDecodedInteriorCandidateTriagePayload {
    const baseline_index = findSameIndexDecodedInteriorCandidateTriageSummaryIndex(
        summaries,
        current_supported_baseline_scene_entry_index,
    ) orelse return error.MissingCurrentSupportedBaselineCandidate;

    const owned_candidates = try allocator.dupe(SameIndexDecodedInteriorCandidateTriageSummary, summaries);
    errdefer allocator.free(owned_candidates);

    var compatible_candidate_count: usize = 0;
    var compatible_candidate_count_above_baseline: usize = 0;
    var highest_ranked_compatible_candidate: ?SameIndexDecodedInteriorCandidateTriageSummary = null;
    var highest_ranked_compatible_candidate_above_baseline: ?SameIndexDecodedInteriorCandidateTriageSummary = null;
    var highest_ranked_fragment_bearing_compatible_candidate: ?SameIndexDecodedInteriorCandidateTriageSummary = null;
    var highest_ranked_fragment_bearing_compatible_candidate_above_baseline: ?SameIndexDecodedInteriorCandidateTriageSummary = null;

    for (owned_candidates) |summary| {
        if (summary.compatible) {
            compatible_candidate_count += 1;
            if (highest_ranked_compatible_candidate == null) highest_ranked_compatible_candidate = summary;
            if (summary.rank < baseline_index + 1) {
                compatible_candidate_count_above_baseline += 1;
                if (highest_ranked_compatible_candidate_above_baseline == null) {
                    highest_ranked_compatible_candidate_above_baseline = summary;
                }
            }
        }

        if (isFragmentBearingCompatibleSameIndexCandidate(summary)) {
            if (highest_ranked_fragment_bearing_compatible_candidate == null) {
                highest_ranked_fragment_bearing_compatible_candidate = summary;
            }
            if (summary.rank < baseline_index + 1 and highest_ranked_fragment_bearing_compatible_candidate_above_baseline == null) {
                highest_ranked_fragment_bearing_compatible_candidate_above_baseline = summary;
            }
        }
    }

    return .{
        .command = "triage-same-index-decoded-interior-candidates",
        .ranking_basis = &life_audit.ranked_decoded_interior_scene_candidate_basis,
        .candidate_count = owned_candidates.len,
        .compatible_candidate_count = compatible_candidate_count,
        .compatible_candidate_count_above_baseline = compatible_candidate_count_above_baseline,
        .current_supported_baseline_scene_entry_index = current_supported_baseline_scene_entry_index,
        .current_supported_baseline_rank = baseline_index + 1,
        .current_supported_baseline = owned_candidates[baseline_index],
        .highest_ranked_compatible_candidate = highest_ranked_compatible_candidate,
        .highest_ranked_compatible_candidate_outranks_current_supported_baseline = if (highest_ranked_compatible_candidate) |candidate| candidate.rank < baseline_index + 1 else false,
        .highest_ranked_compatible_candidate_above_baseline = highest_ranked_compatible_candidate_above_baseline,
        .highest_ranked_fragment_bearing_compatible_candidate = highest_ranked_fragment_bearing_compatible_candidate,
        .highest_ranked_fragment_bearing_compatible_candidate_outranks_current_supported_baseline = if (highest_ranked_fragment_bearing_compatible_candidate) |candidate| candidate.rank < baseline_index + 1 else false,
        .highest_ranked_fragment_bearing_compatible_candidate_above_baseline = highest_ranked_fragment_bearing_compatible_candidate_above_baseline,
        .candidates = owned_candidates,
    };
}

fn findSameIndexDecodedInteriorCandidateTriageSummaryIndex(
    summaries: []const SameIndexDecodedInteriorCandidateTriageSummary,
    scene_entry_index: usize,
) ?usize {
    for (summaries, 0..) |summary, index| {
        if (summary.scene_entry_index == scene_entry_index) return index;
    }
    return null;
}

fn isFragmentBearingCompatibleSameIndexCandidate(candidate: SameIndexDecodedInteriorCandidateTriageSummary) bool {
    return candidate.compatible and candidate.fragment_count > 0 and candidate.grm_zone_count > 0;
}

fn buildSameIndexDecodedInteriorCandidateTriageSummary(
    rank: usize,
    candidate: life_audit.RankedDecodedInteriorSceneCandidate,
    diagnostics_snapshot: room_state.RoomFragmentZoneDiagnostics,
    current_supported_baseline_scene_entry_index: usize,
) SameIndexDecodedInteriorCandidateTriageSummary {
    const first_invalid = firstInvalidFragmentZoneSummary(diagnostics_snapshot.zones);

    return .{
        .rank = rank,
        .scene_entry_index = candidate.scene_entry_index,
        .classic_loader_scene_number = candidate.classic_loader_scene_number,
        .scene_kind = candidate.scene_kind,
        .blob_count = candidate.blob_count,
        .object_count = candidate.object_count,
        .zone_count = candidate.zone_count,
        .track_count = candidate.track_count,
        .patch_count = candidate.patch_count,
        .is_current_supported_baseline = candidate.scene_entry_index == current_supported_baseline_scene_entry_index,
        .fragment_count = diagnostics_snapshot.fragment_count,
        .grm_zone_count = diagnostics_snapshot.grm_zone_count,
        .compatible_zone_count = diagnostics_snapshot.compatible_zone_count,
        .invalid_zone_count = diagnostics_snapshot.invalid_zone_count,
        .first_invalid_zone_index = diagnostics_snapshot.first_invalid_zone_index,
        .first_invalid_issue = if (first_invalid) |entry| entry.issue else null,
        .first_invalid_axis = if (first_invalid) |entry| entry.axis else null,
        .first_invalid_failure_reason = if (first_invalid) |entry| entry.failure_reason else null,
        .first_invalid_zone_num = if (first_invalid) |entry| entry.zone_num else null,
        .first_invalid_grm_index = if (first_invalid) |entry| entry.grm_index else null,
        .first_invalid_fragment_entry_index = if (first_invalid) |entry| entry.fragment_entry_index else null,
        .compatible = diagnostics_snapshot.invalid_zone_count == 0,
    };
}

fn firstInvalidFragmentZoneSummary(
    zones: []const room_state.FragmentZoneCompatibilityDiagnostic,
) ?FirstInvalidFragmentZoneSummary {
    for (zones) |zone| {
        if (zone.issue == .compatible) continue;

        if (fragmentZoneAxisDiagnostic(zone)) |axis| {
            return .{
                .zone_index = zone.zone_index,
                .zone_num = zone.zone_num,
                .grm_index = zone.grm_index,
                .fragment_entry_index = zone.fragment_entry_index,
                .issue = @tagName(zone.issue),
                .axis = fragmentZoneIssueAxisName(zone.issue),
                .failure_reason = fragmentZoneFailureReasonName(zone.issue, axis),
            };
        }

        return .{
            .zone_index = zone.zone_index,
            .zone_num = zone.zone_num,
            .grm_index = zone.grm_index,
            .fragment_entry_index = zone.fragment_entry_index,
            .issue = @tagName(zone.issue),
            .axis = "none",
            .failure_reason = fragmentZoneNonAxisFailureReasonName(zone.issue),
        };
    }

    return null;
}

fn inspectLifeProgram(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths, parsed: ParsedArgs) !void {
    const absolute_path = try std.fs.path.join(allocator, &.{ resolved.asset_root, "SCENE.HQR" });
    defer allocator.free(absolute_path);

    const audit = try life_audit.inspectSceneLifeProgram(
        allocator,
        absolute_path,
        parsed.entry_index.?,
        parsed.life_program_owner orelse .{ .hero = {} },
    );

    const payload = buildLifeProgramInspectionPayload(audit);
    if (parsed.output_json) {
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "command", .value = "inspect-life-program" },
        .{ .key = "asset_path", .value = "SCENE.HQR" },
    });
    try stderr.print(
        "scene_entry_index={d} classic_loader_scene_number={any} scene_kind={s} owner_kind={s} object_index={any} life_byte_length={d} instruction_count={d} decoded_byte_length={d} final_status={s}",
        .{
            payload.scene_entry_index,
            payload.classic_loader_scene_number,
            payload.scene_kind,
            payload.owner_kind,
            payload.object_index,
            payload.life_byte_length,
            payload.instruction_count,
            payload.decoded_byte_length,
            payload.status,
        },
    );
    if (payload.unsupported) |unsupported| {
        try stderr.print(
            " unsupported_mnemonic={s} unsupported_opcode_id={d} unsupported_offset={d}",
            .{ unsupported.mnemonic, unsupported.opcode_id, unsupported.offset },
        );
    }
    if (payload.failure) |failure| {
        try stderr.print(" failure_kind={s}", .{failure.kind});
        if (failure.opcode_id) |opcode_id| {
            try stderr.print(" failure_opcode_id={d}", .{opcode_id});
        }
        if (failure.offset) |offset| {
            try stderr.print(" failure_offset={d}", .{offset});
        }
    }
    try stderr.writeAll("\n");
    try stderr.flush();
}

fn appendSceneEntry(
    scene_entry_indices: *std.ArrayList(usize),
    allocator: std.mem.Allocator,
    entry_index: usize,
) !void {
    if (entry_index < 2) return error.InvalidSceneEntryIndex;

    for (scene_entry_indices.items) |existing_entry_index| {
        if (existing_entry_index == entry_index) return error.DuplicateSceneEntryIndex;
    }
    try scene_entry_indices.append(allocator, entry_index);
}

fn formatSceneEntryIndicesAlloc(allocator: std.mem.Allocator, scene_entry_indices: []const usize) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();

    const writer = &output.writer;
    for (scene_entry_indices, 0..) |entry_index, index| {
        if (index != 0) try writer.writeAll("|");
        try writer.print("{d}", .{entry_index});
    }

    return output.toOwnedSlice();
}

fn buildRankedDecodedInteriorCandidateSummaries(
    allocator: std.mem.Allocator,
    ranked: []const life_audit.RankedDecodedInteriorSceneCandidate,
    current_supported_baseline_scene_entry_index: usize,
) ![]RankedDecodedInteriorCandidateSummary {
    var summaries: std.ArrayList(RankedDecodedInteriorCandidateSummary) = .empty;
    errdefer summaries.deinit(allocator);

    for (ranked, 0..) |candidate, index| {
        try summaries.append(allocator, .{
            .rank = index + 1,
            .scene_entry_index = candidate.scene_entry_index,
            .classic_loader_scene_number = candidate.classic_loader_scene_number,
            .scene_kind = candidate.scene_kind,
            .blob_count = candidate.blob_count,
            .object_count = candidate.object_count,
            .zone_count = candidate.zone_count,
            .track_count = candidate.track_count,
            .patch_count = candidate.patch_count,
            .is_current_supported_baseline = candidate.scene_entry_index == current_supported_baseline_scene_entry_index,
        });
    }

    return summaries.toOwnedSlice(allocator);
}

fn printRankedDecodedInteriorCandidate(
    writer: anytype,
    label: []const u8,
    candidate: RankedDecodedInteriorCandidateSummary,
) !void {
    try writer.print(
        "{s} rank={d} scene_entry_index={d} classic_loader_scene_number={any} scene_kind={s} blob_count={d} object_count={d} zone_count={d} track_count={d} patch_count={d} current_supported_baseline={}\n",
        .{
            label,
            candidate.rank,
            candidate.scene_entry_index,
            candidate.classic_loader_scene_number,
            candidate.scene_kind,
            candidate.blob_count,
            candidate.object_count,
            candidate.zone_count,
            candidate.track_count,
            candidate.patch_count,
            candidate.is_current_supported_baseline,
        },
    );
}

fn printSameIndexDecodedInteriorCandidateTriage(
    writer: anytype,
    label: []const u8,
    candidate: SameIndexDecodedInteriorCandidateTriageSummary,
) !void {
    var first_invalid_zone_index_buffer: [16]u8 = undefined;
    var first_invalid_issue_buffer: [32]u8 = undefined;
    var first_invalid_axis_buffer: [16]u8 = undefined;
    var first_invalid_failure_reason_buffer: [32]u8 = undefined;
    var first_invalid_zone_num_buffer: [16]u8 = undefined;
    var first_invalid_grm_index_buffer: [16]u8 = undefined;
    var first_invalid_fragment_entry_index_buffer: [16]u8 = undefined;
    try writer.print(
        "{s} rank={d} scene_entry_index={d} classic_loader_scene_number={any} scene_kind={s} blob_count={d} object_count={d} zone_count={d} track_count={d} patch_count={d} current_supported_baseline={} compatible={} fragment_count={d} grm_zone_count={d} compatible_zone_count={d} invalid_zone_count={d} first_invalid_zone_index={s} first_invalid_issue={s} first_invalid_axis={s} first_invalid_failure_reason={s} first_invalid_zone_num={s} first_invalid_grm_index={s} first_invalid_fragment_entry_index={s}\n",
        .{
            label,
            candidate.rank,
            candidate.scene_entry_index,
            candidate.classic_loader_scene_number,
            candidate.scene_kind,
            candidate.blob_count,
            candidate.object_count,
            candidate.zone_count,
            candidate.track_count,
            candidate.patch_count,
            candidate.is_current_supported_baseline,
            candidate.compatible,
            candidate.fragment_count,
            candidate.grm_zone_count,
            candidate.compatible_zone_count,
            candidate.invalid_zone_count,
            formatOptionalUsize(&first_invalid_zone_index_buffer, candidate.first_invalid_zone_index),
            formatOptionalString(&first_invalid_issue_buffer, candidate.first_invalid_issue),
            formatOptionalString(&first_invalid_axis_buffer, candidate.first_invalid_axis),
            formatOptionalString(&first_invalid_failure_reason_buffer, candidate.first_invalid_failure_reason),
            formatOptionalI16(&first_invalid_zone_num_buffer, candidate.first_invalid_zone_num),
            formatOptionalI32(&first_invalid_grm_index_buffer, candidate.first_invalid_grm_index),
            formatOptionalUsize(&first_invalid_fragment_entry_index_buffer, candidate.first_invalid_fragment_entry_index),
        },
    );
}

fn printSameIndexDecodedInteriorCandidateTriagePayload(
    writer: anytype,
    payload: SameIndexDecodedInteriorCandidateTriagePayload,
) !void {
    try diagnostics.printLine(writer, &.{
        .{ .key = "command", .value = "triage-same-index-decoded-interior-candidates" },
        .{ .key = "asset_path", .value = "SCENE.HQR" },
    });
    try writer.print(
        "ranking_basis={s} candidate_count={d} compatible_candidate_count={d} compatible_candidate_count_above_baseline={d} current_supported_baseline_scene_entry_index={d} current_supported_baseline_rank={d}\n",
        .{
            formatRankingBasis(),
            payload.candidate_count,
            payload.compatible_candidate_count,
            payload.compatible_candidate_count_above_baseline,
            payload.current_supported_baseline_scene_entry_index,
            payload.current_supported_baseline_rank,
        },
    );
    try printSameIndexDecodedInteriorCandidateTriage(writer, "current_supported_baseline", payload.current_supported_baseline);
    if (payload.highest_ranked_compatible_candidate) |candidate| {
        try printSameIndexDecodedInteriorCandidateTriage(writer, "highest_ranked_compatible_candidate", candidate);
    } else {
        try writer.writeAll("highest_ranked_compatible_candidate=none\n");
    }
    if (payload.highest_ranked_compatible_candidate_above_baseline) |candidate| {
        try printSameIndexDecodedInteriorCandidateTriage(writer, "highest_ranked_compatible_candidate_above_baseline", candidate);
    } else {
        try writer.writeAll("highest_ranked_compatible_candidate_above_baseline=none\n");
    }
    try writer.print(
        "highest_ranked_compatible_candidate_outranks_current_supported_baseline={}\n",
        .{payload.highest_ranked_compatible_candidate_outranks_current_supported_baseline},
    );
    if (payload.highest_ranked_fragment_bearing_compatible_candidate) |candidate| {
        try printSameIndexDecodedInteriorCandidateTriage(writer, "highest_ranked_fragment_bearing_compatible_candidate", candidate);
    } else {
        try writer.writeAll("highest_ranked_fragment_bearing_compatible_candidate=none\n");
    }
    if (payload.highest_ranked_fragment_bearing_compatible_candidate_above_baseline) |candidate| {
        try printSameIndexDecodedInteriorCandidateTriage(writer, "highest_ranked_fragment_bearing_compatible_candidate_above_baseline", candidate);
    } else {
        try writer.writeAll("highest_ranked_fragment_bearing_compatible_candidate_above_baseline=none\n");
    }
    try writer.print(
        "highest_ranked_fragment_bearing_compatible_candidate_outranks_current_supported_baseline={}\n",
        .{payload.highest_ranked_fragment_bearing_compatible_candidate_outranks_current_supported_baseline},
    );
    for (payload.candidates) |candidate| {
        try printSameIndexDecodedInteriorCandidateTriage(writer, "candidate", candidate);
    }
}

fn formatRankingBasis() []const u8 {
    return "track_count_desc|object_count_desc|zone_count_desc|blob_count_desc|scene_entry_index_asc";
}

fn printTrackInstructionSummary(stderr: anytype, label: []const u8, instructions: []const scene_data.TrackInstruction) !void {
    try stderr.print("{s}={d} mnemonics=", .{ label, instructions.len });
    for (instructions, 0..) |instruction, index| {
        if (index != 0) try stderr.writeAll("|");
        try stderr.writeAll(instruction.opcode.mnemonic());
    }
    try stderr.writeAll("\n");
}

fn printUsedBlockSummary(stderr: anytype, used_block_ids: []const u8) !void {
    try stderr.print("used_block_ids={d} values=", .{used_block_ids.len});
    for (used_block_ids, 0..) |block_id, index| {
        if (index != 0) try stderr.writeAll("|");
        try stderr.print("{d}", .{block_id});
    }
    try stderr.writeAll("\n");
}

fn printZone(stderr: anytype, zone: scene_data.SceneZone) !void {
    try stderr.print(
        "zone_type={s} zone_num={d} x0={d} y0={d} z0={d} x1={d} y1={d} z1={d}",
        .{ zone.zone_type.name(), zone.num, zone.x0, zone.y0, zone.z0, zone.x1, zone.y1, zone.z1 },
    );

    switch (zone.semantics) {
        .change_cube => |semantics| {
            try stderr.print(
                " destination_cube={d} destination_x={d} destination_y={d} destination_z={d} yaw={d} initially_on={}\n",
                .{
                    semantics.destination_cube,
                    semantics.destination_x,
                    semantics.destination_y,
                    semantics.destination_z,
                    semantics.yaw,
                    semantics.initially_on,
                },
            );
        },
        .camera => |semantics| {
            try stderr.print(
                " anchor_x={d} anchor_y={d} anchor_z={d} initially_on={} obligatory={}\n",
                .{
                    semantics.anchor_x,
                    semantics.anchor_y,
                    semantics.anchor_z,
                    semantics.initially_on,
                    semantics.obligatory,
                },
            );
        },
        .scenario => {
            try stderr.writeAll(" semantics=scenario\n");
        },
        .grm => |semantics| {
            try stderr.print(
                " grm_index={d} initially_on={}\n",
                .{ semantics.grm_index, semantics.initially_on },
            );
        },
        .giver => |semantics| {
            try stderr.print(
                " quantity={d} already_taken={} bonus_kinds={s}\n",
                .{
                    semantics.quantity,
                    semantics.already_taken,
                    formatBonusKinds(&semantics.bonus_kinds),
                },
            );
        },
        .message => |semantics| {
            try stderr.print(
                " dialog_id={d} linked_camera_zone_id={any} facing_direction={s}\n",
                .{
                    semantics.dialog_id,
                    semantics.linked_camera_zone_id,
                    semantics.facing_direction.name(),
                },
            );
        },
        .ladder => |semantics| {
            try stderr.print(" enabled_on_load={}\n", .{semantics.enabled_on_load});
        },
        .escalator => |semantics| {
            try stderr.print(
                " enabled={} direction={s}\n",
                .{ semantics.enabled, semantics.direction.name() },
            );
        },
        .hit => |semantics| {
            try stderr.print(
                " damage={d} cooldown_raw_value={d} initial_timer={d}\n",
                .{ semantics.damage, semantics.cooldown_raw_value, semantics.initial_timer },
            );
        },
        .rail => |semantics| {
            try stderr.print(" switch_state_on_load={}\n", .{semantics.switch_state_on_load});
        },
    }
}

fn formatBonusKinds(kinds: *const scene_data.GiverBonusKinds) []const u8 {
    if (kinds.money and kinds.life and kinds.magic and !kinds.key and !kinds.clover) return "money|life|magic";
    if (kinds.money and !kinds.life and !kinds.magic and !kinds.key and !kinds.clover) return "money";
    if (!kinds.money and kinds.life and !kinds.magic and !kinds.key and !kinds.clover) return "life";
    if (!kinds.money and !kinds.life and kinds.magic and !kinds.key and !kinds.clover) return "magic";
    if (!kinds.money and !kinds.life and !kinds.magic and kinds.key and !kinds.clover) return "key";
    if (!kinds.money and !kinds.life and !kinds.magic and !kinds.key and kinds.clover) return "clover";
    if (kinds.money and kinds.life and !kinds.magic and !kinds.key and !kinds.clover) return "money|life";
    if (kinds.money and !kinds.life and kinds.magic and !kinds.key and !kinds.clover) return "money|magic";
    if (!kinds.money and kinds.life and kinds.magic and !kinds.key and !kinds.clover) return "life|magic";
    return "mixed";
}

fn generateFixtures(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths) !void {
    const entries = try fixtures.generateFixtures(allocator, resolved);
    defer {
        for (entries) |entry| entry.deinit(allocator);
        allocator.free(entries);
    }

    const json = try fixtures.renderFixtureManifestJson(allocator, entries);
    defer allocator.free(json);

    const output_path = try std.fs.path.join(allocator, &.{ resolved.work_root, "fixture_manifest.json" });
    defer allocator.free(output_path);
    try writeJson(output_path, json);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "status", .value = "ok" },
        .{ .key = "command", .value = "generate-fixtures" },
        .{ .key = "output", .value = "work/port/phase1/fixture_manifest.json" },
    });
    try stderr.flush();
}

fn validatePhase1(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(process.currentIo(), &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const inventory = try catalog.generateAssetCatalog(allocator, resolved);
    defer {
        for (inventory) |entry| entry.deinit(allocator);
        allocator.free(inventory);
    }
    const inventory_json = try catalog.renderCatalogJson(allocator, inventory);
    defer allocator.free(inventory_json);

    const inventory_second = try catalog.generateAssetCatalog(allocator, resolved);
    defer {
        for (inventory_second) |entry| entry.deinit(allocator);
        allocator.free(inventory_second);
    }
    const inventory_json_second = try catalog.renderCatalogJson(allocator, inventory_second);
    defer allocator.free(inventory_json_second);

    if (!std.mem.eql(u8, inventory_json, inventory_json_second)) return error.NonDeterministicAssetCatalog;

    const fixtures_first = try fixtures.generateFixtures(allocator, resolved);
    defer {
        for (fixtures_first) |entry| entry.deinit(allocator);
        allocator.free(fixtures_first);
    }
    const fixture_json_first = try fixtures.renderFixtureManifestJson(allocator, fixtures_first);
    defer allocator.free(fixture_json_first);

    const fixtures_second = try fixtures.generateFixtures(allocator, resolved);
    defer {
        for (fixtures_second) |entry| entry.deinit(allocator);
        allocator.free(fixtures_second);
    }
    const fixture_json_second = try fixtures.renderFixtureManifestJson(allocator, fixtures_second);
    defer allocator.free(fixture_json_second);

    if (!std.mem.eql(u8, fixture_json_first, fixture_json_second)) return error.NonDeterministicFixtureManifest;
    if (!sameFixtureHashes(fixtures_first, fixtures_second)) return error.NonDeterministicFixtureBytes;

    const inventory_path = try std.fs.path.join(allocator, &.{ resolved.work_root, "asset_catalog.json" });
    defer allocator.free(inventory_path);
    const fixture_path = try std.fs.path.join(allocator, &.{ resolved.work_root, "fixture_manifest.json" });
    defer allocator.free(fixture_path);

    try ensureMatchingFile(stderr, "asset_catalog", "work/port/phase1/asset_catalog.json", inventory_path, inventory_json);
    try ensureMatchingFile(stderr, "fixture_manifest", "work/port/phase1/fixture_manifest.json", fixture_path, fixture_json_first);

    try diagnostics.printLine(stderr, &.{
        .{ .key = "status", .value = "ok" },
        .{ .key = "command", .value = "validate-phase1" },
    });
    try stderr.flush();
}

fn sameFixtureHashes(lhs: []const fixtures.FixtureManifestEntry, rhs: []const fixtures.FixtureManifestEntry) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |left, right| {
        if (!std.mem.eql(u8, left.sha256, right.sha256)) return false;
        if (!std.mem.eql(u8, left.output_path, right.output_path)) return false;
    }
    return true;
}

fn ensureMatchingFile(
    writer: anytype,
    output_id: []const u8,
    output_path: []const u8,
    absolute_path: []const u8,
    expected: []const u8,
) !void {
    const actual = std.Io.Dir.cwd().readFileAlloc(
        process.currentIo(),
        absolute_path,
        std.heap.page_allocator,
        .limited(32 * 1024 * 1024),
    ) catch |err| {
        if (err == error.FileNotFound) {
            try diagnostics.printLine(writer, &.{
                .{ .key = "status", .value = "error" },
                .{ .key = "command", .value = "validate-phase1" },
                .{ .key = "output_id", .value = output_id },
                .{ .key = "output_path", .value = output_path },
                .{ .key = "reason", .value = "missing_generated_output" },
            });
            try writer.flush();
            return error.MissingGeneratedOutput;
        }
        return err;
    };
    defer std.heap.page_allocator.free(actual);

    const normalized_actual = if (actual.len == expected.len + 1 and
        actual[actual.len - 1] == '\n' and
        std.mem.eql(u8, actual[0 .. actual.len - 1], expected))
        expected
    else
        actual;

    if (!std.mem.eql(u8, normalized_actual, expected)) {
        const first_diff = firstDiffIndex(normalized_actual, expected);
        var actual_len_buffer: [16]u8 = undefined;
        var expected_len_buffer: [16]u8 = undefined;
        var diff_index_buffer: [16]u8 = undefined;
        var actual_byte_buffer: [8]u8 = undefined;
        var expected_byte_buffer: [8]u8 = undefined;
        try diagnostics.printLine(writer, &.{
            .{ .key = "status", .value = "error" },
            .{ .key = "command", .value = "validate-phase1" },
            .{ .key = "output_id", .value = output_id },
            .{ .key = "output_path", .value = output_path },
            .{ .key = "reason", .value = "generated_output_drift" },
            .{ .key = "actual_bytes", .value = std.fmt.bufPrint(&actual_len_buffer, "{d}", .{normalized_actual.len}) catch unreachable },
            .{ .key = "expected_bytes", .value = std.fmt.bufPrint(&expected_len_buffer, "{d}", .{expected.len}) catch unreachable },
            .{ .key = "first_diff_index", .value = formatOptionalUsize(&diff_index_buffer, first_diff) },
            .{ .key = "actual_byte", .value = formatOptionalByteHex(&actual_byte_buffer, if (first_diff) |index| if (index < normalized_actual.len) normalized_actual[index] else null else null) },
            .{ .key = "expected_byte", .value = formatOptionalByteHex(&expected_byte_buffer, if (first_diff) |index| if (index < expected.len) expected[index] else null else null) },
        });
        try writer.flush();
        return error.GeneratedOutputDrift;
    }
}

fn firstDiffIndex(actual: []const u8, expected: []const u8) ?usize {
    const shared_len = @min(actual.len, expected.len);
    for (0..shared_len) |index| {
        if (actual[index] != expected[index]) return index;
    }
    return if (actual.len == expected.len) null else shared_len;
}

fn writeJson(path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try paths_mod.makePathAbsolute(parent);
    var file = try std.Io.Dir.createFileAbsolute(process.currentIo(), path, .{ .truncate = true });
    defer file.close(process.currentIo());
    try file.writeStreamingAll(process.currentIo(), bytes);
    try file.writeStreamingAll(process.currentIo(), "\n");
}

fn stringifyJsonAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try stringify.write(value);
    return allocator.dupe(u8, out.written());
}

const UnsupportedLifeSummaryEntry = struct {
    opcode_id: u8,
    mnemonic: []const u8,
    occurrence_count: usize,
};

const LifeAuditJsonFailure = struct {
    kind: []const u8,
    opcode_id: ?u8 = null,
    offset: ?usize = null,
};

const LifeAuditJsonUnsupported = struct {
    opcode_id: u8,
    mnemonic: []const u8,
    offset: usize,
};

const LifeAuditJsonSample = struct {
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    owner_kind: []const u8,
    object_index: ?usize,
    life_byte_length: usize,
    instruction_count: usize,
    decoded_byte_length: usize,
    status: []const u8,
    unsupported: ?LifeAuditJsonUnsupported,
    failure: ?LifeAuditJsonFailure,
};

const LifeProgramInspectionPayload = struct {
    command: []const u8,
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    scene_kind: []const u8,
    owner_kind: []const u8,
    object_index: ?usize,
    life_byte_length: usize,
    instruction_count: usize,
    decoded_byte_length: usize,
    status: []const u8,
    unsupported: ?LifeAuditJsonUnsupported,
    failure: ?LifeAuditJsonFailure,
};

const LifeCatalogOpcodeEntry = struct {
    id: u8,
    mnemonic: []const u8,
    supported: bool,
    operand_layout: []const u8,
    fixed_instruction_byte_length: ?usize,
    variable_length_reason: ?[]const u8,
    semantic_operand_kind: ?[]const u8,
};

const LifeCatalogFunctionEntry = struct {
    id: u8,
    mnemonic: []const u8,
    operand_layout: []const u8,
    return_type: []const u8,
    fixed_call_byte_length: usize,
};

const LifeCatalogComparatorEntry = struct {
    id: u8,
    mnemonic: []const u8,
};

const LifeCatalogReturnTypeEntry = struct {
    id: u8,
    mnemonic: []const u8,
    literal_layout: []const u8,
    fixed_literal_byte_length: ?usize,
    fixed_test_byte_length: ?usize,
    variable_length_reason: ?[]const u8,
};

const LifeCatalogPayload = struct {
    command: []const u8,
    schema_version: []const u8,
    opcode_count: usize,
    supported_opcode_count: usize,
    unsupported_opcode_count: usize,
    function_count: usize,
    comparator_count: usize,
    return_type_count: usize,
    opcodes: []const LifeCatalogOpcodeEntry,
    functions: []const LifeCatalogFunctionEntry,
    comparators: []const LifeCatalogComparatorEntry,
    return_types: []const LifeCatalogReturnTypeEntry,
};

fn buildUnsupportedLifeSummary(
    allocator: std.mem.Allocator,
    audits: []const life_audit.SceneLifeProgramAudit,
) ![]UnsupportedLifeSummaryEntry {
    var summary: std.ArrayList(UnsupportedLifeSummaryEntry) = .empty;
    errdefer summary.deinit(allocator);

    for (audits) |audit| {
        if (audit.status != .unsupported_opcode) continue;
        const unsupported = audit.status.unsupported_opcode;

        var found = false;
        for (summary.items) |*entry| {
            if (entry.opcode_id == unsupported.opcode_id) {
                entry.occurrence_count += 1;
                found = true;
                break;
            }
        }
        if (!found) {
            try summary.append(allocator, .{
                .opcode_id = unsupported.opcode_id,
                .mnemonic = unsupported.opcode.mnemonic(),
                .occurrence_count = 1,
            });
        }
    }

    std.mem.sort(UnsupportedLifeSummaryEntry, summary.items, {}, struct {
        fn lessThan(_: void, lhs: UnsupportedLifeSummaryEntry, rhs: UnsupportedLifeSummaryEntry) bool {
            return lhs.opcode_id < rhs.opcode_id;
        }
    }.lessThan);

    return summary.toOwnedSlice(allocator);
}

fn buildLifeAuditJsonSamples(
    allocator: std.mem.Allocator,
    audits: []const life_audit.SceneLifeProgramAudit,
) ![]LifeAuditJsonSample {
    var samples: std.ArrayList(LifeAuditJsonSample) = .empty;
    errdefer samples.deinit(allocator);

    for (audits) |audit| {
        try samples.append(allocator, buildLifeAuditJsonSample(audit));
    }

    return samples.toOwnedSlice(allocator);
}

fn buildLifeAuditJsonSample(audit: life_audit.SceneLifeProgramAudit) LifeAuditJsonSample {
    var unsupported: ?LifeAuditJsonUnsupported = null;
    var failure: ?LifeAuditJsonFailure = null;
    switch (audit.status) {
        .decoded => {},
        .unsupported_opcode => |hit| unsupported = .{
            .opcode_id = hit.opcode_id,
            .mnemonic = hit.opcode.mnemonic(),
            .offset = hit.offset,
        },
        .unknown_opcode => |hit| failure = .{
            .kind = lifeAuditStatusName(audit.status),
            .opcode_id = hit.opcode_id,
            .offset = hit.offset,
        },
        .truncated_operand,
        .malformed_string_operand,
        .missing_switch_context,
        .unknown_life_function,
        .unknown_life_comparator,
        => failure = .{ .kind = lifeAuditStatusName(audit.status) },
    }

    return .{
        .scene_entry_index = audit.scene_entry_index,
        .classic_loader_scene_number = audit.classic_loader_scene_number,
        .scene_kind = audit.scene_kind,
        .owner_kind = lifeOwnerKind(audit.owner),
        .object_index = lifeOwnerObjectIndex(audit.owner),
        .life_byte_length = audit.life_byte_length,
        .instruction_count = audit.instruction_count,
        .decoded_byte_length = audit.decoded_byte_length,
        .status = lifeAuditStatusName(audit.status),
        .unsupported = unsupported,
        .failure = failure,
    };
}

fn buildLifeProgramInspectionPayload(audit: life_audit.SceneLifeProgramAudit) LifeProgramInspectionPayload {
    const sample = buildLifeAuditJsonSample(audit);
    return .{
        .command = "inspect-life-program",
        .scene_entry_index = sample.scene_entry_index,
        .classic_loader_scene_number = sample.classic_loader_scene_number,
        .scene_kind = sample.scene_kind,
        .owner_kind = sample.owner_kind,
        .object_index = sample.object_index,
        .life_byte_length = sample.life_byte_length,
        .instruction_count = sample.instruction_count,
        .decoded_byte_length = sample.decoded_byte_length,
        .status = sample.status,
        .unsupported = sample.unsupported,
        .failure = sample.failure,
    };
}

fn buildLifeCatalogPayload(allocator: std.mem.Allocator) !LifeCatalogPayload {
    const life_catalog = try life_program.buildCatalog(allocator);
    defer life_catalog.deinit(allocator);

    var opcode_entries: std.ArrayList(LifeCatalogOpcodeEntry) = .empty;
    errdefer opcode_entries.deinit(allocator);
    var supported_opcode_count: usize = 0;
    for (life_catalog.opcodes) |entry| {
        if (entry.supported) supported_opcode_count += 1;
        try opcode_entries.append(allocator, .{
            .id = entry.id,
            .mnemonic = entry.mnemonic,
            .supported = entry.supported,
            .operand_layout = @tagName(entry.operand_layout),
            .fixed_instruction_byte_length = entry.fixed_instruction_byte_length,
            .variable_length_reason = if (entry.variable_length_reason) |reason| @tagName(reason) else null,
            .semantic_operand_kind = if (entry.semantic_operand_kind) |kind| @tagName(kind) else null,
        });
    }

    var function_entries: std.ArrayList(LifeCatalogFunctionEntry) = .empty;
    errdefer function_entries.deinit(allocator);
    for (life_catalog.functions) |entry| {
        try function_entries.append(allocator, .{
            .id = entry.id,
            .mnemonic = entry.mnemonic,
            .operand_layout = @tagName(entry.operand_layout),
            .return_type = entry.return_type.mnemonic(),
            .fixed_call_byte_length = entry.fixed_call_byte_length,
        });
    }

    var comparator_entries: std.ArrayList(LifeCatalogComparatorEntry) = .empty;
    errdefer comparator_entries.deinit(allocator);
    for (life_catalog.comparators) |entry| {
        try comparator_entries.append(allocator, .{
            .id = entry.id,
            .mnemonic = entry.mnemonic,
        });
    }

    var return_type_entries: std.ArrayList(LifeCatalogReturnTypeEntry) = .empty;
    errdefer return_type_entries.deinit(allocator);
    for (life_catalog.return_types) |entry| {
        try return_type_entries.append(allocator, .{
            .id = entry.id,
            .mnemonic = entry.mnemonic,
            .literal_layout = @tagName(entry.literal_layout),
            .fixed_literal_byte_length = entry.fixed_literal_byte_length,
            .fixed_test_byte_length = entry.fixed_test_byte_length,
            .variable_length_reason = if (entry.variable_length_reason) |reason| @tagName(reason) else null,
        });
    }

    return .{
        .command = "inspect-life-catalog",
        .schema_version = "life-catalog-v2",
        .opcode_count = opcode_entries.items.len,
        .supported_opcode_count = supported_opcode_count,
        .unsupported_opcode_count = opcode_entries.items.len - supported_opcode_count,
        .function_count = function_entries.items.len,
        .comparator_count = comparator_entries.items.len,
        .return_type_count = return_type_entries.items.len,
        .opcodes = try opcode_entries.toOwnedSlice(allocator),
        .functions = try function_entries.toOwnedSlice(allocator),
        .comparators = try comparator_entries.toOwnedSlice(allocator),
        .return_types = try return_type_entries.toOwnedSlice(allocator),
    };
}

fn lifeOwnerKind(owner: life_audit.LifeBlobOwner) []const u8 {
    return switch (owner) {
        .hero => "hero",
        .object => "object",
    };
}

fn lifeOwnerObjectIndex(owner: life_audit.LifeBlobOwner) ?usize {
    return switch (owner) {
        .hero => null,
        .object => |object_index| object_index,
    };
}

fn formatOptionalUsize(buffer: []u8, value: ?usize) []const u8 {
    if (value) |resolved| return std.fmt.bufPrint(buffer, "{d}", .{resolved}) catch unreachable;
    return "none";
}

fn formatOptionalI32(buffer: []u8, value: ?i32) []const u8 {
    if (value) |resolved| return std.fmt.bufPrint(buffer, "{d}", .{resolved}) catch unreachable;
    return "none";
}

fn formatOptionalI16(buffer: []u8, value: ?i16) []const u8 {
    if (value) |resolved| return std.fmt.bufPrint(buffer, "{d}", .{resolved}) catch unreachable;
    return "none";
}

fn formatOptionalString(buffer: []u8, value: ?[]const u8) []const u8 {
    _ = buffer;
    return value orelse "none";
}

fn formatOptionalByteHex(buffer: []u8, value: ?u8) []const u8 {
    if (value) |resolved| return std.fmt.bufPrint(buffer, "0x{X:0>2}", .{resolved}) catch unreachable;
    return "none";
}

fn inspectLifeCatalog(allocator: std.mem.Allocator, output_json: bool) !void {
    const payload = try buildLifeCatalogPayload(allocator);
    defer allocator.free(payload.opcodes);
    defer allocator.free(payload.functions);
    defer allocator.free(payload.comparators);
    defer allocator.free(payload.return_types);

    if (output_json) {
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), json);
        try std.Io.File.stdout().writeStreamingAll(process.currentIo(), "\n");
        return;
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(process.currentIo(), &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "command={s} schema_version={s} opcode_count={d} supported_opcode_count={d} unsupported_opcode_count={d} function_count={d} comparator_count={d} return_type_count={d}\n",
        .{
            payload.command,
            payload.schema_version,
            payload.opcode_count,
            payload.supported_opcode_count,
            payload.unsupported_opcode_count,
            payload.function_count,
            payload.comparator_count,
            payload.return_type_count,
        },
    );
    try stdout.writeAll("use --json for the full machine-readable catalog\n");
    try stdout.flush();
}

fn formatOptionalFragmentDimensions(
    buffer: []u8,
    value: ?room_state.FragmentDimensionsSnapshot,
) []const u8 {
    if (value) |resolved| {
        return std.fmt.bufPrint(buffer, "{d}x{d}x{d}", .{
            resolved.width,
            resolved.height,
            resolved.depth,
        }) catch unreachable;
    }
    return "none";
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

test "argument parsing handles asset root override and json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "--asset-root", "D:/assets", "inspect-hqr", "SCENE.HQR", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_hqr, parsed.command);
    try std.testing.expectEqualStrings("SCENE.HQR", parsed.relative_path.?);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports inspect-scene json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "inspect-scene", "2", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_scene, parsed.command);
    try std.testing.expectEqual(@as(usize, 2), parsed.entry_index.?);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports inspect-background json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "inspect-background", "2", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_background, parsed.command);
    try std.testing.expectEqual(@as(usize, 2), parsed.entry_index.?);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports inspect-room json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "inspect-room", "2", "2", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_room, parsed.command);
    try std.testing.expectEqual(@as(usize, 2), parsed.entry_index.?);
    try std.testing.expectEqual(@as(usize, 2), parsed.background_entry_index.?);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports inspect-room-transitions json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "inspect-room-transitions", "3", "3", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_room_transitions, parsed.command);
    try std.testing.expectEqual(@as(usize, 3), parsed.entry_index.?);
    try std.testing.expectEqual(@as(usize, 3), parsed.background_entry_index.?);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports inspect-room-intelligence entry selectors" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "inspect-room-intelligence", "--scene-entry", "2", "--background-entry", "2" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_room_intelligence, parsed.command);
    try std.testing.expectEqual(@as(usize, 2), parsed.entry_index.?);
    try std.testing.expectEqual(@as(usize, 2), parsed.background_entry_index.?);
    try std.testing.expect(parsed.scene_name == null);
    try std.testing.expect(parsed.background_name == null);
}

test "argument parsing supports inspect-room-intelligence name selectors" {
    const parsed = try parseArgs(
        std.testing.allocator,
        &.{
            "inspect-room-intelligence",
            "--scene-name",
            "Scene 0: Citadel Island, Twinsen's house",
            "--background-name",
            "Grid 0: Citadel Island, Twinsen's house",
        },
    );
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_room_intelligence, parsed.command);
    try std.testing.expect(parsed.entry_index == null);
    try std.testing.expect(parsed.background_entry_index == null);
    try std.testing.expectEqualStrings("Scene 0: Citadel Island, Twinsen's house", parsed.scene_name.?);
    try std.testing.expectEqualStrings("Grid 0: Citadel Island, Twinsen's house", parsed.background_name.?);
}

test "argument parsing supports inspect-room-intelligence output files" {
    const parsed = try parseArgs(
        std.testing.allocator,
        &.{
            "inspect-room-intelligence",
            "--scene-entry",
            "2",
            "--background-entry",
            "2",
            "--out",
            "room.json",
        },
    );
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_room_intelligence, parsed.command);
    try std.testing.expectEqualStrings("room.json", parsed.output_path.?);
}

test "argument parsing rejects inspect-room-intelligence conflicting selectors" {
    try std.testing.expectError(
        error.ConflictingSceneSelector,
        parseArgs(std.testing.allocator, &.{ "inspect-room-intelligence", "--scene-entry", "2", "--scene-name", "Twinsen's house", "--background-entry", "2" }),
    );
    try std.testing.expectError(
        error.ConflictingBackgroundSelector,
        parseArgs(std.testing.allocator, &.{ "inspect-room-intelligence", "--scene-entry", "2", "--background-entry", "2", "--background-name", "Twinsen's house" }),
    );
}

test "argument parsing rejects inspect-room-intelligence missing selectors" {
    try std.testing.expectError(
        error.MissingSceneSelector,
        parseArgs(std.testing.allocator, &.{ "inspect-room-intelligence", "--background-entry", "2" }),
    );
    try std.testing.expectError(
        error.MissingBackgroundSelector,
        parseArgs(std.testing.allocator, &.{ "inspect-room-intelligence", "--scene-entry", "2" }),
    );
    try std.testing.expectError(
        error.MissingOutputPath,
        parseArgs(std.testing.allocator, &.{ "inspect-room-intelligence", "--scene-entry", "2", "--background-entry", "2", "--out" }),
    );
    try std.testing.expectError(
        error.DuplicateOutputPath,
        parseArgs(std.testing.allocator, &.{ "inspect-room-intelligence", "--scene-entry", "2", "--background-entry", "2", "--out", "a.json", "--out", "b.json" }),
    );
    try std.testing.expectError(
        error.UnknownOption,
        parseArgs(std.testing.allocator, &.{ "inspect-room-intelligence", "--scene-entry", "2", "--background-entry", "2", "--json" }),
    );
}

test "argument parsing supports inspect-room-fragment-zones json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "inspect-room-fragment-zones", "219", "219", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_room_fragment_zones, parsed.command);
    try std.testing.expectEqual(@as(usize, 219), parsed.entry_index.?);
    try std.testing.expectEqual(@as(usize, 219), parsed.background_entry_index.?);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports audit-life-programs json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "audit-life-programs", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.audit_life_programs, parsed.command);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports rank-decoded-interior-candidates json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "rank-decoded-interior-candidates", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.rank_decoded_interior_candidates, parsed.command);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports triage-same-index-decoded-interior-candidates json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "triage-same-index-decoded-interior-candidates", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.triage_same_index_decoded_interior_candidates, parsed.command);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports inspect-life-catalog json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "inspect-life-catalog", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_life_catalog, parsed.command);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports inspect-life-program hero selection by default" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "inspect-life-program", "--scene-entry", "2", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_life_program, parsed.command);
    try std.testing.expectEqual(@as(usize, 2), parsed.entry_index.?);
    try std.testing.expect(parsed.life_program_owner.? == .hero);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing supports inspect-life-program object selection" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "inspect-life-program", "--object-index", "5", "--scene-entry", "2" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.inspect_life_program, parsed.command);
    try std.testing.expectEqual(@as(usize, 2), parsed.entry_index.?);
    try std.testing.expectEqual(@as(usize, 5), parsed.life_program_owner.?.object);
}

test "argument parsing supports explicit audit-life-program scene selection" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "audit-life-programs", "--scene-entry", "2", "--scene-entry", "44" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.audit_life_programs, parsed.command);
    try std.testing.expect(!parsed.audit_all_scene_entries);
    try std.testing.expectEqualSlices(usize, &.{ 2, 44 }, parsed.audit_scene_entry_indices.?);
}

test "argument parsing supports all-scene-entry audit-life-program selection" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "audit-life-programs", "--all-scene-entries", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.audit_life_programs, parsed.command);
    try std.testing.expect(parsed.audit_all_scene_entries);
    try std.testing.expect(parsed.audit_scene_entry_indices == null);
    try std.testing.expect(parsed.output_json);
}

test "argument parsing rejects duplicate audit-life-program scene entries" {
    try std.testing.expectError(
        error.DuplicateSceneEntryIndex,
        parseArgs(std.testing.allocator, &.{ "audit-life-programs", "--scene-entry", "44", "--scene-entry", "44" }),
    );
}

test "argument parsing rejects mixed audit-life-program selection flags" {
    try std.testing.expectError(
        error.ConflictingAuditSceneSelection,
        parseArgs(std.testing.allocator, &.{ "audit-life-programs", "--all-scene-entries", "--scene-entry", "44" }),
    );
}

test "argument parsing rejects inspect-life-program duplicate selectors" {
    try std.testing.expectError(
        error.DuplicateSceneEntrySelector,
        parseArgs(std.testing.allocator, &.{ "inspect-life-program", "--scene-entry", "2", "--scene-entry", "44" }),
    );
    try std.testing.expectError(
        error.DuplicateObjectIndexSelector,
        parseArgs(std.testing.allocator, &.{ "inspect-life-program", "--scene-entry", "2", "--object-index", "2", "--object-index", "3" }),
    );
}

test "inspect-life-catalog payload pins structural mappings" {
    const allocator = std.testing.allocator;
    const payload = try buildLifeCatalogPayload(allocator);
    defer allocator.free(payload.opcodes);
    defer allocator.free(payload.functions);
    defer allocator.free(payload.comparators);
    defer allocator.free(payload.return_types);

    try std.testing.expectEqualStrings("inspect-life-catalog", payload.command);
    try std.testing.expectEqualStrings("life-catalog-v2", payload.schema_version);
    try std.testing.expectEqual(@as(usize, 150), payload.opcode_count);
    try std.testing.expectEqual(@as(usize, 144), payload.supported_opcode_count);
    try std.testing.expectEqual(@as(usize, 6), payload.unsupported_opcode_count);
    try std.testing.expectEqual(@as(usize, 46), payload.function_count);
    try std.testing.expectEqual(@as(usize, 6), payload.comparator_count);
    try std.testing.expectEqual(@as(usize, 4), payload.return_type_count);

    var found_default = false;
    var found_set_dir = false;
    var found_init_buggy = false;
    for (payload.opcodes) |entry| {
        if (entry.id == @intFromEnum(life_program.LifeOpcode.LM_DEFAULT)) {
            found_default = true;
            try std.testing.expect(entry.supported);
            try std.testing.expectEqualStrings("none", entry.operand_layout);
            try std.testing.expectEqual(@as(?usize, 1), entry.fixed_instruction_byte_length);
            try std.testing.expect(entry.variable_length_reason == null);
            try std.testing.expect(entry.semantic_operand_kind == null);
        }
        if (entry.id == @intFromEnum(life_program.LifeOpcode.LM_SET_DIR)) {
            found_set_dir = true;
            try std.testing.expectEqualStrings("move", entry.operand_layout);
            try std.testing.expectEqual(@as(?usize, null), entry.fixed_instruction_byte_length);
            try std.testing.expectEqualStrings("move_mode", entry.variable_length_reason.?);
            try std.testing.expectEqualStrings("move_mode", entry.semantic_operand_kind.?);
        }
        if (entry.id == @intFromEnum(life_program.LifeOpcode.LM_COMPORTEMENT_HERO)) {
            try std.testing.expectEqualStrings("hero_behaviour", entry.semantic_operand_kind.?);
        }
        if (entry.id == @intFromEnum(life_program.LifeOpcode.LM_INIT_BUGGY)) {
            found_init_buggy = true;
            try std.testing.expectEqualStrings("u8", entry.operand_layout);
            try std.testing.expectEqual(@as(?usize, 2), entry.fixed_instruction_byte_length);
            try std.testing.expect(entry.variable_length_reason == null);
            try std.testing.expectEqualStrings("buggy_init", entry.semantic_operand_kind.?);
        }
    }
    try std.testing.expect(found_default);
    try std.testing.expect(found_set_dir);
    try std.testing.expect(found_init_buggy);

    var found_var_game = false;
    for (payload.functions) |entry| {
        if (entry.id == @intFromEnum(life_program.LifeFunction.LF_VAR_GAME)) {
            found_var_game = true;
            try std.testing.expectEqualStrings("u8", entry.operand_layout);
            try std.testing.expectEqualStrings("RET_S16", entry.return_type);
            try std.testing.expectEqual(@as(usize, 2), entry.fixed_call_byte_length);
        }
    }
    try std.testing.expect(found_var_game);

    var found_ret_string = false;
    for (payload.return_types) |entry| {
        if (entry.id == @intFromEnum(life_program.LifeReturnType.RET_STRING)) {
            found_ret_string = true;
            try std.testing.expectEqualStrings("string", entry.literal_layout);
            try std.testing.expectEqual(@as(?usize, null), entry.fixed_literal_byte_length);
            try std.testing.expectEqual(@as(?usize, null), entry.fixed_test_byte_length);
            try std.testing.expectEqualStrings("null_terminated_string", entry.variable_length_reason.?);
        }
    }
    try std.testing.expect(found_ret_string);
}

test "ranked decoded interior candidate payload makes the scene 19 comparison explicit" {
    const allocator = std.testing.allocator;
    const payload = try buildRankedDecodedInteriorCandidatesPayload(allocator, &.{
        .{
            .scene_entry_index = 88,
            .classic_loader_scene_number = 86,
            .scene_kind = "interior",
            .blob_count = 4,
            .object_count = 9,
            .zone_count = 6,
            .track_count = 31,
            .patch_count = 2,
        },
        .{
            .scene_entry_index = 19,
            .classic_loader_scene_number = 17,
            .scene_kind = "interior",
            .blob_count = 3,
            .object_count = 3,
            .zone_count = 4,
            .track_count = 0,
            .patch_count = 5,
        },
    });
    defer allocator.free(payload.candidates);

    try std.testing.expectEqualStrings("rank-decoded-interior-candidates", payload.command);
    try std.testing.expectEqual(@as(usize, 5), payload.ranking_basis.len);
    try std.testing.expectEqualStrings("track_count_desc", payload.ranking_basis[0]);
    try std.testing.expectEqual(@as(usize, 2), payload.candidate_count);
    try std.testing.expectEqual(@as(usize, 19), payload.current_supported_baseline_scene_entry_index);
    try std.testing.expectEqual(@as(usize, 2), payload.current_supported_baseline_rank);
    try std.testing.expectEqual(false, payload.current_supported_baseline_is_top_candidate);
    try std.testing.expectEqual(@as(usize, 88), payload.top_candidate.scene_entry_index);
    try std.testing.expectEqual(@as(usize, 2), payload.top_candidate.patch_count);
    try std.testing.expectEqual(@as(usize, 19), payload.current_supported_baseline.scene_entry_index);
    try std.testing.expectEqual(@as(usize, 5), payload.current_supported_baseline.patch_count);
    try std.testing.expectEqual(true, payload.current_supported_baseline.is_current_supported_baseline);
}

fn testFragmentZoneAxisDiagnostic(
    unit: i32,
    origin_alignment_required: bool,
    origin_aligned: ?bool,
    origin_remainder: ?i32,
    cell_count: ?usize,
) room_state.FragmentZoneAxisDiagnostic {
    return .{
        .min_value = 0,
        .max_value = unit - 1,
        .unit = unit,
        .origin_alignment_required = origin_alignment_required,
        .origin_aligned = origin_aligned,
        .origin_remainder = origin_remainder,
        .origin_cell = if (origin_aligned == null) null else 0,
        .origin_floor_value = null,
        .origin_floor_cell = null,
        .origin_floor_delta = null,
        .origin_ceil_value = null,
        .origin_ceil_cell = null,
        .origin_ceil_delta = null,
        .span_non_negative = true,
        .span_aligned = true,
        .span_remainder = 0,
        .cell_count = cell_count,
    };
}

fn testCompatibleFragmentZoneAxisDiagnostic(unit: i32, origin_alignment_required: bool, cell_count: usize) room_state.FragmentZoneAxisDiagnostic {
    return testFragmentZoneAxisDiagnostic(unit, origin_alignment_required, true, 0, cell_count);
}

fn testFragmentZoneDiagnostic(
    issue: room_state.FragmentZoneCompatibilityIssue,
    zone_index: usize,
    zone_num: i16,
    grm_index: i32,
    fragment_entry_index: ?usize,
) room_state.FragmentZoneCompatibilityDiagnostic {
    return .{
        .zone_index = zone_index,
        .zone_num = zone_num,
        .grm_index = grm_index,
        .initially_on = false,
        .x_axis = testCompatibleFragmentZoneAxisDiagnostic(512, true, 1),
        .y_axis = testCompatibleFragmentZoneAxisDiagnostic(256, false, 1),
        .z_axis = switch (issue) {
            .invalid_z_axis_origin => testFragmentZoneAxisDiagnostic(512, true, false, 112, 1),
            .invalid_z_axis_span => .{
                .min_value = 0,
                .max_value = 510,
                .unit = 512,
                .origin_alignment_required = true,
                .origin_aligned = true,
                .origin_remainder = 0,
                .origin_cell = 0,
                .origin_floor_value = null,
                .origin_floor_cell = null,
                .origin_floor_delta = null,
                .origin_ceil_value = null,
                .origin_ceil_cell = null,
                .origin_ceil_delta = null,
                .span_non_negative = true,
                .span_aligned = false,
                .span_remainder = 511,
                .cell_count = null,
            },
            else => testCompatibleFragmentZoneAxisDiagnostic(512, true, 1),
        },
        .fragment_entry_index = fragment_entry_index,
        .fragment_dimensions = if (fragment_entry_index != null) .{ .width = 1, .height = 1, .depth = 1 } else null,
        .issue = issue,
    };
}

fn testRankedDecodedInteriorSceneCandidate(
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    blob_count: usize,
    object_count: usize,
    zone_count: usize,
    track_count: usize,
    patch_count: usize,
) life_audit.RankedDecodedInteriorSceneCandidate {
    return .{
        .scene_entry_index = scene_entry_index,
        .classic_loader_scene_number = classic_loader_scene_number,
        .scene_kind = "interior",
        .blob_count = blob_count,
        .object_count = object_count,
        .zone_count = zone_count,
        .track_count = track_count,
        .patch_count = patch_count,
    };
}

fn testRoomFragmentZoneDiagnostics(
    scene_entry_index: usize,
    classic_loader_scene_number: ?usize,
    fragment_count: usize,
    grm_zone_count: usize,
    compatible_zone_count: usize,
    invalid_zone_count: usize,
    first_invalid_zone_index: ?usize,
    zones: []const room_state.FragmentZoneCompatibilityDiagnostic,
) room_state.RoomFragmentZoneDiagnostics {
    return .{
        .scene_entry_index = scene_entry_index,
        .background_entry_index = scene_entry_index,
        .classic_loader_scene_number = classic_loader_scene_number,
        .scene_kind = "interior",
        .fragment_count = fragment_count,
        .grm_zone_count = grm_zone_count,
        .compatible_zone_count = compatible_zone_count,
        .invalid_zone_count = invalid_zone_count,
        .first_invalid_zone_index = first_invalid_zone_index,
        .zones = @constCast(zones),
    };
}

fn buildSyntheticSameIndexDecodedInteriorCandidateTriagePayload(
    allocator: std.mem.Allocator,
) !SameIndexDecodedInteriorCandidateTriagePayload {
    const blocked_top_zones = [_]room_state.FragmentZoneCompatibilityDiagnostic{
        testFragmentZoneDiagnostic(.invalid_z_axis_origin, 1, 0, 0, 159),
    };
    const compatible_zones = [_]room_state.FragmentZoneCompatibilityDiagnostic{};

    const summaries = [_]SameIndexDecodedInteriorCandidateTriageSummary{
        buildSameIndexDecodedInteriorCandidateTriageSummary(
            1,
            testRankedDecodedInteriorSceneCandidate(219, 217, 45, 45, 23, 61, 94),
            testRoomFragmentZoneDiagnostics(219, 217, 3, 6, 0, 6, 1, blocked_top_zones[0..]),
            19,
        ),
        buildSameIndexDecodedInteriorCandidateTriageSummary(
            2,
            testRankedDecodedInteriorSceneCandidate(86, 84, 20, 10, 4, 12, 3),
            testRoomFragmentZoneDiagnostics(86, 84, 0, 0, 0, 0, null, compatible_zones[0..]),
            19,
        ),
        buildSameIndexDecodedInteriorCandidateTriageSummary(
            3,
            testRankedDecodedInteriorSceneCandidate(187, 185, 18, 8, 2, 4, 1),
            testRoomFragmentZoneDiagnostics(187, 185, 2, 2, 2, 0, null, compatible_zones[0..]),
            19,
        ),
        buildSameIndexDecodedInteriorCandidateTriageSummary(
            4,
            testRankedDecodedInteriorSceneCandidate(19, 17, 3, 3, 4, 0, 5),
            testRoomFragmentZoneDiagnostics(19, 17, 0, 0, 0, 0, null, compatible_zones[0..]),
            19,
        ),
    };

    return buildSameIndexDecodedInteriorCandidateTriagePayloadFromSummaries(allocator, 19, summaries[0..]);
}

test "same-index decoded interior triage payload pins the current baseline comparison" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticSameIndexDecodedInteriorCandidateTriagePayload(allocator);
    defer allocator.free(payload.candidates);

    try std.testing.expectEqualStrings("triage-same-index-decoded-interior-candidates", payload.command);
    try std.testing.expectEqual(@as(usize, 5), payload.ranking_basis.len);
    try std.testing.expectEqualStrings("track_count_desc", payload.ranking_basis[0]);
    try std.testing.expectEqual(@as(usize, 4), payload.candidate_count);
    try std.testing.expectEqual(@as(usize, 3), payload.compatible_candidate_count);
    try std.testing.expectEqual(@as(usize, 2), payload.compatible_candidate_count_above_baseline);
    try std.testing.expectEqual(@as(usize, 19), payload.current_supported_baseline_scene_entry_index);
    try std.testing.expectEqual(@as(usize, 4), payload.current_supported_baseline_rank);
    try std.testing.expectEqual(@as(usize, 19), payload.current_supported_baseline.scene_entry_index);
    try std.testing.expectEqual(true, payload.current_supported_baseline.compatible);
    try std.testing.expectEqual(@as(usize, 0), payload.current_supported_baseline.fragment_count);
    try std.testing.expectEqual(@as(usize, 0), payload.current_supported_baseline.grm_zone_count);

    const highest = payload.highest_ranked_compatible_candidate orelse return error.MissingHighestCompatibleCandidate;
    try std.testing.expectEqual(@as(usize, 2), highest.rank);
    try std.testing.expectEqual(@as(usize, 86), highest.scene_entry_index);
    try std.testing.expectEqual(@as(?usize, 84), highest.classic_loader_scene_number);
    try std.testing.expectEqual(true, highest.compatible);
    try std.testing.expectEqual(@as(usize, 0), highest.fragment_count);
    try std.testing.expectEqual(@as(usize, 0), highest.grm_zone_count);

    const highest_above_baseline = payload.highest_ranked_compatible_candidate_above_baseline orelse return error.MissingHighestCompatibleCandidateAboveBaseline;
    try std.testing.expectEqual(@as(usize, 2), highest_above_baseline.rank);
    try std.testing.expectEqual(@as(usize, 86), highest_above_baseline.scene_entry_index);
    try std.testing.expectEqual(true, payload.highest_ranked_compatible_candidate_outranks_current_supported_baseline);

    const highest_fragment_bearing = payload.highest_ranked_fragment_bearing_compatible_candidate orelse return error.MissingHighestFragmentBearingCompatibleCandidate;
    try std.testing.expectEqual(@as(usize, 3), highest_fragment_bearing.rank);
    try std.testing.expectEqual(@as(usize, 187), highest_fragment_bearing.scene_entry_index);
    try std.testing.expectEqual(true, highest_fragment_bearing.compatible);
    try std.testing.expectEqual(@as(usize, 2), highest_fragment_bearing.fragment_count);
    try std.testing.expectEqual(@as(usize, 2), highest_fragment_bearing.grm_zone_count);
    try std.testing.expectEqual(@as(usize, 2), highest_fragment_bearing.compatible_zone_count);

    const highest_fragment_bearing_above_baseline = payload.highest_ranked_fragment_bearing_compatible_candidate_above_baseline orelse return error.MissingHighestFragmentBearingCompatibleCandidateAboveBaseline;
    try std.testing.expectEqual(@as(usize, 3), highest_fragment_bearing_above_baseline.rank);
    try std.testing.expectEqual(@as(usize, 187), highest_fragment_bearing_above_baseline.scene_entry_index);
    try std.testing.expectEqual(true, payload.highest_ranked_fragment_bearing_compatible_candidate_outranks_current_supported_baseline);

    const blocked_top = payload.candidates[0];
    try std.testing.expectEqual(@as(usize, 219), blocked_top.scene_entry_index);
    try std.testing.expectEqual(false, blocked_top.compatible);
    try std.testing.expectEqual(@as(usize, 3), blocked_top.fragment_count);
    try std.testing.expectEqual(@as(usize, 6), blocked_top.grm_zone_count);
    try std.testing.expectEqual(@as(usize, 6), blocked_top.invalid_zone_count);
    try std.testing.expectEqual(@as(?usize, 1), blocked_top.first_invalid_zone_index);
    try std.testing.expectEqualStrings("invalid_z_axis_origin", blocked_top.first_invalid_issue.?);
    try std.testing.expectEqualStrings("z", blocked_top.first_invalid_axis.?);
    try std.testing.expectEqualStrings("misaligned_min", blocked_top.first_invalid_failure_reason.?);
    try std.testing.expectEqual(@as(?i16, 0), blocked_top.first_invalid_zone_num);
    try std.testing.expectEqual(@as(?i32, 0), blocked_top.first_invalid_grm_index);
    try std.testing.expectEqual(@as(?usize, 159), blocked_top.first_invalid_fragment_entry_index);

    const first_fragment_bearing_compatible = payload.candidates[2];
    try std.testing.expectEqual(@as(usize, 187), first_fragment_bearing_compatible.scene_entry_index);
    try std.testing.expectEqual(true, first_fragment_bearing_compatible.compatible);
    try std.testing.expectEqual(@as(usize, 2), first_fragment_bearing_compatible.fragment_count);
    try std.testing.expectEqual(@as(usize, 2), first_fragment_bearing_compatible.grm_zone_count);
    try std.testing.expectEqual(@as(usize, 2), first_fragment_bearing_compatible.compatible_zone_count);
}

test "same-index decoded interior triage text output surfaces the fragment-bearing summary" {
    const allocator = std.testing.allocator;
    const payload = try buildSyntheticSameIndexDecodedInteriorCandidateTriagePayload(allocator);
    defer allocator.free(payload.candidates);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try printSameIndexDecodedInteriorCandidateTriagePayload(&output.writer, payload);

    try std.testing.expect(std.mem.indexOf(u8, output.written(), "highest_ranked_compatible_candidate rank=2 scene_entry_index=86") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "highest_ranked_fragment_bearing_compatible_candidate rank=3 scene_entry_index=187") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "highest_ranked_fragment_bearing_compatible_candidate_above_baseline rank=3 scene_entry_index=187") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "highest_ranked_fragment_bearing_compatible_candidate_outranks_current_supported_baseline=true") != null);
}

test "inspect-room composes the guarded canonical interior pair metadata" {
    const room = try room_fixtures.guarded1919();

    const payload = buildRoomInspectionPayload(room);
    try std.testing.expectEqualStrings("inspect-room", payload.command);
    try std.testing.expectEqual(@as(usize, 19), payload.scene.entry_index);
    try std.testing.expectEqual(@as(?usize, 17), payload.scene.classic_loader_scene_number);
    try std.testing.expectEqualStrings("interior", payload.scene.scene_kind);
    try std.testing.expectEqual(@as(i16, 1987), payload.scene.hero_start.x);
    try std.testing.expectEqual(@as(i16, 512), payload.scene.hero_start.y);
    try std.testing.expectEqual(@as(i16, 3743), payload.scene.hero_start.z);
    try std.testing.expectEqual(@as(u16, 22), payload.scene.hero_start.track_byte_length);
    try std.testing.expectEqual(@as(u16, 38), payload.scene.hero_start.life_byte_length);
    try std.testing.expectEqual(@as(usize, 3), payload.scene.object_count);
    try std.testing.expectEqual(@as(usize, 4), payload.scene.zone_count);
    try std.testing.expectEqual(@as(usize, 0), payload.scene.track_count);
    try std.testing.expectEqual(@as(usize, 5), payload.scene.patch_count);

    try std.testing.expectEqual(@as(usize, 19), payload.background.entry_index);
    try std.testing.expectEqual(@as(usize, 19), payload.background.linkage.remapped_cube_index);
    try std.testing.expectEqual(@as(usize, 20), payload.background.linkage.gri_entry_index);
    try std.testing.expectEqual(@as(u8, 2), payload.background.linkage.gri_my_grm);
    try std.testing.expectEqual(@as(usize, 151), payload.background.linkage.grm_entry_index);
    try std.testing.expectEqual(@as(u8, 1), payload.background.linkage.gri_my_bll);
    try std.testing.expectEqual(@as(usize, 180), payload.background.linkage.bll_entry_index);
    try std.testing.expectEqual(@as(usize, 73), payload.background.used_blocks.count);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 7 }, payload.background.used_blocks.values[0..6]);
    try std.testing.expectEqual(@as(usize, 64), payload.background.column_table.width);
    try std.testing.expectEqual(@as(usize, 64), payload.background.column_table.depth);
    try std.testing.expectEqual(@as(usize, 4096), payload.background.column_table.offset_count);
    try std.testing.expectEqual(@as(usize, 8192), payload.background.column_table.table_byte_length);
    try std.testing.expect(payload.background.column_table.data_byte_length > 0);
    try std.testing.expectEqual(@as(usize, 1246), payload.background.composition.occupied_cell_count);
    try std.testing.expectEqual(@as(?background_data.GridBounds, .{
        .min_x = 39,
        .max_x = 63,
        .min_z = 6,
        .max_z = 58,
    }), payload.background.composition.occupied_bounds);
    try std.testing.expectEqual(@as(usize, 219), payload.background.composition.layout_count);
    try std.testing.expectEqual(@as(usize, 45), payload.background.composition.max_layout_block_count);
    try std.testing.expectEqual(@as(usize, 0), payload.background.fragments.fragment_count);
    try std.testing.expectEqual(@as(usize, 0), payload.background.fragments.footprint_cell_count);
    try std.testing.expectEqual(@as(usize, 0), payload.background.fragments.non_empty_cell_count);
    try std.testing.expectEqual(@as(u8, 0), payload.background.fragments.max_height);
}

test "inspect-room json keeps the guarded canonical interior pair stable" {
    const allocator = std.testing.allocator;
    const room = try room_fixtures.guarded1919();

    const json = try stringifyJsonAlloc(allocator, buildRoomInspectionPayload(room));
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"command\": \"inspect-room\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"scene_kind\": \"interior\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"classic_loader_scene_number\": 17") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"remapped_cube_index\": 19") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"gri_entry_index\": 20") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"grm_entry_index\": 151") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bll_entry_index\": 180") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"count\": 73") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"width\": 64") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"depth\": 64") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"occupied_cell_count\": 1246") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fragment_count\": 0") != null);
}

test "inspect-room-transitions payload exposes guarded 3/3 interior commits" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const payload = try buildRoomTransitionInspectionPayload(allocator, resolved, 3, 3);
    defer allocator.free(payload.transitions);

    try std.testing.expectEqualStrings("inspect-room-transitions", payload.command);
    try std.testing.expectEqual(@as(usize, 3), payload.source_scene_entry_index);
    try std.testing.expectEqual(@as(usize, 3), payload.source_background_entry_index);
    try std.testing.expect(payload.transition_count >= 2);

    var found_zone_1 = false;
    for (payload.transitions) |transition| {
        if (transition.source_zone_index != 1) continue;
        found_zone_1 = true;
        try std.testing.expectEqual(@as(i16, 19), transition.destination_cube);
        try std.testing.expectEqualStrings("committed", transition.result);
        try std.testing.expect(transition.rejection_reason == null);
        try std.testing.expectEqual(@as(?usize, 21), transition.destination_scene_entry_index);
        try std.testing.expectEqual(@as(?usize, 19), transition.destination_background_entry_index);
        try std.testing.expect(transition.post_load_diagnostics == null);
        try std.testing.expectEqual(transition.destination_world_position, transition.hero_position);
    }
    try std.testing.expect(found_zone_1);
}

test "inspect-room-transitions payload exposes guarded 187/187 no-readjust destination blocker" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const payload = try buildRoomTransitionInspectionPayload(allocator, resolved, 187, 187);
    defer allocator.free(payload.transitions);

    try std.testing.expectEqual(@as(usize, 1), payload.transition_count);
    const transition = payload.transitions[0];
    try std.testing.expectEqualStrings("decoded_change_cube", transition.source_kind);
    try std.testing.expectEqual(@as(usize, 1), transition.source_zone_index);
    try std.testing.expectEqual(@as(i16, 185), transition.destination_cube);
    try std.testing.expectEqual(true, transition.dont_readjust_twinsen);
    try std.testing.expectEqualStrings("rejected", transition.result);
    try std.testing.expectEqualStrings("unsupported_destination_height_mismatch", transition.rejection_reason.?);
    try std.testing.expectEqual(@as(?usize, 187), transition.destination_scene_entry_index);
    try std.testing.expectEqual(@as(?usize, 187), transition.destination_background_entry_index);
    try std.testing.expectEqual(RoomTransitionWorldPositionSummary{
        .x = 2656,
        .y = 1792,
        .z = 3141,
    }, transition.hero_position);
    const post_load = transition.post_load_diagnostics orelse return error.MissingPostLoadDiagnostics;
    try std.testing.expectEqualStrings("target_height_mismatch", post_load.move_target_status);
    try std.testing.expect(post_load.shadow_adjustment_failure == null);
    try std.testing.expectEqual(RoomTransitionWorldPositionSummary{
        .x = 13824,
        .y = 5120,
        .z = 14848,
    }, post_load.provisional_world_position);
    try std.testing.expectEqualStrings("occupied_surface", post_load.raw_cell.status);
    try std.testing.expectEqual(true, post_load.raw_cell.occupied);
    try std.testing.expectEqual(@as(?RoomTransitionGridCellSummary, .{ .x = 27, .z = 29 }), post_load.raw_cell.cell);
    try std.testing.expectEqual(@as(?i32, 2048), post_load.raw_cell.surface_top_y);
    try std.testing.expectEqual(@as(?u8, 8), post_load.raw_cell.surface_total_height);
    try std.testing.expectEqual(@as(?u8, 1), post_load.raw_cell.surface_stack_depth);
    try std.testing.expectEqual(@as(?u8, 0), post_load.raw_cell.surface_floor_type);
    try std.testing.expectEqualStrings("solid", post_load.raw_cell.surface_shape_class.?);
    try std.testing.expectEqualStrings("within_occupied_bounds", post_load.occupied_coverage.relation);
    const nearest_standable = post_load.nearest_standable orelse return error.MissingNearestStandable;
    try std.testing.expectEqual(RoomTransitionGridCellSummary{ .x = 27, .z = 29 }, nearest_standable.cell);
    try std.testing.expectEqual(@as(i32, 6400), nearest_standable.surface_top_y);
    try std.testing.expectEqual(@as(u8, 25), nearest_standable.surface_total_height);
    try std.testing.expectEqual(@as(u8, 1), nearest_standable.surface_stack_depth);
    try std.testing.expectEqual(@as(u8, 0), nearest_standable.surface_floor_type);
    try std.testing.expectEqualStrings("solid", nearest_standable.surface_shape_class);
}

test "inspect-room-transitions payload exposes scene-2 secret-room key gate runtime effects" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const payload = try buildRoomTransitionInspectionPayload(allocator, resolved, 2, 1);
    defer allocator.free(payload.transitions);

    try std.testing.expectEqual(@as(usize, 1), payload.transition_count);
    const transition = payload.transitions[0];
    try std.testing.expectEqualStrings("decoded_change_cube", transition.source_kind);
    try std.testing.expectEqual(@as(usize, 0), transition.source_zone_index);
    try std.testing.expectEqual(RoomTransitionWorldPositionSummary{
        .x = 9730,
        .y = 1025,
        .z = 762,
    }, transition.runtime_probe_position.?);

    const no_key = transition.runtime_no_key_effect orelse return error.MissingRuntimeNoKeyEffect;
    try std.testing.expectEqual(@as(u8, 0), no_key.little_keys_before);
    try std.testing.expectEqual(@as(u8, 0), no_key.little_keys_after);
    try std.testing.expect(!no_key.triggered_room_transition);
    try std.testing.expectEqualStrings("house_locked_no_key", no_key.secret_room_door_event.?);
    try std.testing.expect(no_key.pending_destination_cube == null);

    const with_key = transition.runtime_with_key_effect orelse return error.MissingRuntimeWithKeyEffect;
    try std.testing.expectEqual(@as(u8, 1), with_key.little_keys_before);
    try std.testing.expectEqual(@as(u8, 0), with_key.little_keys_after);
    try std.testing.expect(with_key.triggered_room_transition);
    try std.testing.expectEqualStrings("house_consumed_key", with_key.secret_room_door_event.?);
    try std.testing.expectEqual(@as(?i16, 0), with_key.pending_destination_cube);
    try std.testing.expectEqual(RoomTransitionWorldPositionSummary{
        .x = 2562,
        .y = 2049,
        .z = 3322,
    }, with_key.pending_destination_world_position.?);
    try std.testing.expectEqual(@as(?usize, 2), with_key.destination_scene_entry_index);
    try std.testing.expectEqual(@as(?usize, 0), with_key.destination_background_entry_index);
    try std.testing.expectEqual(RoomTransitionWorldPositionSummary{
        .x = 2562,
        .y = 2048,
        .z = 3322,
    }, with_key.hero_position.?);
}

test "inspect-room-transitions payload exposes scene-2 synthetic cellar return runtime effects" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const payload = try buildRoomTransitionInspectionPayload(allocator, resolved, 2, 0);
    defer allocator.free(payload.transitions);

    try std.testing.expectEqual(@as(usize, 2), payload.transition_count);
    var synthetic_transition: ?RoomTransitionProbeSummary = null;
    for (payload.transitions) |transition| {
        if (std.mem.eql(u8, transition.source_kind, "runtime_synthetic")) {
            synthetic_transition = transition;
            break;
        }
    }
    const transition = synthetic_transition orelse return error.MissingSyntheticCellarReturn;

    try std.testing.expectEqual(@as(i16, 1), transition.destination_cube);
    try std.testing.expectEqual(@as(?usize, 2), transition.destination_scene_entry_index);
    try std.testing.expectEqual(@as(?usize, 1), transition.destination_background_entry_index);
    try std.testing.expectEqual(RoomTransitionWorldPositionSummary{
        .x = 9725,
        .y = 1024,
        .z = 1098,
    }, transition.hero_position);

    const no_key = transition.runtime_no_key_effect orelse return error.MissingRuntimeNoKeyEffect;
    try std.testing.expectEqual(@as(u8, 0), no_key.little_keys_after);
    try std.testing.expect(no_key.triggered_room_transition);
    try std.testing.expectEqualStrings("cellar_return_free", no_key.secret_room_door_event.?);
    try std.testing.expectEqual(@as(?usize, 1), no_key.destination_background_entry_index);

    const with_key = transition.runtime_with_key_effect orelse return error.MissingRuntimeWithKeyEffect;
    try std.testing.expectEqual(@as(u8, 1), with_key.little_keys_before);
    try std.testing.expectEqual(@as(u8, 1), with_key.little_keys_after);
    try std.testing.expect(with_key.triggered_room_transition);
    try std.testing.expectEqualStrings("cellar_return_free", with_key.secret_room_door_event.?);
    try std.testing.expectEqual(@as(?usize, 1), with_key.destination_background_entry_index);
}

test "inspect-room-fragment-zones payload explains the 219 219 blocker" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const diagnostics_snapshot = try room_state.inspectRoomFragmentZoneDiagnostics(allocator, resolved, 219, 219);
    defer diagnostics_snapshot.deinit(allocator);

    const payload = try buildRoomFragmentZoneDiagnosticsPayload(allocator, diagnostics_snapshot);
    defer allocator.free(payload.zones);

    try std.testing.expectEqualStrings("inspect-room-fragment-zones", payload.command);
    try std.testing.expectEqual(@as(usize, 219), payload.scene_entry_index);
    try std.testing.expectEqual(@as(usize, 219), payload.background_entry_index);
    try std.testing.expectEqual(@as(?usize, 217), payload.classic_loader_scene_number);
    try std.testing.expectEqualStrings("interior", payload.scene_kind);
    try std.testing.expectEqual(@as(usize, 3), payload.fragment_count);
    try std.testing.expectEqual(@as(usize, 6), payload.grm_zone_count);
    try std.testing.expectEqual(@as(usize, 0), payload.compatible_zone_count);
    try std.testing.expectEqual(@as(usize, 6), payload.invalid_zone_count);
    try std.testing.expectEqual(@as(?usize, 1), payload.first_invalid_zone_index);

    const first = payload.zones[0];
    try std.testing.expectEqual(@as(usize, 1), first.zone_index);
    try std.testing.expectEqual(@as(i16, 0), first.zone_num);
    try std.testing.expectEqual(@as(i32, 0), first.grm_index);
    try std.testing.expectEqualStrings("invalid_z_axis_origin", first.issue);
    try std.testing.expectEqual(@as(?usize, 159), first.fragment_entry_index);
    try std.testing.expect(first.fragment_dimensions != null);
    try std.testing.expectEqual(false, first.z_axis.origin_aligned.?);
    try std.testing.expectEqual(@as(?i32, 112), first.z_axis.origin_remainder);
    try std.testing.expectEqual(@as(?i32, 4096), first.z_axis.origin_floor_value);
    try std.testing.expectEqual(@as(?usize, 8), first.z_axis.origin_floor_cell);
    try std.testing.expectEqual(@as(?i32, 4608), first.z_axis.origin_ceil_value);
    try std.testing.expectEqual(@as(?usize, 9), first.z_axis.origin_ceil_cell);

    const third = payload.zones[2];
    try std.testing.expectEqual(@as(usize, 11), third.zone_index);
    try std.testing.expectEqualStrings("invalid_x_axis_origin", third.issue);
    try std.testing.expectEqual(@as(?usize, 160), third.fragment_entry_index);
    try std.testing.expectEqual(false, third.x_axis.origin_aligned.?);
    try std.testing.expectEqual(@as(?i32, 80), third.x_axis.origin_remainder);
}

test "inspect-room no longer exposes unsupported-life diagnostics for the former switch-family set" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectError(error.UnsupportedSceneLifeHitUnavailable, room_state.inspectUnsupportedSceneLifeHit(allocator, resolved, 2));
    try std.testing.expectError(error.UnsupportedSceneLifeHitUnavailable, room_state.inspectUnsupportedSceneLifeHit(allocator, resolved, 11));
    try std.testing.expectError(error.UnsupportedSceneLifeHitUnavailable, room_state.inspectUnsupportedSceneLifeHit(allocator, resolved, 44));
}

test "inspect-room formats invalid-fragment-zone diagnostics with offending grm zone details" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const diagnostics_snapshot = try room_state.inspectRoomFragmentZoneDiagnostics(allocator, resolved, 219, 219);
    defer diagnostics_snapshot.deinit(allocator);

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try printFragmentZoneBoundsDiagnostic(&writer, diagnostics_snapshot);

    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "event=room_load_rejected scene_entry_index=219 background_entry_index=219 reason=invalid_fragment_zone_bounds classic_loader_scene_number=217 scene_kind=interior invalid_fragment_zone_issue_count=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "event=fragment_zone_validation_issue scene_entry_index=219 background_entry_index=219 zone_index=1 zone_num=0 grm_index=0 fragment_entry_index=159 axis=z min_value=4208 max_value=5744 unit=512 failure_reason=misaligned_min issue=invalid_z_axis_origin origin_floor_value=4096 origin_floor_cell=8 origin_floor_delta=-112 origin_ceil_value=4608 origin_ceil_cell=9 origin_ceil_delta=400") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "event=fragment_zone_validation_issue scene_entry_index=219 background_entry_index=219 zone_index=11 zone_num=11 grm_index=1 fragment_entry_index=160 axis=x min_value=20048 max_value=20560 unit=512 failure_reason=misaligned_min issue=invalid_x_axis_origin origin_floor_value=19968 origin_floor_cell=39 origin_floor_delta=-80 origin_ceil_value=20480 origin_ceil_cell=40 origin_ceil_delta=432") != null);
}

test "inspect-room rejects exterior scene entries" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectError(error.ViewerSceneMustBeInterior, inspectRoom(allocator, resolved, 212, 212, true));
}

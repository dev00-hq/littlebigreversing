const std = @import("std");
const builtin = @import("builtin");
const diagnostics = @import("../foundation/diagnostics.zig");
const paths_mod = @import("../foundation/paths.zig");
const catalog = @import("../assets/catalog.zig");
const fixtures = @import("../assets/fixtures.zig");
const hqr = @import("../assets/hqr.zig");
const background_data = @import("../game_data/background.zig");
const scene_data = @import("../game_data/scene.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const life_audit = @import("../game_data/scene/life_audit.zig");
const room_state = @import("../runtime/room_state.zig");
const room_fixtures = if (builtin.is_test) @import("../testing/room_fixtures.zig") else struct {};

const Command = enum {
    inventory_assets,
    inspect_hqr,
    inspect_background,
    extract_entry,
    inspect_scene,
    inspect_room,
    audit_life_programs,
    inspect_life_program,
    generate_fixtures,
    validate_phase1,
};

const ParsedArgs = struct {
    command: Command,
    asset_root_override: ?[]u8,
    relative_path: ?[]const u8,
    entry_index: ?usize,
    background_entry_index: ?usize,
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

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const parsed = try parseArgs(allocator, args);
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
        .audit_life_programs => try auditLifePrograms(allocator, resolved, parsed),
        .inspect_life_program => try inspectLifeProgram(allocator, resolved, parsed),
        .generate_fixtures => try generateFixtures(allocator, resolved),
        .validate_phase1 => try validatePhase1(allocator, resolved),
    }
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
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
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
        const payload = .{
            .asset_path = relative_path,
            .entry_count = archive.entry_count,
            .entries = archive.entries,
        };
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.fs.File.stdout().writeAll(json);
        try std.fs.File.stdout().writeAll("\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
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
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
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
        try std.fs.File.stdout().writeAll(json);
        try std.fs.File.stdout().writeAll("\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
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
        try std.fs.File.stdout().writeAll(json);
        try std.fs.File.stdout().writeAll("\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
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
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    const room = room_state.loadRoomSnapshot(allocator, resolved, scene_entry_index, background_entry_index) catch |err| {
        if (err == error.ViewerUnsupportedSceneLife) {
            const hit = try room_state.inspectUnsupportedSceneLifeHit(allocator, resolved, scene_entry_index);
            try printUnsupportedSceneLifeDiagnostic(stderr, scene_entry_index, background_entry_index, hit);
            try stderr.flush();
        }
        return err;
    };
    defer room.deinit(allocator);

    const payload = buildRoomInspectionPayload(&room);
    if (output_json) {
        const json = try stringifyJsonAlloc(allocator, payload);
        defer allocator.free(json);
        try std.fs.File.stdout().writeAll(json);
        try std.fs.File.stdout().writeAll("\n");
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
        try std.fs.File.stdout().writeAll(json);
        try std.fs.File.stdout().writeAll("\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
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
        try std.fs.File.stdout().writeAll(json);
        try std.fs.File.stdout().writeAll("\n");
        return;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
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
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    const writer = output.writer(allocator);
    for (scene_entry_indices, 0..) |entry_index, index| {
        if (index != 0) try writer.writeAll("|");
        try writer.print("{d}", .{entry_index});
    }

    return output.toOwnedSlice(allocator);
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
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;
    try diagnostics.printLine(stderr, &.{
        .{ .key = "status", .value = "ok" },
        .{ .key = "command", .value = "generate-fixtures" },
        .{ .key = "output", .value = "work/port/phase1/fixture_manifest.json" },
    });
    try stderr.flush();
}

fn validatePhase1(allocator: std.mem.Allocator, resolved: paths_mod.ResolvedPaths) !void {
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

    try ensureMatchingFile(inventory_path, inventory_json);
    try ensureMatchingFile(fixture_path, fixture_json_first);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;
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

fn ensureMatchingFile(path: []const u8, expected: []const u8) !void {
    var file = std.fs.openFileAbsolute(path, .{}) catch return error.MissingGeneratedOutput;
    defer file.close();

    const actual = try file.readToEndAlloc(std.heap.page_allocator, 32 * 1024 * 1024);
    defer std.heap.page_allocator.free(actual);
    if (!std.mem.eql(u8, actual, expected) and !(actual.len == expected.len + 1 and actual[actual.len - 1] == '\n' and std.mem.eql(u8, actual[0 .. actual.len - 1], expected))) {
        return error.GeneratedOutputDrift;
    }
}

fn writeJson(path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try paths_mod.makePathAbsolute(parent);
    var file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
    try file.writeAll("\n");
}

fn stringifyJsonAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.io.Writer.Allocating = .init(allocator);
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

test "argument parsing supports audit-life-programs json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "audit-life-programs", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.audit_life_programs, parsed.command);
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

test "inspect-room rejects unsupported scene life outside the guarded runtime boundary" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectError(error.ViewerUnsupportedSceneLife, inspectRoom(allocator, resolved, 2, 2, true));
    try std.testing.expectError(error.ViewerUnsupportedSceneLife, inspectRoom(allocator, resolved, 44, 2, true));
    try std.testing.expectError(error.ViewerUnsupportedSceneLife, inspectRoom(allocator, resolved, 11, 10, true));
}

test "inspect-room formats unsupported-life diagnostics with first-hit blocker details" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const hit = try room_state.inspectUnsupportedSceneLifeHit(allocator, resolved, 11);
    var buffer: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try printUnsupportedSceneLifeDiagnostic(stream.writer(), 11, 10, hit);

    try std.testing.expectEqualStrings(
        "event=room_load_rejected scene_entry_index=11 background_entry_index=10 reason=unsupported_life_blob classic_loader_scene_number=9 scene_kind=interior unsupported_life_owner_kind=object unsupported_life_object_index=12 unsupported_life_opcode_name=LM_DEFAULT unsupported_life_opcode_id=116 unsupported_life_offset=38\n",
        stream.getWritten(),
    );
}

test "inspect-room rejects exterior scene entries" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    try std.testing.expectError(error.ViewerSceneMustBeInterior, inspectRoom(allocator, resolved, 212, 212, true));
}

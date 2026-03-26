const std = @import("std");
const diagnostics = @import("../foundation/diagnostics.zig");
const paths_mod = @import("../foundation/paths.zig");
const catalog = @import("../assets/catalog.zig");
const fixtures = @import("../assets/fixtures.zig");
const hqr = @import("../assets/hqr.zig");
const background_data = @import("../game_data/background.zig");
const scene_data = @import("../game_data/scene.zig");
const life_program = @import("../game_data/scene/life_program.zig");
const life_audit = @import("../game_data/scene/life_audit.zig");

const Command = enum {
    inventory_assets,
    inspect_hqr,
    inspect_background,
    extract_entry,
    inspect_scene,
    audit_life_programs,
    generate_fixtures,
    validate_phase1,
};

const ParsedArgs = struct {
    command: Command,
    asset_root_override: ?[]u8,
    relative_path: ?[]const u8,
    entry_index: ?usize,
    audit_scene_entry_indices: ?[]usize,
    audit_all_scene_entries: bool,
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
        .audit_life_programs => try auditLifePrograms(allocator, resolved, parsed),
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
        return .{ .command = .inventory_assets, .asset_root_override = asset_root_override, .relative_path = null, .entry_index = null, .audit_scene_entry_indices = null, .audit_all_scene_entries = false, .output_json = false };
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
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
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
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
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
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
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
            .audit_scene_entry_indices = null,
            .audit_all_scene_entries = false,
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
            .audit_scene_entry_indices = if (audit_all_scene_entries or scene_entry_indices.items.len == 0) null else try scene_entry_indices.toOwnedSlice(allocator),
            .audit_all_scene_entries = audit_all_scene_entries,
            .output_json = output_json,
        };
    }
    if (std.mem.eql(u8, command_name, "generate-fixtures")) {
        return .{ .command = .generate_fixtures, .asset_root_override = asset_root_override, .relative_path = null, .entry_index = null, .audit_scene_entry_indices = null, .audit_all_scene_entries = false, .output_json = false };
    }
    if (std.mem.eql(u8, command_name, "validate-phase1")) {
        return .{ .command = .validate_phase1, .asset_root_override = asset_root_override, .relative_path = null, .entry_index = null, .audit_scene_entry_indices = null, .audit_all_scene_entries = false, .output_json = false };
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

        try samples.append(allocator, .{
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
        });
    }

    return samples.toOwnedSlice(allocator);
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

test "argument parsing supports audit-life-programs json output" {
    const parsed = try parseArgs(std.testing.allocator, &.{ "audit-life-programs", "--json" });
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(Command.audit_life_programs, parsed.command);
    try std.testing.expect(parsed.output_json);
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

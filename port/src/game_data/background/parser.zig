const std = @import("std");
const hqr = @import("../../assets/hqr.zig");
const model = @import("model.zig");

const bkg_header_size = 28;
const gri_header_size = 34;
const tab_all_cube_entry_size = 2;
const column_table_width = 64;
const column_table_depth = 64;
const column_offset_count = column_table_width * column_table_depth;
const column_table_byte_length = column_offset_count * @sizeOf(u16);

pub const TabAllCubeSelection = struct {
    entry_count: usize,
    entry: model.TabAllCubeEntry,
};

pub const ParsedGriPayload = struct {
    header: model.GriHeader,
    used_blocks: model.UsedBlockSummary,
    column_table: model.ColumnTableMetadata,
    grid: model.GridComposition,

    pub fn deinit(self: ParsedGriPayload, allocator: std.mem.Allocator) void {
        self.used_blocks.deinit(allocator);
        self.grid.deinit(allocator);
    }
};

pub const ParsedBllPayload = struct {
    metadata: model.BllTableMetadata,
    library: model.LayoutLibrary,

    pub fn deinit(self: ParsedBllPayload, allocator: std.mem.Allocator) void {
        self.library.deinit(allocator);
    }
};

pub const FragmentRange = struct {
    start_index: usize,
    count: usize,
};

pub fn loadBackgroundMetadata(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    entry_index: usize,
) !model.BackgroundMetadata {
    if (entry_index == 0) return error.InvalidBackgroundEntryIndex;

    const header_raw = try hqr.extractClassicEntryToBytes(allocator, absolute_path, 0);
    defer allocator.free(header_raw);
    const header_compressed_header = try hqr.parseResourceHeader(header_raw);
    const header_payload = try hqr.decodeResourceEntryBytes(allocator, header_raw);
    defer allocator.free(header_payload);
    const bkg_header = try parseBkgHeaderPayload(header_payload);

    const tab_all_cube_entry_index = @as(usize, bkg_header.brk_start) + @as(usize, bkg_header.max_brk);
    const tab_all_cube_raw = try hqr.extractClassicEntryToBytes(allocator, absolute_path, tab_all_cube_entry_index);
    defer allocator.free(tab_all_cube_raw);
    const tab_all_cube_compressed_header = try hqr.parseResourceHeader(tab_all_cube_raw);
    const tab_all_cube_payload = try hqr.decodeResourceEntryBytes(allocator, tab_all_cube_raw);
    defer allocator.free(tab_all_cube_payload);
    const tab_all_cube_selection = try parseTabAllCubePayload(tab_all_cube_payload, entry_index);

    const remapped_cube_index = tab_all_cube_selection.entry.num;
    const gri_entry_index = @as(usize, bkg_header.gri_start) + remapped_cube_index;
    const gri_raw = try hqr.extractClassicEntryToBytes(allocator, absolute_path, gri_entry_index);
    defer allocator.free(gri_raw);
    const gri_compressed_header = try hqr.parseResourceHeader(gri_raw);
    const gri_payload = try hqr.decodeResourceEntryBytes(allocator, gri_raw);
    defer allocator.free(gri_payload);
    var gri = try parseGriPayload(allocator, gri_payload);
    errdefer gri.deinit(allocator);

    const grm_entry_index = @as(usize, bkg_header.grm_start) + @as(usize, gri.header.my_grm);
    const bll_entry_index = @as(usize, bkg_header.bll_start) + @as(usize, gri.header.my_bll);
    const bll_raw = try hqr.extractClassicEntryToBytes(allocator, absolute_path, bll_entry_index);
    defer allocator.free(bll_raw);
    const bll_compressed_header = try hqr.parseResourceHeader(bll_raw);
    const bll_payload = try hqr.decodeResourceEntryBytes(allocator, bll_raw);
    defer allocator.free(bll_payload);
    var bll = try parseBllPayload(allocator, bll_payload);
    errdefer bll.deinit(allocator);

    try validateGridAgainstLibrary(gri.grid, bll.library);
    const fragment_range = try detectFragmentRange(allocator, absolute_path, bkg_header, remapped_cube_index, gri.header.my_grm);
    var fragments = try loadFragmentLibrary(allocator, absolute_path, bll.library, fragment_range);
    errdefer fragments.deinit(allocator);

    return .{
        .entry_index = entry_index,
        .header_entry_index = 0,
        .header_compressed_header = header_compressed_header,
        .bkg_header = bkg_header,
        .tab_all_cube_entry_index = tab_all_cube_entry_index,
        .tab_all_cube_compressed_header = tab_all_cube_compressed_header,
        .tab_all_cube_entry_count = tab_all_cube_selection.entry_count,
        .tab_all_cube = tab_all_cube_selection.entry,
        .remapped_cube_index = remapped_cube_index,
        .gri_entry_index = gri_entry_index,
        .gri_compressed_header = gri_compressed_header,
        .gri_header = gri.header,
        .used_blocks = gri.used_blocks,
        .column_table = gri.column_table,
        .grm_entry_index = grm_entry_index,
        .bll_entry_index = bll_entry_index,
        .bll_compressed_header = bll_compressed_header,
        .bll = bll.metadata,
        .composition = .{
            .grid = gri.grid,
            .library = bll.library,
            .fragments = fragments,
        },
    };
}

pub fn parseBkgHeaderPayload(payload: []const u8) !model.BkgHeader {
    if (payload.len < bkg_header_size) return error.TruncatedBkgHeader;
    if (payload.len != bkg_header_size) return error.TrailingBkgHeaderBytes;

    return .{
        .gri_start = readInt(u16, payload, 0),
        .grm_start = readInt(u16, payload, 2),
        .bll_start = readInt(u16, payload, 4),
        .brk_start = readInt(u16, payload, 6),
        .max_brk = readInt(u16, payload, 8),
        .forbiden_brick = readInt(u16, payload, 10),
        .max_size_gri = readInt(u32, payload, 12),
        .max_size_bll = readInt(u32, payload, 16),
        .max_size_brick_cube = readInt(u32, payload, 20),
        .max_size_mask_brick_cube = readInt(u32, payload, 24),
    };
}

pub fn parseTabAllCubePayload(payload: []const u8, entry_index: usize) !TabAllCubeSelection {
    if (payload.len == 0) return error.EmptyTabAllCubePayload;
    if (payload.len % tab_all_cube_entry_size != 0) return error.InvalidTabAllCubePayloadSize;

    const entry_count = payload.len / tab_all_cube_entry_size;
    if (entry_index >= entry_count) return error.InvalidBackgroundEntryIndex;
    const offset = entry_index * tab_all_cube_entry_size;

    return .{
        .entry_count = entry_count,
        .entry = .{
            .type_id = payload[offset],
            .num = payload[offset + 1],
        },
    };
}

pub fn parseGriPayload(allocator: std.mem.Allocator, payload: []const u8) !ParsedGriPayload {
    if (payload.len < gri_header_size) return error.TruncatedGriHeader;

    var used_block: [32]u8 = undefined;
    @memcpy(&used_block, payload[2..gri_header_size]);
    var used_blocks = try decodeUsedBlockSummary(allocator, used_block);
    errdefer used_blocks.deinit(allocator);

    const after_header = payload[gri_header_size..];
    if (after_header.len < column_table_byte_length) return error.TruncatedGriColumnTable;

    var min_offset: u16 = std.math.maxInt(u16);
    var max_offset: u16 = 0;
    var unique_offsets = std.AutoHashMap(u16, void).init(allocator);
    defer unique_offsets.deinit();
    for (0..column_offset_count) |index| {
        const byte_offset = index * @sizeOf(u16);
        const offset = readInt(u16, after_header, byte_offset);
        if (offset < column_table_byte_length or offset >= after_header.len) {
            return error.InvalidGriColumnOffset;
        }
        min_offset = @min(min_offset, offset);
        max_offset = @max(max_offset, offset);
        try unique_offsets.put(offset, {});
    }

    var cells: std.ArrayList(model.GridCell) = .empty;
    errdefer cells.deinit(allocator);

    var spans: std.ArrayList(model.ColumnSpan) = .empty;
    errdefer spans.deinit(allocator);

    var block_refs: std.ArrayList(model.ColumnBlockRef) = .empty;
    errdefer block_refs.deinit(allocator);

    var referenced_cell_count: usize = 0;
    var reference_bounds: ?model.GridBounds = null;

    for (0..column_offset_count) |index| {
        const offset = readInt(u16, after_header, index * @sizeOf(u16));
        const cell = try parseGridCell(
            allocator,
            payload,
            offset,
            spans.items.len,
            block_refs.items.len,
        );
        if (cell.cell.non_empty_block_ref_count > 0) {
            referenced_cell_count += 1;
            const x = index % column_table_width;
            const z = index / column_table_width;
            if (reference_bounds) |*bounds| {
                bounds.min_x = @min(bounds.min_x, x);
                bounds.max_x = @max(bounds.max_x, x);
                bounds.min_z = @min(bounds.min_z, z);
                bounds.max_z = @max(bounds.max_z, z);
            } else {
                reference_bounds = .{
                    .min_x = x,
                    .max_x = x,
                    .min_z = z,
                    .max_z = z,
                };
            }
        }
        try spans.appendSlice(allocator, cell.spans);
        try block_refs.appendSlice(allocator, cell.block_refs);
        try cells.append(allocator, cell.cell);
        allocator.free(cell.spans);
        allocator.free(cell.block_refs);
    }

    return .{
        .header = .{
            .my_bll = payload[0],
            .my_grm = payload[1],
            .used_block = used_block,
        },
        .used_blocks = used_blocks,
        .column_table = .{
            .width = column_table_width,
            .depth = column_table_depth,
            .offset_count = column_offset_count,
            .table_byte_length = column_table_byte_length,
            .data_byte_length = after_header.len - column_table_byte_length,
            .min_offset = min_offset,
            .max_offset = max_offset,
        },
        .grid = .{
            .width = column_table_width,
            .depth = column_table_depth,
            .cells = try cells.toOwnedSlice(allocator),
            .spans = try spans.toOwnedSlice(allocator),
            .block_refs = try block_refs.toOwnedSlice(allocator),
            .unique_offset_count = unique_offsets.count(),
            .referenced_cell_count = referenced_cell_count,
            .reference_bounds = reference_bounds,
        },
    };
}

pub fn parseBllPayload(allocator: std.mem.Allocator, payload: []const u8) !ParsedBllPayload {
    if (payload.len < @sizeOf(u32)) return error.TruncatedBllTable;

    const table_byte_length = readInt(u32, payload, 0);
    if (table_byte_length < @sizeOf(u32) or table_byte_length % @sizeOf(u32) != 0 or table_byte_length > payload.len) {
        return error.InvalidBllTableHeader;
    }

    const block_count = table_byte_length / @sizeOf(u32);
    var first_block_offset: u32 = std.math.maxInt(u32);
    var last_block_offset: u32 = 0;

    for (0..block_count) |index| {
        const offset = readInt(u32, payload, index * @sizeOf(u32));
        if (offset < table_byte_length or offset > payload.len) return error.InvalidBllBlockOffset;

        var next_offset: usize = payload.len;
        for ((index + 1)..block_count) |search| {
            const candidate = readInt(u32, payload, search * @sizeOf(u32));
            if (candidate < table_byte_length or candidate > payload.len) return error.InvalidBllBlockOffset;
            if (candidate > offset) next_offset = @min(next_offset, candidate);
        }
        if (next_offset < offset) return error.InvalidBllBlockOffset;

        first_block_offset = @min(first_block_offset, offset);
        last_block_offset = @max(last_block_offset, offset);
    }

    var layouts: std.ArrayList(model.Layout) = .empty;
    errdefer layouts.deinit(allocator);

    var layout_blocks: std.ArrayList(model.LayoutBlock) = .empty;
    errdefer layout_blocks.deinit(allocator);

    var max_layout_block_count: usize = 0;

    for (0..block_count) |index| {
        const start = readInt(u32, payload, index * @sizeOf(u32));
        const next = findNextOffset(payload, table_byte_length, index, start);
        if (start + 3 > next) return error.TruncatedBllLayoutHeader;

        const x = payload[start];
        const y = payload[start + 1];
        const z = payload[start + 2];
        if (x == 0 or y == 0 or z == 0) return error.InvalidBllLayoutDimensions;

        const layout_block_count = @as(usize, x) * @as(usize, y) * @as(usize, z);
        const expected_byte_length = 3 + (layout_block_count * 4);
        if (start + expected_byte_length > next) return error.TruncatedBllLayoutBlocks;
        if (start + expected_byte_length != next) return error.InvalidBllLayoutSize;

        const block_start = layout_blocks.items.len;
        var pos = start + 3;
        for (0..layout_block_count) |_| {
            try layout_blocks.append(allocator, .{
                .shape = payload[pos],
                .sound_floor = payload[pos + 1],
                .brick_index = readInt(u16, payload, pos + 2),
            });
            pos += 4;
        }

        max_layout_block_count = @max(max_layout_block_count, layout_block_count);
        try layouts.append(allocator, .{
            .index = index + 1,
            .start_offset = @intCast(start),
            .byte_length = expected_byte_length,
            .x = x,
            .y = y,
            .z = z,
            .block_start = block_start,
            .block_count = layout_block_count,
        });
    }

    return .{
        .metadata = .{
            .block_count = block_count,
            .table_byte_length = @intCast(table_byte_length),
            .first_block_offset = if (block_count == 0) 0 else first_block_offset,
            .last_block_offset = last_block_offset,
        },
        .library = .{
            .layouts = try layouts.toOwnedSlice(allocator),
            .layout_blocks = try layout_blocks.toOwnedSlice(allocator),
            .max_layout_block_count = max_layout_block_count,
        },
    };
}

pub fn parseFragmentPayload(
    allocator: std.mem.Allocator,
    payload: []const u8,
    relative_index: usize,
    entry_index: usize,
) !model.Fragment {
    if (payload.len < 3) return error.TruncatedGrmFragment;

    const width = payload[0];
    const height = payload[1];
    const depth = payload[2];

    const cell_count = @as(usize, width) * @as(usize, depth);
    const block_ref_count = cell_count * @as(usize, height);
    const expected_len = 3 + (block_ref_count * 2);
    if (payload.len < expected_len) return error.TruncatedGrmFragmentPayload;
    if (payload.len != expected_len) return error.InvalidGrmFragmentSize;

    var cells: std.ArrayList(model.FragmentCell) = .empty;
    errdefer cells.deinit(allocator);
    try cells.ensureTotalCapacity(allocator, cell_count);

    var block_refs: std.ArrayList(model.ColumnBlockRef) = .empty;
    errdefer block_refs.deinit(allocator);
    try block_refs.ensureTotalCapacity(allocator, block_ref_count);

    var non_empty_cell_count: usize = 0;
    var non_empty_bounds: ?model.GridBounds = null;
    var max_non_empty_column_height: u8 = 0;
    var cursor: usize = 3;

    for (0..@as(usize, depth)) |z| {
        for (0..@as(usize, width)) |x| {
            const block_ref_start = block_refs.items.len;
            var non_empty_block_ref_count: usize = 0;
            var first_non_empty_block_ref_index: ?usize = null;
            var last_non_empty_block_ref_index: ?usize = null;

            for (0..@as(usize, height)) |_| {
                const block_ref_index = block_refs.items.len;
                const block_ref = model.ColumnBlockRef{
                    .layout_index = payload[cursor],
                    .layout_block_index = payload[cursor + 1],
                };
                cursor += 2;
                try block_refs.append(allocator, block_ref);
                if (block_ref.layout_index == 0) continue;
                non_empty_block_ref_count += 1;
                if (first_non_empty_block_ref_index == null) first_non_empty_block_ref_index = block_ref_index;
                last_non_empty_block_ref_index = block_ref_index;
            }

            if (non_empty_block_ref_count > 0) {
                non_empty_cell_count += 1;
                max_non_empty_column_height = @max(
                    max_non_empty_column_height,
                    std.math.cast(u8, non_empty_block_ref_count) orelse return error.InvalidGrmFragmentSize,
                );
                if (non_empty_bounds) |*bounds| {
                    bounds.min_x = @min(bounds.min_x, x);
                    bounds.max_x = @max(bounds.max_x, x);
                    bounds.min_z = @min(bounds.min_z, z);
                    bounds.max_z = @max(bounds.max_z, z);
                } else {
                    non_empty_bounds = .{
                        .min_x = x,
                        .max_x = x,
                        .min_z = z,
                        .max_z = z,
                    };
                }
            }

            try cells.append(allocator, .{
                .x = x,
                .z = z,
                .block_ref_start = block_ref_start,
                .block_ref_count = @as(usize, height),
                .non_empty_block_ref_count = non_empty_block_ref_count,
                .first_non_empty_block_ref_index = first_non_empty_block_ref_index,
                .last_non_empty_block_ref_index = last_non_empty_block_ref_index,
            });
        }
    }

    return .{
        .relative_index = relative_index,
        .entry_index = entry_index,
        .width = width,
        .height = height,
        .depth = depth,
        .cells = try cells.toOwnedSlice(allocator),
        .block_refs = try block_refs.toOwnedSlice(allocator),
        .footprint_cell_count = cell_count,
        .non_empty_cell_count = non_empty_cell_count,
        .non_empty_bounds = non_empty_bounds,
        .max_non_empty_column_height = max_non_empty_column_height,
    };
}

fn decodeUsedBlockSummary(allocator: std.mem.Allocator, used_block: [32]u8) !model.UsedBlockSummary {
    var used_block_ids: std.ArrayList(u8) = .empty;
    errdefer used_block_ids.deinit(allocator);

    for (1..256) |block_id| {
        const byte = used_block[block_id >> 3];
        const bit = @as(u8, 1) << @intCast(7 - (block_id & 7));
        if ((byte & bit) == 0) continue;
        try used_block_ids.append(allocator, @intCast(block_id));
    }

    return .{
        .raw_bytes = used_block,
        .used_block_ids = try used_block_ids.toOwnedSlice(allocator),
    };
}

const ParsedGridCell = struct {
    cell: model.GridCell,
    spans: []model.ColumnSpan,
    block_refs: []model.ColumnBlockRef,
};

fn parseGridCell(
    allocator: std.mem.Allocator,
    payload: []const u8,
    offset: u16,
    span_start: usize,
    block_ref_start: usize,
) !ParsedGridCell {
    var local_spans: std.ArrayList(model.ColumnSpan) = .empty;
    errdefer local_spans.deinit(allocator);

    var local_block_refs: std.ArrayList(model.ColumnBlockRef) = .empty;
    errdefer local_block_refs.deinit(allocator);

    var cursor: usize = gri_header_size + offset;
    if (cursor >= payload.len) return error.InvalidGriColumnOffset;

    const span_count = payload[cursor];
    cursor += 1;
    if (span_count == 0) return error.InvalidGriColumnSpanCount;

    var total_height: usize = 0;
    var non_empty_block_ref_count: usize = 0;
    var first_non_empty_block_ref_index: ?usize = null;
    var last_non_empty_block_ref_index: ?usize = null;

    for (0..span_count) |_| {
        if (cursor >= payload.len) return error.TruncatedGriColumnPayload;

        const descriptor = payload[cursor];
        cursor += 1;
        const encoding = switch (descriptor >> 6) {
            0 => model.ColumnEncoding.empty,
            1 => model.ColumnEncoding.explicit,
            2 => model.ColumnEncoding.repeated,
            else => return error.UnsupportedGriColumnEncoding,
        };
        const height: u8 = (descriptor & 0x1F) + 1;
        total_height += height;
        if (total_height > 25) return error.InvalidGriColumnHeight;

        const span_block_ref_start = block_ref_start + local_block_refs.items.len;
        switch (encoding) {
            .empty => {
                try local_spans.append(allocator, .{
                    .encoding = encoding,
                    .height = height,
                    .block_ref_start = span_block_ref_start,
                    .block_ref_count = 0,
                });
            },
            .explicit => {
                if (cursor + (@as(usize, height) * 2) > payload.len) return error.TruncatedGriColumnPayload;
                const before_refs = local_block_refs.items.len;
                for (0..height) |_| {
                    const block_ref_index = block_ref_start + local_block_refs.items.len;
                    const block_ref = model.ColumnBlockRef{
                        .layout_index = payload[cursor],
                        .layout_block_index = payload[cursor + 1],
                    };
                    cursor += 2;
                    try local_block_refs.append(allocator, block_ref);
                    if (block_ref.layout_index == 0) continue;
                    non_empty_block_ref_count += 1;
                    if (first_non_empty_block_ref_index == null) first_non_empty_block_ref_index = block_ref_index;
                    last_non_empty_block_ref_index = block_ref_index;
                }
                try local_spans.append(allocator, .{
                    .encoding = encoding,
                    .height = height,
                    .block_ref_start = span_block_ref_start,
                    .block_ref_count = local_block_refs.items.len - before_refs,
                });
            },
            .repeated => {
                if (cursor + 2 > payload.len) return error.TruncatedGriColumnPayload;
                const block_ref_index = block_ref_start + local_block_refs.items.len;
                const block_ref = model.ColumnBlockRef{
                    .layout_index = payload[cursor],
                    .layout_block_index = payload[cursor + 1],
                };
                cursor += 2;
                try local_block_refs.append(allocator, block_ref);
                if (block_ref.layout_index != 0) {
                    non_empty_block_ref_count += height;
                    if (first_non_empty_block_ref_index == null) first_non_empty_block_ref_index = block_ref_index;
                    last_non_empty_block_ref_index = block_ref_index;
                }
                try local_spans.append(allocator, .{
                    .encoding = encoding,
                    .height = height,
                    .block_ref_start = span_block_ref_start,
                    .block_ref_count = 1,
                });
            },
        }
    }

    return .{
        .cell = .{
            .offset = offset,
            .span_start = span_start,
            .span_count = span_count,
            .total_height = total_height,
            .non_empty_block_ref_count = non_empty_block_ref_count,
            .first_non_empty_block_ref_index = first_non_empty_block_ref_index,
            .last_non_empty_block_ref_index = last_non_empty_block_ref_index,
        },
        .spans = try local_spans.toOwnedSlice(allocator),
        .block_refs = try local_block_refs.toOwnedSlice(allocator),
    };
}

fn findNextOffset(payload: []const u8, table_byte_length: u32, index: usize, offset: u32) usize {
    var next_offset: usize = payload.len;
    const block_count = table_byte_length / @sizeOf(u32);
    var search = index + 1;
    while (search < block_count) : (search += 1) {
        const candidate = readInt(u32, payload, search * @sizeOf(u32));
        if (candidate > offset and candidate < next_offset) next_offset = candidate;
    }
    return next_offset;
}

fn validateGridAgainstLibrary(grid: model.GridComposition, library: model.LayoutLibrary) !void {
    for (grid.block_refs) |block_ref| {
        if (block_ref.layout_index == 0) continue;
        if (block_ref.layout_index > library.layouts.len) return error.InvalidGriLayoutReference;

        const layout = library.layouts[block_ref.layout_index - 1];
        if (block_ref.layout_block_index >= layout.block_count) return error.InvalidGriLayoutBlockReference;
    }
}

fn loadFragmentLibrary(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    library: model.LayoutLibrary,
    range: FragmentRange,
) !model.FragmentLibrary {
    var fragments: std.ArrayList(model.Fragment) = .empty;
    errdefer {
        for (fragments.items) |fragment| fragment.deinit(allocator);
        fragments.deinit(allocator);
    }

    var footprint_cell_count: usize = 0;
    var non_empty_cell_count: usize = 0;
    var max_height: u8 = 0;

    for (0..range.count) |relative_index| {
        const entry_index = range.start_index + relative_index;
        const raw = try hqr.extractClassicEntryToBytes(allocator, absolute_path, entry_index);
        defer allocator.free(raw);
        const payload = try hqr.decodeResourceEntryBytes(allocator, raw);
        defer allocator.free(payload);

        var fragment = try parseFragmentPayload(allocator, payload, relative_index, entry_index);
        errdefer fragment.deinit(allocator);

        try validateFragmentAgainstLibrary(fragment, library);

        footprint_cell_count += fragment.footprint_cell_count;
        non_empty_cell_count += fragment.non_empty_cell_count;
        max_height = @max(max_height, fragment.height);
        try fragments.append(allocator, fragment);
    }

    return .{
        .fragments = try fragments.toOwnedSlice(allocator),
        .footprint_cell_count = footprint_cell_count,
        .non_empty_cell_count = non_empty_cell_count,
        .max_height = max_height,
    };
}

fn detectFragmentRange(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    bkg_header: model.BkgHeader,
    remapped_cube_index: usize,
    current_my_grm: u8,
) !FragmentRange {
    const total_grid_count = @as(usize, bkg_header.grm_start) - @as(usize, bkg_header.gri_start);
    const total_fragment_count = @as(usize, bkg_header.bll_start) - @as(usize, bkg_header.grm_start);
    const current_fragment_index = @as(usize, current_my_grm);
    if (remapped_cube_index >= total_grid_count) return error.InvalidBackgroundGridIndex;
    if (current_fragment_index > total_fragment_count) return error.InvalidBackgroundFragmentIndex;

    var next_fragment_index = total_fragment_count;
    if (remapped_cube_index + 1 < total_grid_count) {
        const next_gri_entry_index = @as(usize, bkg_header.gri_start) + remapped_cube_index + 1;
        const next_my_grm = try loadGriMyGrm(allocator, absolute_path, next_gri_entry_index);
        if (next_my_grm < current_my_grm) return error.InvalidBackgroundFragmentOrdering;
        if (next_my_grm == current_my_grm) {
            next_fragment_index = current_fragment_index;
        } else {
            next_fragment_index = @as(usize, next_my_grm);
        }
    }

    if (next_fragment_index < current_fragment_index or next_fragment_index > total_fragment_count) {
        return error.InvalidBackgroundFragmentIndex;
    }

    return .{
        .start_index = @as(usize, bkg_header.grm_start) + current_fragment_index,
        .count = next_fragment_index - current_fragment_index,
    };
}

fn loadGriMyGrm(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    gri_entry_index: usize,
) !u8 {
    const raw = try hqr.extractClassicEntryToBytes(allocator, absolute_path, gri_entry_index);
    defer allocator.free(raw);
    const payload = try hqr.decodeResourceEntryBytes(allocator, raw);
    defer allocator.free(payload);
    if (payload.len < 2) return error.TruncatedGriHeader;
    return payload[1];
}

fn validateFragmentAgainstLibrary(fragment: model.Fragment, library: model.LayoutLibrary) !void {
    for (fragment.block_refs) |block_ref| {
        if (block_ref.layout_index == 0) continue;
        if (block_ref.layout_index > library.layouts.len) return error.InvalidGrmLayoutReference;

        const layout = library.layouts[block_ref.layout_index - 1];
        if (block_ref.layout_block_index >= layout.block_count) return error.InvalidGrmLayoutBlockReference;
    }
}

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    const size = @sizeOf(T);
    return std.mem.readInt(T, bytes[offset .. offset + size][0..size], .little);
}

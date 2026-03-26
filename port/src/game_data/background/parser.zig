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

    pub fn deinit(self: ParsedGriPayload, allocator: std.mem.Allocator) void {
        self.used_blocks.deinit(allocator);
    }
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
    const bll = try parseBllPayload(bll_payload);

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
        .bll = bll,
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
    for (0..column_offset_count) |index| {
        const byte_offset = index * @sizeOf(u16);
        const offset = readInt(u16, after_header, byte_offset);
        if (offset < column_table_byte_length or offset >= after_header.len) {
            return error.InvalidGriColumnOffset;
        }
        min_offset = @min(min_offset, offset);
        max_offset = @max(max_offset, offset);
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
    };
}

pub fn parseBllPayload(payload: []const u8) !model.BllTableMetadata {
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

    return .{
        .block_count = block_count,
        .table_byte_length = @intCast(table_byte_length),
        .first_block_offset = if (block_count == 0) 0 else first_block_offset,
        .last_block_offset = last_block_offset,
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

fn readInt(comptime T: type, bytes: []const u8, offset: usize) T {
    const size = @sizeOf(T);
    return std.mem.readInt(T, bytes[offset .. offset + size][0..size], .little);
}

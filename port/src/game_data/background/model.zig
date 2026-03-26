const std = @import("std");
const hqr = @import("../../assets/hqr.zig");

pub const BkgHeader = struct {
    gri_start: u16,
    grm_start: u16,
    bll_start: u16,
    brk_start: u16,
    max_brk: u16,
    forbiden_brick: u16,
    max_size_gri: u32,
    max_size_bll: u32,
    max_size_brick_cube: u32,
    max_size_mask_brick_cube: u32,
};

pub const TabAllCubeEntry = struct {
    type_id: u8,
    num: u8,
};

pub const GriHeader = struct {
    my_bll: u8,
    my_grm: u8,
    used_block: [32]u8,
};

pub const UsedBlockSummary = struct {
    raw_bytes: [32]u8,
    used_block_ids: []u8,

    pub fn deinit(self: UsedBlockSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.used_block_ids);
    }
};

pub const ColumnTableMetadata = struct {
    width: usize,
    depth: usize,
    offset_count: usize,
    table_byte_length: usize,
    data_byte_length: usize,
    min_offset: u16,
    max_offset: u16,
};

pub const BllTableMetadata = struct {
    block_count: usize,
    table_byte_length: u32,
    first_block_offset: u32,
    last_block_offset: u32,
};

pub const BackgroundMetadata = struct {
    entry_index: usize,
    header_entry_index: usize,
    header_compressed_header: hqr.ResourceHeader,
    bkg_header: BkgHeader,
    tab_all_cube_entry_index: usize,
    tab_all_cube_compressed_header: hqr.ResourceHeader,
    tab_all_cube_entry_count: usize,
    tab_all_cube: TabAllCubeEntry,
    remapped_cube_index: usize,
    gri_entry_index: usize,
    gri_compressed_header: hqr.ResourceHeader,
    gri_header: GriHeader,
    used_blocks: UsedBlockSummary,
    column_table: ColumnTableMetadata,
    grm_entry_index: usize,
    bll_entry_index: usize,
    bll_compressed_header: hqr.ResourceHeader,
    bll: BllTableMetadata,

    pub fn deinit(self: BackgroundMetadata, allocator: std.mem.Allocator) void {
        self.used_blocks.deinit(allocator);
    }
};

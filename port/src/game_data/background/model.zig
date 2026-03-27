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

pub const GridBounds = struct {
    min_x: usize,
    max_x: usize,
    min_z: usize,
    max_z: usize,
};

pub const ColumnEncoding = enum(u2) {
    empty = 0,
    explicit = 1,
    repeated = 2,
};

pub const ColumnBlockRef = struct {
    layout_index: u8,
    layout_block_index: u8,
};

pub const ColumnSpan = struct {
    encoding: ColumnEncoding,
    height: u8,
    block_ref_start: usize,
    block_ref_count: usize,
};

pub const GridCell = struct {
    offset: u16,
    span_start: usize,
    span_count: usize,
    total_height: usize,
    non_empty_block_ref_count: usize,
    first_non_empty_block_ref_index: ?usize,
    last_non_empty_block_ref_index: ?usize,
};

pub const GridCompositionSummary = struct {
    width: usize,
    depth: usize,
    cell_count: usize,
    unique_offset_count: usize,
    referenced_cell_count: usize,
    reference_bounds: ?GridBounds,
};

pub const GridComposition = struct {
    width: usize,
    depth: usize,
    cells: []GridCell,
    spans: []ColumnSpan,
    block_refs: []ColumnBlockRef,
    unique_offset_count: usize,
    referenced_cell_count: usize,
    reference_bounds: ?GridBounds,

    pub fn deinit(self: GridComposition, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
        allocator.free(self.spans);
        allocator.free(self.block_refs);
    }

    pub fn summary(self: GridComposition) GridCompositionSummary {
        return .{
            .width = self.width,
            .depth = self.depth,
            .cell_count = self.cells.len,
            .unique_offset_count = self.unique_offset_count,
            .referenced_cell_count = self.referenced_cell_count,
            .reference_bounds = self.reference_bounds,
        };
    }

    pub fn jsonStringify(self: GridComposition, jw: anytype) !void {
        try jw.write(self.summary());
    }
};

pub const LayoutBlock = struct {
    shape: u8,
    sound_floor: u8,
    brick_index: u16,

    pub fn floorType(self: LayoutBlock) u8 {
        return self.sound_floor >> 4;
    }

    pub fn soundId(self: LayoutBlock) u8 {
        return self.sound_floor & 0x0F;
    }
};

pub const Layout = struct {
    index: usize,
    start_offset: u32,
    byte_length: usize,
    x: u8,
    y: u8,
    z: u8,
    block_start: usize,
    block_count: usize,
};

pub const LayoutLibrarySummary = struct {
    layout_count: usize,
    layout_block_count: usize,
    max_layout_block_count: usize,
};

pub const LayoutLibrary = struct {
    layouts: []Layout,
    layout_blocks: []LayoutBlock,
    max_layout_block_count: usize,

    pub fn deinit(self: LayoutLibrary, allocator: std.mem.Allocator) void {
        allocator.free(self.layouts);
        allocator.free(self.layout_blocks);
    }

    pub fn summary(self: LayoutLibrary) LayoutLibrarySummary {
        return .{
            .layout_count = self.layouts.len,
            .layout_block_count = self.layout_blocks.len,
            .max_layout_block_count = self.max_layout_block_count,
        };
    }

    pub fn jsonStringify(self: LayoutLibrary, jw: anytype) !void {
        try jw.write(self.summary());
    }
};

pub const BackgroundCompositionSummary = struct {
    grid: GridCompositionSummary,
    library: LayoutLibrarySummary,
};

pub const BackgroundComposition = struct {
    grid: GridComposition,
    library: LayoutLibrary,

    pub fn deinit(self: BackgroundComposition, allocator: std.mem.Allocator) void {
        self.grid.deinit(allocator);
        self.library.deinit(allocator);
    }

    pub fn summary(self: BackgroundComposition) BackgroundCompositionSummary {
        return .{
            .grid = self.grid.summary(),
            .library = self.library.summary(),
        };
    }

    pub fn jsonStringify(self: BackgroundComposition, jw: anytype) !void {
        try jw.write(self.summary());
    }
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
    composition: BackgroundComposition,

    pub fn deinit(self: BackgroundMetadata, allocator: std.mem.Allocator) void {
        self.used_blocks.deinit(allocator);
        self.composition.deinit(allocator);
    }
};

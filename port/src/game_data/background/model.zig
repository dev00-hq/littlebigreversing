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

pub const brick_preview_swatch_side: usize = 8;
pub const brick_preview_swatch_pixel_count: usize = brick_preview_swatch_side * brick_preview_swatch_side;

pub const BrickSwatchPixel = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
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

pub const FragmentCell = struct {
    x: usize,
    z: usize,
    block_ref_start: usize,
    block_ref_count: usize,
    non_empty_block_ref_count: usize,
    first_non_empty_block_ref_index: ?usize,
    last_non_empty_block_ref_index: ?usize,
};

pub const FragmentSummary = struct {
    relative_index: usize,
    entry_index: usize,
    width: u8,
    height: u8,
    depth: u8,
    footprint_cell_count: usize,
    non_empty_cell_count: usize,
    non_empty_bounds: ?GridBounds,
    max_non_empty_column_height: u8,
};

pub const Fragment = struct {
    relative_index: usize,
    entry_index: usize,
    width: u8,
    height: u8,
    depth: u8,
    cells: []FragmentCell,
    block_refs: []ColumnBlockRef,
    footprint_cell_count: usize,
    non_empty_cell_count: usize,
    non_empty_bounds: ?GridBounds,
    max_non_empty_column_height: u8,

    pub fn deinit(self: Fragment, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
        allocator.free(self.block_refs);
    }

    pub fn summary(self: Fragment) FragmentSummary {
        return .{
            .relative_index = self.relative_index,
            .entry_index = self.entry_index,
            .width = self.width,
            .height = self.height,
            .depth = self.depth,
            .footprint_cell_count = self.footprint_cell_count,
            .non_empty_cell_count = self.non_empty_cell_count,
            .non_empty_bounds = self.non_empty_bounds,
            .max_non_empty_column_height = self.max_non_empty_column_height,
        };
    }

    pub fn jsonStringify(self: Fragment, jw: anytype) !void {
        try jw.write(self.summary());
    }
};

pub const FragmentLibrarySummary = struct {
    fragment_count: usize,
    footprint_cell_count: usize,
    non_empty_cell_count: usize,
    max_height: u8,
};

pub const FragmentLibrary = struct {
    fragments: []Fragment,
    footprint_cell_count: usize,
    non_empty_cell_count: usize,
    max_height: u8,

    pub fn deinit(self: FragmentLibrary, allocator: std.mem.Allocator) void {
        for (self.fragments) |fragment| fragment.deinit(allocator);
        allocator.free(self.fragments);
    }

    pub fn summary(self: FragmentLibrary) FragmentLibrarySummary {
        return .{
            .fragment_count = self.fragments.len,
            .footprint_cell_count = self.footprint_cell_count,
            .non_empty_cell_count = self.non_empty_cell_count,
            .max_height = self.max_height,
        };
    }

    pub fn jsonStringify(self: FragmentLibrary, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("fragment_count");
        try jw.write(self.fragments.len);
        try jw.objectField("footprint_cell_count");
        try jw.write(self.footprint_cell_count);
        try jw.objectField("non_empty_cell_count");
        try jw.write(self.non_empty_cell_count);
        try jw.objectField("max_height");
        try jw.write(self.max_height);
        try jw.objectField("fragments");
        try jw.beginArray();
        for (self.fragments) |fragment| try jw.write(fragment.summary());
        try jw.endArray();
        try jw.endObject();
    }
};

pub const BrickPreviewSummary = struct {
    brick_index: u16,
    entry_index: usize,
    width: u8,
    height: u8,
    offset_x: u8,
    offset_y: u8,
    opaque_pixel_count: usize,
    unique_color_count: usize,
};

pub const BrickPreview = struct {
    brick_index: u16,
    entry_index: usize,
    width: u8,
    height: u8,
    offset_x: u8,
    offset_y: u8,
    opaque_pixel_count: usize,
    unique_color_count: usize,
    swatch: [brick_preview_swatch_pixel_count]BrickSwatchPixel,

    pub fn summary(self: BrickPreview) BrickPreviewSummary {
        return .{
            .brick_index = self.brick_index,
            .entry_index = self.entry_index,
            .width = self.width,
            .height = self.height,
            .offset_x = self.offset_x,
            .offset_y = self.offset_y,
            .opaque_pixel_count = self.opaque_pixel_count,
            .unique_color_count = self.unique_color_count,
        };
    }

    pub fn jsonStringify(self: BrickPreview, jw: anytype) !void {
        try jw.write(self.summary());
    }
};

pub const BrickPreviewLibrarySummary = struct {
    palette_entry_index: usize,
    preview_count: usize,
    max_preview_width: u8,
    max_preview_height: u8,
    total_opaque_pixel_count: usize,
};

pub const BrickPreviewLibrary = struct {
    palette_entry_index: usize,
    previews: []BrickPreview,
    max_preview_width: u8,
    max_preview_height: u8,
    total_opaque_pixel_count: usize,

    pub fn deinit(self: BrickPreviewLibrary, allocator: std.mem.Allocator) void {
        allocator.free(self.previews);
    }

    pub fn summary(self: BrickPreviewLibrary) BrickPreviewLibrarySummary {
        return .{
            .palette_entry_index = self.palette_entry_index,
            .preview_count = self.previews.len,
            .max_preview_width = self.max_preview_width,
            .max_preview_height = self.max_preview_height,
            .total_opaque_pixel_count = self.total_opaque_pixel_count,
        };
    }

    pub fn jsonStringify(self: BrickPreviewLibrary, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("palette_entry_index");
        try jw.write(self.palette_entry_index);
        try jw.objectField("preview_count");
        try jw.write(self.previews.len);
        try jw.objectField("max_preview_width");
        try jw.write(self.max_preview_width);
        try jw.objectField("max_preview_height");
        try jw.write(self.max_preview_height);
        try jw.objectField("total_opaque_pixel_count");
        try jw.write(self.total_opaque_pixel_count);
        try jw.objectField("previews");
        try jw.beginArray();
        for (self.previews) |preview| try jw.write(preview.summary());
        try jw.endArray();
        try jw.endObject();
    }
};

pub const BackgroundCompositionSummary = struct {
    grid: GridCompositionSummary,
    library: LayoutLibrarySummary,
    fragments: FragmentLibrarySummary,
    bricks: BrickPreviewLibrarySummary,
};

pub const BackgroundComposition = struct {
    grid: GridComposition,
    library: LayoutLibrary,
    fragments: FragmentLibrary,
    bricks: BrickPreviewLibrary,

    pub fn deinit(self: BackgroundComposition, allocator: std.mem.Allocator) void {
        self.grid.deinit(allocator);
        self.library.deinit(allocator);
        self.fragments.deinit(allocator);
        self.bricks.deinit(allocator);
    }

    pub fn summary(self: BackgroundComposition) BackgroundCompositionSummary {
        return .{
            .grid = self.grid.summary(),
            .library = self.library.summary(),
            .fragments = self.fragments.summary(),
            .bricks = self.bricks.summary(),
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

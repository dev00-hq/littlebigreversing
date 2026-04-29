const std = @import("std");
const model = @import("background/model.zig");
const parser = @import("background/parser.zig");

pub const BkgHeader = model.BkgHeader;
pub const TabAllCubeEntry = model.TabAllCubeEntry;
pub const GriHeader = model.GriHeader;
pub const UsedBlockSummary = model.UsedBlockSummary;
pub const ColumnTableMetadata = model.ColumnTableMetadata;
pub const BllTableMetadata = model.BllTableMetadata;
pub const GridBounds = model.GridBounds;
pub const ColumnEncoding = model.ColumnEncoding;
pub const ColumnBlockRef = model.ColumnBlockRef;
pub const ColumnSpan = model.ColumnSpan;
pub const GridCell = model.GridCell;
pub const GridCompositionSummary = model.GridCompositionSummary;
pub const GridComposition = model.GridComposition;
pub const LayoutBlock = model.LayoutBlock;
pub const Layout = model.Layout;
pub const LayoutLibrarySummary = model.LayoutLibrarySummary;
pub const LayoutLibrary = model.LayoutLibrary;
pub const FragmentCell = model.FragmentCell;
pub const FragmentSummary = model.FragmentSummary;
pub const Fragment = model.Fragment;
pub const FragmentLibrarySummary = model.FragmentLibrarySummary;
pub const FragmentLibrary = model.FragmentLibrary;
pub const brick_preview_swatch_side = model.brick_preview_swatch_side;
pub const brick_preview_swatch_pixel_count = model.brick_preview_swatch_pixel_count;
pub const BrickSwatchPixel = model.BrickSwatchPixel;
pub const BrickPreviewSummary = model.BrickPreviewSummary;
pub const BrickPreview = model.BrickPreview;
pub const BrickPreviewLibrarySummary = model.BrickPreviewLibrarySummary;
pub const BrickPreviewLibrary = model.BrickPreviewLibrary;
pub const BackgroundCompositionSummary = model.BackgroundCompositionSummary;
pub const BackgroundTopologyCompositionSummary = model.BackgroundTopologyCompositionSummary;
pub const BackgroundTopologyComposition = model.BackgroundTopologyComposition;
pub const BackgroundComposition = model.BackgroundComposition;
pub const BackgroundTopologyMetadata = model.BackgroundTopologyMetadata;
pub const BackgroundMetadata = model.BackgroundMetadata;

pub const loadBackgroundTopologyMetadata = parser.loadBackgroundTopologyMetadata;
pub const loadBackgroundMetadata = parser.loadBackgroundMetadata;
pub const loadBackgroundEntryCount = parser.loadBackgroundEntryCount;

test "background facade reexports the stable public API" {
    comptime {
        if (BkgHeader != model.BkgHeader) @compileError("BkgHeader facade drifted");
        if (TabAllCubeEntry != model.TabAllCubeEntry) @compileError("TabAllCubeEntry facade drifted");
        if (GriHeader != model.GriHeader) @compileError("GriHeader facade drifted");
        if (UsedBlockSummary != model.UsedBlockSummary) @compileError("UsedBlockSummary facade drifted");
        if (ColumnTableMetadata != model.ColumnTableMetadata) @compileError("ColumnTableMetadata facade drifted");
        if (BllTableMetadata != model.BllTableMetadata) @compileError("BllTableMetadata facade drifted");
        if (GridBounds != model.GridBounds) @compileError("GridBounds facade drifted");
        if (ColumnEncoding != model.ColumnEncoding) @compileError("ColumnEncoding facade drifted");
        if (ColumnBlockRef != model.ColumnBlockRef) @compileError("ColumnBlockRef facade drifted");
        if (ColumnSpan != model.ColumnSpan) @compileError("ColumnSpan facade drifted");
        if (GridCell != model.GridCell) @compileError("GridCell facade drifted");
        if (GridCompositionSummary != model.GridCompositionSummary) @compileError("GridCompositionSummary facade drifted");
        if (GridComposition != model.GridComposition) @compileError("GridComposition facade drifted");
        if (LayoutBlock != model.LayoutBlock) @compileError("LayoutBlock facade drifted");
        if (Layout != model.Layout) @compileError("Layout facade drifted");
        if (LayoutLibrarySummary != model.LayoutLibrarySummary) @compileError("LayoutLibrarySummary facade drifted");
        if (LayoutLibrary != model.LayoutLibrary) @compileError("LayoutLibrary facade drifted");
        if (FragmentCell != model.FragmentCell) @compileError("FragmentCell facade drifted");
        if (FragmentSummary != model.FragmentSummary) @compileError("FragmentSummary facade drifted");
        if (Fragment != model.Fragment) @compileError("Fragment facade drifted");
        if (FragmentLibrarySummary != model.FragmentLibrarySummary) @compileError("FragmentLibrarySummary facade drifted");
        if (FragmentLibrary != model.FragmentLibrary) @compileError("FragmentLibrary facade drifted");
        if (brick_preview_swatch_side != model.brick_preview_swatch_side) @compileError("brick_preview_swatch_side facade drifted");
        if (brick_preview_swatch_pixel_count != model.brick_preview_swatch_pixel_count) @compileError("brick_preview_swatch_pixel_count facade drifted");
        if (BrickSwatchPixel != model.BrickSwatchPixel) @compileError("BrickSwatchPixel facade drifted");
        if (BrickPreviewSummary != model.BrickPreviewSummary) @compileError("BrickPreviewSummary facade drifted");
        if (BrickPreview != model.BrickPreview) @compileError("BrickPreview facade drifted");
        if (BrickPreviewLibrarySummary != model.BrickPreviewLibrarySummary) @compileError("BrickPreviewLibrarySummary facade drifted");
        if (BrickPreviewLibrary != model.BrickPreviewLibrary) @compileError("BrickPreviewLibrary facade drifted");
        if (BackgroundCompositionSummary != model.BackgroundCompositionSummary) @compileError("BackgroundCompositionSummary facade drifted");
        if (BackgroundTopologyCompositionSummary != model.BackgroundTopologyCompositionSummary) @compileError("BackgroundTopologyCompositionSummary facade drifted");
        if (BackgroundTopologyComposition != model.BackgroundTopologyComposition) @compileError("BackgroundTopologyComposition facade drifted");
        if (BackgroundComposition != model.BackgroundComposition) @compileError("BackgroundComposition facade drifted");
        if (BackgroundTopologyMetadata != model.BackgroundTopologyMetadata) @compileError("BackgroundTopologyMetadata facade drifted");
        if (BackgroundMetadata != model.BackgroundMetadata) @compileError("BackgroundMetadata facade drifted");
    }
}

test {
    _ = @import("background/tests.zig");
}

const std = @import("std");
const model = @import("background/model.zig");
const parser = @import("background/parser.zig");

pub const BkgHeader = model.BkgHeader;
pub const TabAllCubeEntry = model.TabAllCubeEntry;
pub const GriHeader = model.GriHeader;
pub const UsedBlockSummary = model.UsedBlockSummary;
pub const ColumnTableMetadata = model.ColumnTableMetadata;
pub const BllTableMetadata = model.BllTableMetadata;
pub const BackgroundMetadata = model.BackgroundMetadata;

pub const loadBackgroundMetadata = parser.loadBackgroundMetadata;

test "background facade reexports the stable public API" {
    comptime {
        if (BkgHeader != model.BkgHeader) @compileError("BkgHeader facade drifted");
        if (TabAllCubeEntry != model.TabAllCubeEntry) @compileError("TabAllCubeEntry facade drifted");
        if (GriHeader != model.GriHeader) @compileError("GriHeader facade drifted");
        if (UsedBlockSummary != model.UsedBlockSummary) @compileError("UsedBlockSummary facade drifted");
        if (ColumnTableMetadata != model.ColumnTableMetadata) @compileError("ColumnTableMetadata facade drifted");
        if (BllTableMetadata != model.BllTableMetadata) @compileError("BllTableMetadata facade drifted");
        if (BackgroundMetadata != model.BackgroundMetadata) @compileError("BackgroundMetadata facade drifted");
    }
}

test {
    _ = @import("background/tests.zig");
}

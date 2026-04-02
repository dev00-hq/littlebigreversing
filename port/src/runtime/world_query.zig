const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const room_state = @import("room_state.zig");

pub const world_grid_span_xz: i32 = 512;
pub const world_grid_span_y: i32 = 256;
const world_grid_span_xz_usize: usize = 512;

pub const GridCell = struct {
    x: usize,
    z: usize,
};

pub const GridBounds = struct {
    width: usize,
    depth: usize,
    occupied_bounds: ?room_state.CompositionBoundsSnapshot,
};

pub const CellTopSurface = struct {
    cell: GridCell,
    total_height: u8,
    top_y: i32,
    stack_depth: u8,
    top_floor_type: u8,
    top_shape: u8,
    top_shape_class: room_state.SurfaceShapeClass,
    top_brick_index: u16,
};

pub const Standability = enum {
    standable,
    blocked,
};

pub const HeroStartStatus = enum {
    exact,
    resolved,
};

pub const HeroStartResolution = struct {
    status: HeroStartStatus,
    raw_world_position: room_state.WorldPointSnapshot,
    world_position: room_state.WorldPointSnapshot,
    cell: GridCell,
    surface: CellTopSurface,
    standability: Standability,
};

pub const WorldQuery = struct {
    room: *const room_state.RoomSnapshot,

    pub fn init(room: *const room_state.RoomSnapshot) WorldQuery {
        return .{ .room = room };
    }

    pub fn gridBounds(self: WorldQuery) GridBounds {
        return .{
            .width = self.room.background.column_table.width,
            .depth = self.room.background.column_table.depth,
            .occupied_bounds = self.room.background.composition.occupied_bounds,
        };
    }

    pub fn roomWorldBounds(self: WorldQuery) room_state.WorldBounds {
        const bounds = self.gridBounds();
        return .{
            .min_x = 0,
            .max_x = worldAxisMax(bounds.width),
            .min_z = 0,
            .max_z = worldAxisMax(bounds.depth),
        };
    }

    pub fn containsCell(self: WorldQuery, x: usize, z: usize) bool {
        const bounds = self.gridBounds();
        return x < bounds.width and z < bounds.depth;
    }

    pub fn isOccupiedCell(self: WorldQuery, x: usize, z: usize) !bool {
        const cell_index = try self.cellIndex(x, z);
        return self.room.background.composition.height_grid[cell_index] > 0;
    }

    pub fn cellWorldBounds(self: WorldQuery, x: usize, z: usize) !room_state.WorldBounds {
        _ = try self.cellIndex(x, z);
        return gridCellWorldBounds(x, z);
    }

    pub fn gridCellAtWorldPoint(self: WorldQuery, world_x: i32, world_z: i32) !GridCell {
        if (world_x < 0 or world_z < 0) return error.WorldPointOutOfBounds;

        const cell_x: usize = @intCast(@divFloor(world_x, world_grid_span_xz));
        const cell_z: usize = @intCast(@divFloor(world_z, world_grid_span_xz));
        _ = try self.cellIndex(cell_x, cell_z);

        return .{
            .x = cell_x,
            .z = cell_z,
        };
    }

    pub fn cellTopSurface(self: WorldQuery, x: usize, z: usize) !CellTopSurface {
        const cell_index = try self.cellIndex(x, z);
        const total_height = self.room.background.composition.height_grid[cell_index];
        if (total_height == 0) return error.WorldCellEmpty;

        const tile = self.findCompositionTile(x, z) orelse return error.WorldCellMissingTopSurface;
        return .{
            .cell = .{ .x = x, .z = z },
            .total_height = total_height,
            .top_y = topSurfaceY(total_height),
            .stack_depth = tile.stack_depth,
            .top_floor_type = tile.top_floor_type,
            .top_shape = tile.top_shape,
            .top_shape_class = tile.top_shape_class,
            .top_brick_index = tile.top_brick_index,
        };
    }

    pub fn standabilityAtCell(self: WorldQuery, x: usize, z: usize) !Standability {
        return standabilityForSurface(try self.cellTopSurface(x, z));
    }

    pub fn resolveHeroStart(self: WorldQuery) !HeroStartResolution {
        const hero_position = room_state.WorldPointSnapshot{
            .x = self.room.scene.hero_start.x,
            .y = self.room.scene.hero_start.y,
            .z = self.room.scene.hero_start.z,
        };
        if (self.tryResolveExactHeroStart(hero_position)) |resolution| return resolution;

        const fallback = try self.findNearestStandableCell(hero_position.x, hero_position.z);
        const fallback_bounds = gridCellWorldBounds(fallback.cell.x, fallback.cell.z);
        return .{
            .status = .resolved,
            .raw_world_position = hero_position,
            .world_position = .{
                .x = std.math.clamp(hero_position.x, fallback_bounds.min_x, fallback_bounds.max_x),
                .y = fallback.surface.top_y,
                .z = std.math.clamp(hero_position.z, fallback_bounds.min_z, fallback_bounds.max_z),
            },
            .cell = fallback.cell,
            .surface = fallback.surface,
            .standability = fallback.standability,
        };
    }

    pub fn validateHeroStart(self: WorldQuery) !HeroStartResolution {
        const resolution = try self.resolveHeroStart();
        if (resolution.status != .exact) return error.HeroStartRequiresResolution;
        if (resolution.standability != .standable) return error.HeroStartNotStandable;
        if (resolution.world_position.y != resolution.surface.top_y) return error.HeroStartSurfaceHeightMismatch;
        return resolution;
    }

    fn cellIndex(self: WorldQuery, x: usize, z: usize) !usize {
        const bounds = self.gridBounds();
        if (x >= bounds.width or z >= bounds.depth) return error.WorldCellOutOfBounds;
        return (z * bounds.width) + x;
    }

    fn findCompositionTile(self: WorldQuery, x: usize, z: usize) ?room_state.CompositionTileSnapshot {
        for (self.room.background.composition.tiles) |tile| {
            if (tile.x == x and tile.z == z) return tile;
        }
        return null;
    }

    fn tryResolveExactHeroStart(
        self: WorldQuery,
        hero_position: room_state.WorldPointSnapshot,
    ) ?HeroStartResolution {
        const cell = self.gridCellAtWorldPoint(hero_position.x, hero_position.z) catch return null;
        const surface = self.cellTopSurface(cell.x, cell.z) catch return null;
        const standability = standabilityForSurface(surface);
        if (standability != .standable) return null;
        if (hero_position.y != surface.top_y) return null;

        return .{
            .status = .exact,
            .raw_world_position = hero_position,
            .world_position = hero_position,
            .cell = cell,
            .surface = surface,
            .standability = standability,
        };
    }

    fn findNearestStandableCell(self: WorldQuery, world_x: i32, world_z: i32) !struct {
        cell: GridCell,
        surface: CellTopSurface,
        standability: Standability,
    } {
        var best: ?struct {
            cell: GridCell,
            surface: CellTopSurface,
            standability: Standability,
            distance_sq: i64,
        } = null;

        for (self.room.background.composition.tiles) |tile| {
            const surface = try self.cellTopSurface(tile.x, tile.z);
            const standability = standabilityForSurface(surface);
            if (standability != .standable) continue;

            const cell = GridCell{ .x = tile.x, .z = tile.z };
            const bounds = gridCellWorldBounds(cell.x, cell.z);
            const dx = axisDistanceToBounds(world_x, bounds.min_x, bounds.max_x);
            const dz = axisDistanceToBounds(world_z, bounds.min_z, bounds.max_z);
            const distance_sq = (@as(i64, dx) * @as(i64, dx)) + (@as(i64, dz) * @as(i64, dz));

            if (best == null or distance_sq < best.?.distance_sq or (distance_sq == best.?.distance_sq and lessThanCell(cell, best.?.cell))) {
                best = .{
                    .cell = cell,
                    .surface = surface,
                    .standability = standability,
                    .distance_sq = distance_sq,
                };
            }
        }

        const resolved = best orelse return error.HeroStartNoStandableCell;
        return .{
            .cell = resolved.cell,
            .surface = resolved.surface,
            .standability = resolved.standability,
        };
    }
};

pub fn init(room: *const room_state.RoomSnapshot) WorldQuery {
    return WorldQuery.init(room);
}

pub fn gridCellWorldBounds(x: usize, z: usize) room_state.WorldBounds {
    const x_min: i32 = @intCast(x * world_grid_span_xz_usize);
    const z_min: i32 = @intCast(z * world_grid_span_xz_usize);
    const cell_span: i32 = world_grid_span_xz - 1;
    return .{
        .min_x = x_min,
        .max_x = x_min + cell_span,
        .min_z = z_min,
        .max_z = z_min + cell_span,
    };
}

pub fn standabilityForSurface(surface: CellTopSurface) Standability {
    return switch (surface.top_shape_class) {
        .solid,
        .single_stair,
        .double_stair_corner,
        .double_stair_peak,
        => .standable,
        .open,
        .weird,
        => .blocked,
    };
}

fn topSurfaceY(total_height: u8) i32 {
    return @as(i32, total_height) * world_grid_span_y;
}

fn axisDistanceToBounds(value: i32, min_value: i32, max_value: i32) i32 {
    if (value < min_value) return min_value - value;
    if (value > max_value) return value - max_value;
    return 0;
}

fn lessThanCell(left: GridCell, right: GridCell) bool {
    if (left.z != right.z) return left.z < right.z;
    return left.x < right.x;
}

fn worldAxisMax(cell_count: usize) i32 {
    if (cell_count == 0) return 0;
    return @intCast((cell_count * world_grid_span_xz_usize) - 1);
}

test "runtime world query consumes the guarded room snapshot for base topology queries" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    const query = init(&room);
    const occupied_tile = room.background.composition.tiles[0];
    const surface = try query.cellTopSurface(occupied_tile.x, occupied_tile.z);

    try std.testing.expectEqual(GridBounds{
        .width = 64,
        .depth = 64,
        .occupied_bounds = .{
            .min_x = 39,
            .max_x = 63,
            .min_z = 6,
            .max_z = 58,
        },
    }, query.gridBounds());
    try std.testing.expectEqual(room_state.WorldBounds{
        .min_x = 0,
        .max_x = 32767,
        .min_z = 0,
        .max_z = 32767,
    }, query.roomWorldBounds());
    try std.testing.expect(try query.isOccupiedCell(occupied_tile.x, occupied_tile.z));
    try std.testing.expectEqual(occupied_tile.x, surface.cell.x);
    try std.testing.expectEqual(occupied_tile.z, surface.cell.z);
    try std.testing.expectEqual(occupied_tile.total_height, surface.total_height);
    try std.testing.expectEqual(occupied_tile.stack_depth, surface.stack_depth);
    try std.testing.expectEqual(occupied_tile.top_floor_type, surface.top_floor_type);
    try std.testing.expectEqual(occupied_tile.top_shape, surface.top_shape);
    try std.testing.expectEqual(occupied_tile.top_shape_class, surface.top_shape_class);
    try std.testing.expectEqual(occupied_tile.top_brick_index, surface.top_brick_index);
}

test "runtime world query rejects empty and out-of-bounds cells explicitly" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    const query = init(&room);

    try std.testing.expectEqual(false, try query.isOccupiedCell(0, 0));
    try std.testing.expectError(error.WorldCellEmpty, query.cellTopSurface(0, 0));
    try std.testing.expectError(error.WorldCellOutOfBounds, query.cellTopSurface(64, 0));
    try std.testing.expectError(error.WorldPointOutOfBounds, query.gridCellAtWorldPoint(-1, 0));
}

test "runtime world query resolves the supported hero start against immutable room topology only" {
    const allocator = std.testing.allocator;
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    const room = try room_state.loadRoomSnapshot(allocator, resolved, 19, 19);
    defer room.deinit(allocator);

    const query = init(&room);
    try std.testing.expectError(error.HeroStartRequiresResolution, query.validateHeroStart());

    const hero_start = try query.resolveHeroStart();
    const cell_bounds = try query.cellWorldBounds(hero_start.cell.x, hero_start.cell.z);

    try std.testing.expectEqual(HeroStartStatus.resolved, hero_start.status);
    try std.testing.expectEqual(Standability.standable, try query.standabilityAtCell(hero_start.cell.x, hero_start.cell.z));
    try std.testing.expectEqual(@as(i32, 1987), hero_start.raw_world_position.x);
    try std.testing.expectEqual(@as(i32, 512), hero_start.raw_world_position.y);
    try std.testing.expectEqual(@as(i32, 3743), hero_start.raw_world_position.z);
    try std.testing.expect(hero_start.world_position.x >= cell_bounds.min_x);
    try std.testing.expect(hero_start.world_position.x <= cell_bounds.max_x);
    try std.testing.expect(hero_start.world_position.z >= cell_bounds.min_z);
    try std.testing.expect(hero_start.world_position.z <= cell_bounds.max_z);
    try std.testing.expectEqual(hero_start.surface.top_y, hero_start.world_position.y);
}

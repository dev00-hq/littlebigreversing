const std = @import("std");

pub const canonical_asset_root_relative = "work/_innoextract_full/Speedrun/Windows/LBA2_cdrom/LBA2";
pub const phase1_work_relative = "work/port/phase1";

pub const ResolvedPaths = struct {
    repo_root: []const u8,
    asset_root: []const u8,
    work_root: []const u8,

    pub fn deinit(self: ResolvedPaths, allocator: std.mem.Allocator) void {
        allocator.free(self.repo_root);
        allocator.free(self.asset_root);
        allocator.free(self.work_root);
    }
};

pub fn resolveFromExecutable(allocator: std.mem.Allocator, asset_root_override: ?[]const u8) !ResolvedPaths {
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);

    const exe_dir = std.fs.path.dirname(exe_path) orelse return error.InvalidExecutablePath;
    const zig_out_dir = std.fs.path.dirname(exe_dir) orelse return error.InvalidExecutablePath;
    const port_dir = std.fs.path.dirname(zig_out_dir) orelse return error.InvalidExecutablePath;
    const repo_dir = std.fs.path.dirname(port_dir) orelse return error.InvalidExecutablePath;

    return resolveFromRepoRoot(allocator, repo_dir, asset_root_override);
}

pub fn resolveFromRepoRoot(
    allocator: std.mem.Allocator,
    repo_root_input: []const u8,
    asset_root_override: ?[]const u8,
) !ResolvedPaths {
    const repo_root = try std.fs.cwd().realpathAlloc(allocator, repo_root_input);
    errdefer allocator.free(repo_root);

    const asset_root = if (asset_root_override) |override|
        try std.fs.cwd().realpathAlloc(allocator, override)
    else blk: {
        const joined = try std.fs.path.join(allocator, &.{ repo_root, canonical_asset_root_relative });
        defer allocator.free(joined);
        break :blk try std.fs.cwd().realpathAlloc(allocator, joined);
    };
    errdefer allocator.free(asset_root);

    const work_root = try std.fs.path.join(allocator, &.{ repo_root, phase1_work_relative });
    errdefer allocator.free(work_root);

    return .{
        .repo_root = repo_root,
        .asset_root = asset_root,
        .work_root = work_root,
    };
}

pub fn ensurePhase1WorkDirs(allocator: std.mem.Allocator, paths: ResolvedPaths) !void {
    try makePathAbsolute(paths.work_root);

    const extracted = try std.fs.path.join(allocator, &.{ paths.work_root, "extracted" });
    defer allocator.free(extracted);
    try makePathAbsolute(extracted);

    const fixtures = try std.fs.path.join(allocator, &.{ paths.work_root, "fixtures" });
    defer allocator.free(fixtures);
    try makePathAbsolute(fixtures);
}

pub fn makePathAbsolute(absolute_path: []const u8) !void {
    std.fs.makeDirAbsolute(absolute_path) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        error.FileNotFound => {
            const parent = std.fs.path.dirname(absolute_path) orelse return err;
            if (std.mem.eql(u8, parent, absolute_path)) return err;
            try makePathAbsolute(parent);
            std.fs.makeDirAbsolute(absolute_path) catch |mkdir_err| switch (mkdir_err) {
                error.PathAlreadyExists => return,
                else => return mkdir_err,
            };
        },
        else => return err,
    };
}

test "path resolution keeps canonical work root and override" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("assets");
    const repo_root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(repo_root);
    const asset_override = try tmp.dir.realpathAlloc(allocator, "assets");
    defer allocator.free(asset_override);

    const resolved = try resolveFromRepoRoot(allocator, repo_root, asset_override);
    defer resolved.deinit(allocator);

    const expected_work = try std.fs.path.join(allocator, &.{ repo_root, phase1_work_relative });
    defer allocator.free(expected_work);

    try std.testing.expectEqualStrings(repo_root, resolved.repo_root);
    try std.testing.expectEqualStrings(asset_override, resolved.asset_root);
    try std.testing.expectEqualStrings(expected_work, resolved.work_root);
}

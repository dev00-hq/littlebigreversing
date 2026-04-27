const std = @import("std");
const process = @import("process.zig");

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
    const repo_root = try absolutePathAlloc(allocator, repo_root_input);
    errdefer allocator.free(repo_root);

    const asset_root = if (asset_root_override) |override|
        try absolutePathAlloc(allocator, override)
    else blk: {
        const joined = try std.fs.path.join(allocator, &.{ repo_root, canonical_asset_root_relative });
        defer allocator.free(joined);
        break :blk try absolutePathAlloc(allocator, joined);
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
    std.fs.cwd().makePath(absolute_path) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
}

fn absolutePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return allocator.dupe(u8, path);
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    return std.fs.path.join(allocator, &.{ cwd, path });
}

fn tempDirAbsolutePathAlloc(allocator: std.mem.Allocator, tmp: *const std.testing.TmpDir, sub_path: []const u8) ![]u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    return std.fs.path.join(allocator, &.{ cwd, ".zig-cache", "tmp", &tmp.sub_path, sub_path });
}

test "path resolution keeps canonical work root and override" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("assets");
    const repo_root = try tempDirAbsolutePathAlloc(allocator, &tmp, ".");
    defer allocator.free(repo_root);
    const asset_override = try tempDirAbsolutePathAlloc(allocator, &tmp, "assets");
    defer allocator.free(asset_override);

    const resolved = try resolveFromRepoRoot(allocator, repo_root, asset_override);
    defer resolved.deinit(allocator);

    const expected_work = try std.fs.path.join(allocator, &.{ repo_root, phase1_work_relative });
    defer allocator.free(expected_work);

    try std.testing.expectEqualStrings(repo_root, resolved.repo_root);
    try std.testing.expectEqualStrings(asset_override, resolved.asset_root);
    try std.testing.expectEqualStrings(expected_work, resolved.work_root);
}

const std = @import("std");
const paths_mod = @import("../foundation/paths.zig");
const fixture_bytes = @import("../testing/fixtures.zig");

pub const HqrEntry = struct {
    index: usize,
    offset: u32,
    byte_length: u32,
    sha256: []const u8,

    pub fn deinit(self: HqrEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.sha256);
    }
};

pub const HqrArchive = struct {
    entry_count: usize,
    entries: []HqrEntry,

    pub fn deinit(self: HqrArchive, allocator: std.mem.Allocator) void {
        for (self.entries) |entry| entry.deinit(allocator);
        allocator.free(self.entries);
    }
};

pub const ParsedEntry = struct {
    index: usize,
    offset: u32,
    byte_length: u32,
};

pub fn loadArchive(allocator: std.mem.Allocator, absolute_path: []const u8) !HqrArchive {
    var file = try std.fs.openFileAbsolute(absolute_path, .{});
    defer file.close();

    const size = try file.getEndPos();
    const parsed = try parseTableFromFile(allocator, &file, size);
    defer allocator.free(parsed);

    var entries: std.ArrayList(HqrEntry) = .empty;
    errdefer {
        for (entries.items) |entry| entry.deinit(allocator);
        entries.deinit(allocator);
    }

    for (parsed) |entry| {
        try entries.append(allocator, .{
            .index = entry.index,
            .offset = entry.offset,
            .byte_length = entry.byte_length,
            .sha256 = try hashRangeAlloc(allocator, &file, entry.offset, entry.byte_length),
        });
    }

    return .{
        .entry_count = entries.items.len,
        .entries = try entries.toOwnedSlice(allocator),
    };
}

pub fn extractEntryToBytes(allocator: std.mem.Allocator, absolute_path: []const u8, entry_index: usize) ![]u8 {
    var file = try std.fs.openFileAbsolute(absolute_path, .{});
    defer file.close();

    const size = try file.getEndPos();
    const parsed = try parseTableFromFile(allocator, &file, size);
    defer allocator.free(parsed);

    if (entry_index == 0 or entry_index > parsed.len) return error.EntryIndexOutOfRange;
    const entry = parsed[entry_index - 1];
    const bytes = try allocator.alloc(u8, entry.byte_length);
    errdefer allocator.free(bytes);

    try file.seekTo(entry.offset);
    const read = try file.readAll(bytes);
    if (read != bytes.len) return error.UnexpectedEndOfFile;
    return bytes;
}

pub fn extractEntryToPath(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    entry_index: usize,
    output_path: []const u8,
) ![]const u8 {
    const bytes = try extractEntryToBytes(allocator, absolute_path, entry_index);
    defer allocator.free(bytes);

    if (std.fs.path.dirname(output_path)) |parent| try paths_mod.makePathAbsolute(parent);

    var file = try std.fs.createFileAbsolute(output_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);

    return hashBytesAlloc(allocator, bytes);
}

pub fn sanitizeRelativeAssetPath(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    for (relative_path) |char| {
        switch (char) {
            '/', '\\' => try list.appendSlice(allocator, "__"),
            'A'...'Z', 'a'...'z', '0'...'9', '.', '_', '-' => try list.append(allocator, char),
            else => try list.append(allocator, '_'),
        }
    }

    return list.toOwnedSlice(allocator);
}

pub fn parseTableFromBytes(allocator: std.mem.Allocator, bytes: []const u8) ![]ParsedEntry {
    return parseTable(allocator, bytes.len, struct {
        bytes: []const u8,

        fn readAt(self: @This(), offset: u64, buffer: []u8) !void {
            const start: usize = @intCast(offset);
            const end = start + buffer.len;
            if (end > self.bytes.len) return error.InvalidArchiveOffset;
            @memcpy(buffer, self.bytes[start..end]);
        }
    }{ .bytes = bytes });
}

fn parseTableFromFile(allocator: std.mem.Allocator, file: *std.fs.File, size: u64) ![]ParsedEntry {
    return parseTable(allocator, size, struct {
        file: *std.fs.File,

        fn readAt(self: @This(), offset: u64, buffer: []u8) !void {
            _ = try self.file.preadAll(buffer, offset);
        }
    }{ .file = file });
}

fn parseTable(allocator: std.mem.Allocator, size: u64, reader_ctx: anytype) ![]ParsedEntry {
    if (size < 8) return error.InvalidArchiveSize;

    var header: [4]u8 = undefined;
    try reader_ctx.readAt(0, &header);
    const table_end = std.mem.readInt(u32, &header, .little);
    if (table_end < 8 or table_end % 4 != 0 or table_end > size) return error.InvalidTableHeader;

    const entry_count: usize = @intCast((table_end / 4) - 1);
    var offsets = try allocator.alloc(u32, entry_count);
    defer allocator.free(offsets);

    for (0..entry_count) |index| {
        try reader_ctx.readAt((index + 1) * 4, &header);
        offsets[index] = std.mem.readInt(u32, &header, .little);
    }

    for (offsets) |offset| {
        if (offset == 0) continue;
        if (offset < table_end or offset > size) return error.InvalidArchiveOffset;
    }

    var parsed = try allocator.alloc(ParsedEntry, entry_count);
    errdefer allocator.free(parsed);

    for (0..entry_count) |index| {
        const offset = offsets[index];
        if (offset == 0) {
            parsed[index] = .{ .index = index + 1, .offset = 0, .byte_length = 0 };
            continue;
        }

        var next_offset: u64 = size;
        var search = index + 1;
        while (search < offsets.len) : (search += 1) {
            if (offsets[search] > offset) {
                next_offset = @min(next_offset, offsets[search]);
            }
        }
        if (next_offset < offset) return error.InvalidArchiveOffset;

        parsed[index] = .{
            .index = index + 1,
            .offset = offset,
            .byte_length = @intCast(next_offset - offset),
        };
    }

    return parsed;
}

fn hashRangeAlloc(allocator: std.mem.Allocator, file: *std.fs.File, offset: u32, byte_length: u32) ![]const u8 {
    if (byte_length == 0) return hashBytesAlloc(allocator, "");

    var digest = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [64 * 1024]u8 = undefined;
    var current_offset: u64 = offset;
    var remaining: usize = byte_length;

    while (remaining > 0) {
        const chunk_len = @min(remaining, buffer.len);
        const chunk = buffer[0..chunk_len];
        const read = try file.preadAll(chunk, current_offset);
        digest.update(chunk[0..read]);
        current_offset += read;
        remaining -= read;
    }

    var out: [32]u8 = undefined;
    digest.final(&out);
    const encoded = std.fmt.bytesToHex(out, .lower);
    return allocator.dupe(u8, &encoded);
}

fn hashBytesAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &out, .{});
    const encoded = std.fmt.bytesToHex(out, .lower);
    return allocator.dupe(u8, &encoded);
}

test "parse synthetic archive with empty entry" {
    const allocator = std.testing.allocator;
    const parsed = try parseTableFromBytes(allocator, fixture_bytes.sample_hqr_with_hole[0..]);
    defer allocator.free(parsed);

    try std.testing.expectEqual(@as(usize, 3), parsed.len);
    try std.testing.expectEqual(@as(usize, 1), parsed[0].index);
    try std.testing.expectEqual(@as(u32, 16), parsed[0].offset);
    try std.testing.expectEqual(@as(u32, 4), parsed[0].byte_length);
    try std.testing.expectEqual(@as(usize, 2), parsed[1].index);
    try std.testing.expectEqual(@as(u32, 0), parsed[1].offset);
    try std.testing.expectEqual(@as(u32, 0), parsed[1].byte_length);
    try std.testing.expectEqual(@as(usize, 3), parsed[2].index);
    try std.testing.expectEqual(@as(u32, 20), parsed[2].offset);
    try std.testing.expectEqual(@as(u32, 3), parsed[2].byte_length);
}

test "invalid table header and offsets fail fast" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidTableHeader, parseTableFromBytes(allocator, fixture_bytes.invalid_header_hqr[0..]));
    try std.testing.expectError(error.InvalidArchiveOffset, parseTableFromBytes(allocator, fixture_bytes.invalid_offset_hqr[0..]));
}

test "out of range entry access fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "fixture.hqr", .data = fixture_bytes.sample_hqr_with_hole[0..] });
    const absolute = try tmp.dir.realpathAlloc(allocator, "fixture.hqr");
    defer allocator.free(absolute);

    try std.testing.expectError(error.EntryIndexOutOfRange, extractEntryToBytes(allocator, absolute, 10));
}

test "sanitization cannot keep path separators" {
    const allocator = std.testing.allocator;
    const sanitized = try sanitizeRelativeAssetPath(allocator, "../VIDEO/VIDEO.HQR");
    defer allocator.free(sanitized);

    try std.testing.expectEqualStrings("..__VIDEO__VIDEO.HQR", sanitized);
}

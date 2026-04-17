const std = @import("std");
const builtin = @import("builtin");
const paths_mod = @import("../foundation/paths.zig");
const fixture_bytes = @import("../testing/fixtures.zig");
const asset_fixtures = @import("fixtures.zig");

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

// Reuse one open classic archive plus its offset table across a broader load
// without exposing a copyable resource owner to callers.
pub const ClassicArchiveSession = opaque {
    pub fn init(allocator: std.mem.Allocator, absolute_path: []const u8) !*ClassicArchiveSession {
        var file = try std.fs.openFileAbsolute(absolute_path, .{});
        errdefer file.close();

        const size = try file.getEndPos();
        const table = try loadClassicTableFromFile(allocator, &file, size);
        errdefer allocator.free(table.offsets);

        const session_impl = try allocator.create(ClassicArchiveSessionImpl);
        errdefer allocator.destroy(session_impl);

        session_impl.* = .{
            .allocator = allocator,
            .file = file,
            .size = size,
            .table_end = table.table_end,
            .classic_offsets = table.offsets,
        };
        return @ptrCast(session_impl);
    }

    pub fn deinit(self: *ClassicArchiveSession) void {
        const session_impl = self.impl();
        session_impl.allocator.free(session_impl.classic_offsets);
        session_impl.file.close();
        session_impl.allocator.destroy(session_impl);
    }

    pub fn readEntryToBytes(self: *ClassicArchiveSession, allocator: std.mem.Allocator, classic_index: usize) ![]u8 {
        const session_impl = self.impl();
        const entry = try parseClassicEntryRangeFromOffsets(session_impl.size, session_impl.table_end, session_impl.classic_offsets, classic_index);
        return readParsedEntryFromFile(allocator, &session_impl.file, entry);
    }

    fn impl(self: *ClassicArchiveSession) *ClassicArchiveSessionImpl {
        return @ptrCast(@alignCast(self));
    }
};

const ClassicArchiveSessionImpl = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    size: u64,
    table_end: u32,
    classic_offsets: []u32,
};

pub const ResourceHeader = struct {
    size_file: u32,
    compressed_size_file: u32,
    compress_method: u16,
};

const resource_header_size = 10;

// Test binaries repeatedly decode the same real archive entries; cache raw bytes
// by archive path and entry index so broad asset-backed suites stay incremental.
var test_entry_cache_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var test_entry_cache_mutex: std.Thread.Mutex = .{};
var test_entry_cache = std.StringHashMap([]const u8).init(std.heap.page_allocator);

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

pub fn listNonEmptyEntryIndices(allocator: std.mem.Allocator, absolute_path: []const u8) ![]usize {
    var file = try std.fs.openFileAbsolute(absolute_path, .{});
    defer file.close();

    const size = try file.getEndPos();
    const parsed = try parseTableFromFile(allocator, &file, size);
    defer allocator.free(parsed);

    var entry_indices: std.ArrayList(usize) = .empty;
    errdefer entry_indices.deinit(allocator);

    for (parsed) |entry| {
        if (entry.offset == 0 or entry.byte_length == 0) continue;
        try entry_indices.append(allocator, entry.index);
    }

    return entry_indices.toOwnedSlice(allocator);
}

pub fn extractEntryToBytes(allocator: std.mem.Allocator, absolute_path: []const u8, entry_index: usize) ![]u8 {
    if (builtin.is_test) return extractEntryToBytesMemoized(allocator, absolute_path, entry_index);
    return readRawEntryFromFile(allocator, absolute_path, entry_index);
}

pub fn decodeEntryToBytes(allocator: std.mem.Allocator, absolute_path: []const u8, entry_index: usize) ![]u8 {
    const raw_entry = try readRawEntryFromFile(allocator, absolute_path, entry_index);
    defer allocator.free(raw_entry);

    return decodeResourceEntryBytes(allocator, raw_entry);
}

pub fn extractClassicEntryToBytes(allocator: std.mem.Allocator, absolute_path: []const u8, classic_index: usize) ![]u8 {
    if (builtin.is_test) return extractClassicEntryToBytesMemoized(allocator, absolute_path, classic_index);
    return readRawClassicEntryFromFile(allocator, absolute_path, classic_index);
}

pub fn decodeClassicEntryToBytes(allocator: std.mem.Allocator, absolute_path: []const u8, classic_index: usize) ![]u8 {
    const raw_entry = try readRawClassicEntryFromFile(allocator, absolute_path, classic_index);
    defer allocator.free(raw_entry);

    return decodeResourceEntryBytes(allocator, raw_entry);
}

pub fn decodeResourceEntryBytes(allocator: std.mem.Allocator, raw_entry: []const u8) ![]u8 {
    const header = try parseResourceHeader(raw_entry);
    const payload = raw_entry[resource_header_size..];

    switch (header.compress_method) {
        0 => {
            if (payload.len < header.size_file) return error.TruncatedResourcePayload;
            return allocator.dupe(u8, payload[0..header.size_file]);
        },
        1, 2 => {
            if (payload.len < header.compressed_size_file) return error.TruncatedResourcePayload;
            return expandLzAlloc(allocator, payload[0..header.compressed_size_file], header.size_file, header.compress_method + 1);
        },
        else => return error.UnsupportedCompressionMethod,
    }
}

pub fn parseResourceHeader(raw_entry: []const u8) !ResourceHeader {
    if (raw_entry.len < resource_header_size) return error.TruncatedResourceHeader;

    return .{
        .size_file = std.mem.readInt(u32, raw_entry[0..4], .little),
        .compressed_size_file = std.mem.readInt(u32, raw_entry[4..8], .little),
        .compress_method = std.mem.readInt(u16, raw_entry[8..10], .little),
    };
}

fn readRawEntryFromFile(allocator: std.mem.Allocator, absolute_path: []const u8, entry_index: usize) ![]u8 {
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

fn extractEntryToBytesMemoized(allocator: std.mem.Allocator, absolute_path: []const u8, entry_index: usize) ![]u8 {
    return extractEntryToBytesCachedByKind(allocator, absolute_path, entry_index, .raw);
}

fn extractClassicEntryToBytesMemoized(allocator: std.mem.Allocator, absolute_path: []const u8, classic_index: usize) ![]u8 {
    return extractEntryToBytesCachedByKind(allocator, absolute_path, classic_index, .classic);
}

const CachedEntryKind = enum {
    raw,
    classic,
};

fn buildCachedEntryKeyAlloc(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    entry_index: usize,
    kind: CachedEntryKind,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}:{s}:{d}", .{ @tagName(kind), absolute_path, entry_index });
}

fn extractEntryToBytesCachedByKind(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    entry_index: usize,
    kind: CachedEntryKind,
) ![]u8 {
    const lookup_key = try buildCachedEntryKeyAlloc(allocator, absolute_path, entry_index, kind);
    defer allocator.free(lookup_key);

    test_entry_cache_mutex.lock();
    if (test_entry_cache.get(lookup_key)) |cached| {
        test_entry_cache_mutex.unlock();
        return allocator.dupe(u8, cached);
    }
    test_entry_cache_mutex.unlock();

    const bytes = switch (kind) {
        .raw => try readRawEntryFromFile(allocator, absolute_path, entry_index),
        .classic => try readRawClassicEntryFromFile(allocator, absolute_path, entry_index),
    };
    errdefer allocator.free(bytes);

    test_entry_cache_mutex.lock();
    defer test_entry_cache_mutex.unlock();
    if (test_entry_cache.get(lookup_key)) |cached| {
        allocator.free(bytes);
        return allocator.dupe(u8, cached);
    }

    const cache_allocator = test_entry_cache_arena.allocator();
    const owned_key = try cache_allocator.dupe(u8, lookup_key);
    const owned_bytes = try cache_allocator.dupe(u8, bytes);
    try test_entry_cache.put(owned_key, owned_bytes);
    return bytes;
}

fn readRawClassicEntryFromFile(allocator: std.mem.Allocator, absolute_path: []const u8, classic_index: usize) ![]u8 {
    const session = try ClassicArchiveSession.init(allocator, absolute_path);
    defer session.deinit();

    return session.readEntryToBytes(allocator, classic_index);
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

fn parseClassicEntryRangeFromFile(file: *std.fs.File, size: u64, classic_index: usize) !ParsedEntry {
    if (size < 8) return error.InvalidArchiveSize;

    var header: [4]u8 = undefined;
    _ = try file.preadAll(&header, 0);
    const table_end = std.mem.readInt(u32, &header, .little);
    if (table_end < 8 or table_end % 4 != 0 or table_end > size) return error.InvalidTableHeader;

    return parseClassicEntryRangeWithHeader(file, size, table_end, classic_index);
}

const ClassicTable = struct {
    table_end: u32,
    offsets: []u32,
};

fn loadClassicTableFromFile(allocator: std.mem.Allocator, file: *std.fs.File, size: u64) !ClassicTable {
    if (size < 8) return error.InvalidArchiveSize;

    var header: [4]u8 = undefined;
    const header_read = try file.preadAll(&header, 0);
    if (header_read != header.len) return error.UnexpectedEndOfFile;
    const table_end = std.mem.readInt(u32, &header, .little);
    if (table_end < 8 or table_end % 4 != 0 or table_end > size) return error.InvalidTableHeader;

    const table_bytes = try allocator.alloc(u8, @intCast(table_end));
    defer allocator.free(table_bytes);
    const table_read = try file.preadAll(table_bytes, 0);
    if (table_read != table_bytes.len) return error.UnexpectedEndOfFile;

    const entry_count: usize = @intCast(table_end / 4);
    const offsets = try allocator.alloc(u32, entry_count);
    errdefer allocator.free(offsets);

    for (0..entry_count) |index| {
        const base = index * 4;
        offsets[index] = std.mem.readInt(u32, table_bytes[base..][0..4], .little);
    }

    return .{
        .table_end = table_end,
        .offsets = offsets,
    };
}

fn parseClassicEntryRangeWithHeader(file: *std.fs.File, size: u64, table_end: u32, classic_index: usize) !ParsedEntry {
    var header: [4]u8 = undefined;

    const entry_table_offset = @as(u64, @intCast(classic_index)) * 4;
    if (entry_table_offset >= table_end) return error.EntryIndexOutOfRange;

    _ = try file.preadAll(&header, entry_table_offset);
    const offset = std.mem.readInt(u32, &header, .little);
    if (offset == 0) return error.EntryIndexOutOfRange;
    if (offset < table_end or offset > size) return error.InvalidArchiveOffset;

    var next_offset: u64 = size;
    var search_offset = entry_table_offset + 4;
    while (search_offset < table_end) : (search_offset += 4) {
        _ = try file.preadAll(&header, search_offset);
        const candidate = std.mem.readInt(u32, &header, .little);
        if (candidate == 0 or candidate <= offset) continue;
        if (candidate > size) return error.InvalidArchiveOffset;
        next_offset = @min(next_offset, candidate);
    }
    if (next_offset < offset) return error.InvalidArchiveOffset;

    return .{
        .index = classic_index,
        .offset = offset,
        .byte_length = @intCast(next_offset - offset),
    };
}

fn parseClassicEntryRangeFromOffsets(size: u64, table_end: u32, offsets: []const u32, classic_index: usize) !ParsedEntry {
    if (classic_index >= offsets.len) return error.EntryIndexOutOfRange;

    const offset = offsets[classic_index];
    if (offset == 0) return error.EntryIndexOutOfRange;

    const offset_u64: u64 = offset;
    if (offset_u64 < table_end or offset_u64 > size) return error.InvalidArchiveOffset;

    var next_offset: u64 = size;
    for (offsets[classic_index + 1 ..]) |candidate| {
        if (candidate == 0 or candidate <= offset) continue;
        const candidate_u64: u64 = candidate;
        if (candidate_u64 > size) return error.InvalidArchiveOffset;
        next_offset = @min(next_offset, candidate_u64);
    }
    if (next_offset < offset_u64) return error.InvalidArchiveOffset;

    return .{
        .index = classic_index,
        .offset = offset,
        .byte_length = @intCast(next_offset - offset_u64),
    };
}

fn readParsedEntryFromFile(allocator: std.mem.Allocator, file: *std.fs.File, entry: ParsedEntry) ![]u8 {
    const bytes = try allocator.alloc(u8, entry.byte_length);
    errdefer allocator.free(bytes);

    const read = try file.preadAll(bytes, entry.offset);
    if (read != bytes.len) return error.UnexpectedEndOfFile;
    return bytes;
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

fn expandLzAlloc(allocator: std.mem.Allocator, source: []const u8, decompressed_size: u32, min_block_size: u16) ![]u8 {
    const output = try allocator.alloc(u8, decompressed_size);
    errdefer allocator.free(output);

    var src_index: usize = 0;
    var dst_index: usize = 0;

    while (dst_index < output.len) {
        if (src_index >= source.len) return error.TruncatedResourcePayload;
        var info = source[src_index];
        src_index += 1;

        var remaining_bits: u8 = 8;
        while (remaining_bits > 0 and dst_index < output.len) : (remaining_bits -= 1) {
            const is_literal = (info & 1) == 1;
            info >>= 1;

            if (is_literal) {
                if (src_index >= source.len) return error.TruncatedResourcePayload;
                output[dst_index] = source[src_index];
                src_index += 1;
                dst_index += 1;
                continue;
            }

            if (src_index + 1 >= source.len) return error.TruncatedResourcePayload;
            const token = std.mem.readInt(u16, source[src_index .. src_index + 2][0..2], .little);
            src_index += 2;

            const copy_len: usize = @as(usize, token & 0x000F) + min_block_size;
            const backwards: usize = (@as(usize, token >> 4)) + 1;
            if (backwards > dst_index) return error.InvalidResourceBackReference;

            var copy_src = dst_index - backwards;
            for (0..copy_len) |_| {
                if (dst_index >= output.len) break;
                output[dst_index] = output[copy_src];
                dst_index += 1;
                copy_src += 1;
            }
        }
    }

    return output;
}

fn fixtureTargetById(target_id: []const u8) !asset_fixtures.FixtureTarget {
    for (asset_fixtures.fixture_targets) |target| {
        if (std.mem.eql(u8, target.target_id, target_id)) return target;
    }
    return error.MissingFixtureTarget;
}

fn resolveAssetArchivePathForTests(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
    const resolved = try paths_mod.resolveFromRepoRoot(allocator, "..", null);
    defer resolved.deinit(allocator);

    return std.fs.path.join(allocator, &.{ resolved.asset_root, relative_path });
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
    try std.testing.expectError(error.InvalidArchiveSize, parseTableFromBytes(allocator, fixture_bytes.invalid_archive_size_hqr[0..]));
    try std.testing.expectError(error.InvalidTableHeader, parseTableFromBytes(allocator, fixture_bytes.invalid_header_hqr[0..]));
    try std.testing.expectError(error.InvalidArchiveOffset, parseTableFromBytes(allocator, fixture_bytes.invalid_offset_hqr[0..]));
}

test "listNonEmptyEntryIndices skips empty entries" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "fixture.hqr", .data = fixture_bytes.sample_hqr_with_hole[0..] });
    const absolute = try tmp.dir.realpathAlloc(allocator, "fixture.hqr");
    defer allocator.free(absolute);

    const entry_indices = try listNonEmptyEntryIndices(allocator, absolute);
    defer allocator.free(entry_indices);

    try std.testing.expectEqualSlices(usize, &.{ 1, 3 }, entry_indices);
}

test "resource header parsing and decompression follow classic HQR semantics" {
    const allocator = std.testing.allocator;
    const header = try parseResourceHeader(fixture_bytes.compressed_resource_ababa[0..]);

    try std.testing.expectEqual(@as(u32, 5), header.size_file);
    try std.testing.expectEqual(@as(u32, 5), header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 1), header.compress_method);

    const decoded = try decodeResourceEntryBytes(allocator, fixture_bytes.compressed_resource_ababa[0..]);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings("ABABA", decoded);

    const method2_header = try parseResourceHeader(fixture_bytes.compressed_resource_ababa_method2[0..]);
    try std.testing.expectEqual(@as(u16, 2), method2_header.compress_method);

    const method2_decoded = try decodeResourceEntryBytes(allocator, fixture_bytes.compressed_resource_ababa_method2[0..]);
    defer allocator.free(method2_decoded);

    try std.testing.expectEqualStrings("ABABA", method2_decoded);
}

test "real SCENE.HQR entry 2 decompresses through the wrapped resource header" {
    const allocator = std.testing.allocator;
    const target = try fixtureTargetById("interior-room-twinsens-house-scene");
    const archive_path = try resolveAssetArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const raw_entry = try extractEntryToBytes(allocator, archive_path, target.entry_index);
    defer allocator.free(raw_entry);

    const header = try parseResourceHeader(raw_entry);
    try std.testing.expectEqual(@as(u32, 1412), header.size_file);
    try std.testing.expectEqual(@as(u32, 778), header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 1), header.compress_method);
    try std.testing.expect(raw_entry.len >= resource_header_size + header.compressed_size_file);

    const payload = try decodeResourceEntryBytes(allocator, raw_entry);
    defer allocator.free(payload);

    try std.testing.expectEqual(@as(usize, 1412), payload.len);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 12, 0, 0, 0, 0x9E, 0x01, 0x88, 0x00 }, payload[0..11]);
}

test "real SCENE.HQR entry 44 compressed payload expands to the advertised size" {
    const allocator = std.testing.allocator;
    const target = try fixtureTargetById("exterior-area-citadel-tavern-and-shop-scene");
    const archive_path = try resolveAssetArchivePathForTests(allocator, target.asset_path);
    defer allocator.free(archive_path);

    const raw_entry = try extractEntryToBytes(allocator, archive_path, target.entry_index);
    defer allocator.free(raw_entry);

    const header = try parseResourceHeader(raw_entry);
    try std.testing.expectEqual(@as(u32, 9338), header.size_file);
    try std.testing.expectEqual(@as(u32, 5917), header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 1), header.compress_method);

    const payload = try decodeResourceEntryBytes(allocator, raw_entry);
    defer allocator.free(payload);

    try std.testing.expectEqual(@as(usize, 9338), payload.len);
    try std.testing.expectEqualSlices(u8, &.{ 0, 7, 9, 12, 0, 1, 1 }, payload[0..7]);
}

test "classic entry access exposes the skipped header payloads" {
    const allocator = std.testing.allocator;

    const bkg_archive = try resolveAssetArchivePathForTests(allocator, "LBA_BKG.HQR");
    defer allocator.free(bkg_archive);
    const bkg_raw = try extractClassicEntryToBytes(allocator, bkg_archive, 0);
    defer allocator.free(bkg_raw);
    const bkg_header = try parseResourceHeader(bkg_raw);
    const bkg_payload = try decodeClassicEntryToBytes(allocator, bkg_archive, 0);
    defer allocator.free(bkg_payload);

    try std.testing.expectEqual(@as(usize, 38), bkg_raw.len);
    try std.testing.expectEqual(@as(u32, 28), bkg_header.size_file);
    try std.testing.expectEqual(@as(u32, 28), bkg_header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 0), bkg_header.compress_method);
    try std.testing.expectEqual(@as(usize, 28), bkg_payload.len);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bkg_payload[0..2], .little));

    const scene_archive = try resolveAssetArchivePathForTests(allocator, "SCENE.HQR");
    defer allocator.free(scene_archive);
    const scene_raw = try extractClassicEntryToBytes(allocator, scene_archive, 0);
    defer allocator.free(scene_raw);
    const scene_header = try parseResourceHeader(scene_raw);
    const scene_payload = try decodeClassicEntryToBytes(allocator, scene_archive, 0);
    defer allocator.free(scene_payload);

    try std.testing.expectEqual(@as(usize, 14), scene_raw.len);
    try std.testing.expectEqual(@as(u32, 4), scene_header.size_file);
    try std.testing.expectEqual(@as(u32, 4), scene_header.compressed_size_file);
    try std.testing.expectEqual(@as(u16, 0), scene_header.compress_method);
    try std.testing.expectEqual(@as(usize, 4), scene_payload.len);
    try std.testing.expectEqual(@as(u32, 20447), std.mem.readInt(u32, scene_payload[0..4], .little));
}

test "unsupported resource compression fails fast" {
    const allocator = std.testing.allocator;
    const invalid = [_]u8{
        0x04, 0x00, 0x00, 0x00,
        0x04, 0x00, 0x00, 0x00,
        0x09, 0x00, 'T',  'E',
        'S',  'T',
    };

    try std.testing.expectError(error.UnsupportedCompressionMethod, decodeResourceEntryBytes(allocator, invalid[0..]));
}

test "truncated resource entries and invalid back-references fail fast" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(error.TruncatedResourceHeader, parseResourceHeader(fixture_bytes.compressed_resource_ababa[0..9]));
    try std.testing.expectError(error.TruncatedResourcePayload, decodeResourceEntryBytes(allocator, fixture_bytes.truncated_resource_payload[0..]));
    try std.testing.expectError(error.InvalidResourceBackReference, decodeResourceEntryBytes(allocator, fixture_bytes.invalid_resource_back_reference[0..]));
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

test "classic entry access rejects empty and out-of-range synthetic slots" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "fixture.hqr", .data = fixture_bytes.sample_hqr_with_hole[0..] });
    const absolute = try tmp.dir.realpathAlloc(allocator, "fixture.hqr");
    defer allocator.free(absolute);

    try std.testing.expectError(error.EntryIndexOutOfRange, extractClassicEntryToBytes(allocator, absolute, 2));
    try std.testing.expectError(error.EntryIndexOutOfRange, decodeClassicEntryToBytes(allocator, absolute, 4));
}

test "sanitization cannot keep path separators" {
    const allocator = std.testing.allocator;
    const sanitized = try sanitizeRelativeAssetPath(allocator, "../VIDEO/VIDEO.HQR");
    defer allocator.free(sanitized);

    try std.testing.expectEqualStrings("..__VIDEO__VIDEO.HQR", sanitized);
}

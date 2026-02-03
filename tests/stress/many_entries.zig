//! Stress tests: Archives with many entries.
//!
//! Tests archive handling with large numbers of files to verify
//! scalability and correct iteration.

const std = @import("std");
const compressionz = @import("compressionz");
const tar = compressionz.archive.tar;
const zip = compressionz.archive.zip;

const testing = std.testing;

// =============================================================================
// TAR Many Entries Tests
// =============================================================================

test "tar: 100 small files" {
    const allocator = testing.allocator;

    // Calculate buffer size needed
    // Each file: 512 (header) + 512 (data padded) = 1024 bytes
    // Plus 1024 for end blocks
    const buffer_size = 100 * 1024 + 2048;
    const tar_buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(tar_buffer);

    var tar_stream = std.io.fixedBufferStream(tar_buffer);

    // Write 100 files
    var writer = tar.Writer(@TypeOf(&tar_stream)).init(&tar_stream);

    for (0..100) |i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "file_{d:0>3}.txt", .{i}) catch unreachable;

        var content_buf: [32]u8 = undefined;
        const content = std.fmt.bufPrint(&content_buf, "Content of file {d}", .{i}) catch unreachable;

        try writer.addFile(name, content);
    }
    try writer.finish();

    // Read and verify
    const written = tar_stream.getWritten();
    var read_stream = std.io.fixedBufferStream(written);
    var reader = tar.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    var count: usize = 0;
    while (try reader.next()) |entry| {
        const data = try entry.readAll(allocator);
        defer allocator.free(data);

        var expected_buf: [32]u8 = undefined;
        const expected = std.fmt.bufPrint(&expected_buf, "Content of file {d}", .{count}) catch unreachable;
        try testing.expectEqualStrings(expected, data);

        count += 1;
    }

    try testing.expectEqual(@as(usize, 100), count);
}

test "tar: nested directory structure" {
    const allocator = testing.allocator;

    const buffer_size = 50 * 1024;
    const tar_buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(tar_buffer);

    var tar_stream = std.io.fixedBufferStream(tar_buffer);
    var writer = tar.Writer(@TypeOf(&tar_stream)).init(&tar_stream);

    // Create nested structure: a/b/c/d/e/file.txt
    const paths = [_][]const u8{
        "level1/file.txt",
        "level1/level2/file.txt",
        "level1/level2/level3/file.txt",
        "level1/level2/level3/level4/file.txt",
        "level1/level2/level3/level4/level5/file.txt",
    };

    for (paths) |path| {
        try writer.addFile(path, "test");
    }
    try writer.finish();

    // Read and verify paths
    const written = tar_stream.getWritten();
    var read_stream = std.io.fixedBufferStream(written);
    var reader = tar.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    var i: usize = 0;
    while (try reader.next()) |entry| {
        try testing.expectEqualStrings(paths[i], entry.name);
        i += 1;
    }
    try testing.expectEqual(paths.len, i);
}

// =============================================================================
// ZIP Many Entries Tests
// =============================================================================

test "zip: 50 files" {
    const allocator = testing.allocator;

    const buffer_size = 100 * 1024;
    const zip_buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(zip_buffer);

    var zip_stream = std.io.fixedBufferStream(zip_buffer);

    // Write 50 files
    var writer = try zip.Writer(@TypeOf(&zip_stream)).init(allocator, &zip_stream);
    defer writer.deinit();

    for (0..50) |i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "document_{d:0>2}.txt", .{i}) catch unreachable;

        var content_buf: [64]u8 = undefined;
        const content = std.fmt.bufPrint(&content_buf, "This is document number {d}. Some padding text here.", .{i}) catch unreachable;

        try writer.addFile(name, content);
    }
    try writer.finish();

    // Read and verify
    const written = zip_stream.getWritten();
    var read_stream = std.io.fixedBufferStream(written);
    var reader = try zip.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    try testing.expectEqual(@as(usize, 50), try reader.count());

    var count: usize = 0;
    while (try reader.next()) |entry| {
        const data = try entry.readAll(allocator);
        defer allocator.free(data);

        // Verify content starts correctly
        try testing.expect(std.mem.startsWith(u8, data, "This is document number"));
        count += 1;
    }

    try testing.expectEqual(@as(usize, 50), count);
}

test "zip: mixed file sizes" {
    const allocator = testing.allocator;

    const buffer_size = 200 * 1024;
    const zip_buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(zip_buffer);

    var zip_stream = std.io.fixedBufferStream(zip_buffer);

    var writer = try zip.Writer(@TypeOf(&zip_stream)).init(allocator, &zip_stream);
    defer writer.deinit();

    // Write files of various sizes
    const sizes = [_]usize{ 0, 1, 10, 100, 1000, 5000, 10000 };

    for (sizes, 0..) |size, i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "size_{d}.bin", .{size}) catch unreachable;

        const content = try allocator.alloc(u8, size);
        defer allocator.free(content);
        @memset(content, @intCast(i));

        try writer.addFile(name, content);
    }
    try writer.finish();

    // Read and verify sizes
    const written = zip_stream.getWritten();
    var read_stream = std.io.fixedBufferStream(written);
    var reader = try zip.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    var i: usize = 0;
    while (try reader.next()) |entry| {
        const data = try entry.readAll(allocator);
        defer allocator.free(data);

        try testing.expectEqual(sizes[i], data.len);
        i += 1;
    }
}

// =============================================================================
// Edge Cases
// =============================================================================

test "tar: single empty file" {
    const allocator = testing.allocator;

    var tar_buffer: [2048]u8 = undefined;
    var tar_stream = std.io.fixedBufferStream(&tar_buffer);

    var writer = tar.Writer(@TypeOf(&tar_stream)).init(&tar_stream);
    try writer.addFile("empty.txt", "");
    try writer.finish();

    var read_stream = std.io.fixedBufferStream(tar_stream.getWritten());
    var reader = tar.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    const entry = try reader.next();
    try testing.expect(entry != null);
    try testing.expectEqual(@as(u64, 0), entry.?.size);

    try testing.expectEqual(@as(?*tar.Entry, null), try reader.next());
}

test "zip: all empty files" {
    const allocator = testing.allocator;

    var zip_buffer: [8192]u8 = undefined;
    var zip_stream = std.io.fixedBufferStream(&zip_buffer);

    var writer = try zip.Writer(@TypeOf(&zip_stream)).init(allocator, &zip_stream);
    defer writer.deinit();

    for (0..10) |i| {
        var name_buf: [16]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "empty_{d}.txt", .{i}) catch unreachable;
        try writer.addFile(name, "");
    }
    try writer.finish();

    var read_stream = std.io.fixedBufferStream(zip_stream.getWritten());
    var reader = try zip.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    try testing.expectEqual(@as(usize, 10), try reader.count());

    var count: usize = 0;
    while (try reader.next()) |entry| {
        try testing.expectEqual(@as(u32, 0), entry.uncompressed_size);
        count += 1;
    }
    try testing.expectEqual(@as(usize, 10), count);
}

//! Integration tests: Archive write → read with compression.
//!
//! Tests ZIP and TAR archive creation and extraction with various
//! compression methods and file contents.

const std = @import("std");
const compressionz = @import("compressionz");
const tar = compressionz.archive.tar;
const zip = compressionz.archive.zip;

const testing = std.testing;

// =============================================================================
// TAR Archive Tests
// =============================================================================

test "tar: write and read multiple files" {
    const allocator = testing.allocator;

    var tar_buffer: [16384]u8 = undefined;
    var tar_stream = std.io.fixedBufferStream(&tar_buffer);

    // Write archive
    var writer = tar.Writer(@TypeOf(&tar_stream)).init(&tar_stream);

    try writer.addFile("file1.txt", "Hello, World!");
    try writer.addFile("dir/file2.txt", "This is a nested file.\n\n\n");
    try writer.addFile("empty.txt", "");
    try writer.finish();

    // Read archive
    const tar_data = tar_stream.getWritten();
    var read_stream = std.io.fixedBufferStream(tar_data);
    var reader = tar.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    // File 1
    const entry1 = try reader.next();
    try testing.expect(entry1 != null);
    try testing.expectEqualStrings("file1.txt", entry1.?.name);
    const data1 = try entry1.?.readAll(allocator);
    defer allocator.free(data1);
    try testing.expectEqualStrings("Hello, World!", data1);

    // File 2
    const entry2 = try reader.next();
    try testing.expect(entry2 != null);
    try testing.expectEqualStrings("dir/file2.txt", entry2.?.name);

    // File 3 (empty)
    const entry3 = try reader.next();
    try testing.expect(entry3 != null);
    try testing.expectEqualStrings("empty.txt", entry3.?.name);
    try testing.expectEqual(@as(u64, 0), entry3.?.size);

    // End
    try testing.expectEqual(@as(?*tar.Entry, null), try reader.next());
}

test "tar: binary content" {
    const allocator = testing.allocator;

    var tar_buffer: [8192]u8 = undefined;
    var tar_stream = std.io.fixedBufferStream(&tar_buffer);

    // Create binary data
    var binary_data: [512]u8 = undefined;
    for (&binary_data, 0..) |*b, i| {
        b.* = @intCast(i % 256);
    }

    // Write
    var writer = tar.Writer(@TypeOf(&tar_stream)).init(&tar_stream);
    try writer.addFile("binary.bin", &binary_data);
    try writer.finish();

    // Read
    const tar_data = tar_stream.getWritten();
    var read_stream = std.io.fixedBufferStream(tar_data);
    var reader = tar.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    const entry = try reader.next();
    try testing.expect(entry != null);
    const data = try entry.?.readAll(allocator);
    defer allocator.free(data);
    try testing.expectEqualSlices(u8, &binary_data, data);
}

// =============================================================================
// ZIP Archive Tests
// =============================================================================

test "zip: write and read multiple files" {
    const allocator = testing.allocator;

    var zip_buffer: [16384]u8 = undefined;
    var zip_stream = std.io.fixedBufferStream(&zip_buffer);

    // Write archive
    var writer = try zip.Writer(@TypeOf(&zip_stream)).init(allocator, &zip_stream);
    defer writer.deinit();

    try writer.addFile("hello.txt", "Hello from ZIP!");
    try writer.addFile("subdir/nested.txt", "Nested file content");
    try writer.addFile("empty.txt", "");
    try writer.finish();

    // Read archive
    const zip_data = zip_stream.getWritten();
    var read_stream = std.io.fixedBufferStream(zip_data);
    var reader = try zip.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    try testing.expectEqual(@as(usize, 3), try reader.count());

    // Read first file
    if (try reader.next()) |entry| {
        try testing.expectEqualStrings("hello.txt", entry.name);
        const data = try entry.readAll(allocator);
        defer allocator.free(data);
        try testing.expectEqualStrings("Hello from ZIP!", data);
    } else {
        return error.TestFailed;
    }

    // Read second file
    if (try reader.next()) |entry| {
        try testing.expectEqualStrings("subdir/nested.txt", entry.name);
        const data = try entry.readAll(allocator);
        defer allocator.free(data);
        try testing.expectEqualStrings("Nested file content", data);
    } else {
        return error.TestFailed;
    }

    // Read empty file
    if (try reader.next()) |entry| {
        try testing.expectEqualStrings("empty.txt", entry.name);
        try testing.expectEqual(@as(u32, 0), entry.uncompressed_size);
    } else {
        return error.TestFailed;
    }
}

test "zip: compressed content" {
    const allocator = testing.allocator;

    var zip_buffer: [32768]u8 = undefined;
    var zip_stream = std.io.fixedBufferStream(&zip_buffer);

    // Write highly compressible data
    const compressible = "AAAA" ** 1000;

    var writer = try zip.Writer(@TypeOf(&zip_stream)).init(allocator, &zip_stream);
    defer writer.deinit();
    try writer.addFile("compressible.txt", compressible);
    try writer.finish();

    // Read and verify
    const zip_data = zip_stream.getWritten();
    var read_stream = std.io.fixedBufferStream(zip_data);
    var reader = try zip.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    if (try reader.next()) |entry| {
        const data = try entry.readAll(allocator);
        defer allocator.free(data);
        try testing.expectEqualStrings(compressible, data);

        // Verify compression actually happened
        try testing.expect(entry.compressed_size < entry.uncompressed_size);
    } else {
        return error.TestFailed;
    }
}

test "zip: binary content" {
    const allocator = testing.allocator;

    var zip_buffer: [8192]u8 = undefined;
    var zip_stream = std.io.fixedBufferStream(&zip_buffer);

    // Create binary data
    var binary_data: [512]u8 = undefined;
    for (&binary_data, 0..) |*b, i| {
        b.* = @intCast(i % 256);
    }

    // Write
    var writer = try zip.Writer(@TypeOf(&zip_stream)).init(allocator, &zip_stream);
    defer writer.deinit();
    try writer.addFile("binary.bin", &binary_data);
    try writer.finish();

    // Read
    const zip_data = zip_stream.getWritten();
    var read_stream = std.io.fixedBufferStream(zip_data);
    var reader = try zip.Reader(@TypeOf(&read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    if (try reader.next()) |entry| {
        const data = try entry.readAll(allocator);
        defer allocator.free(data);
        try testing.expectEqualSlices(u8, &binary_data, data);
    } else {
        return error.TestFailed;
    }
}

// =============================================================================
// Cross-Format Tests
// =============================================================================

test "same content in tar and zip produces identical decompressed data" {
    const allocator = testing.allocator;
    const content = "This content should be identical in both archives!";

    // Create TAR
    var tar_buffer: [4096]u8 = undefined;
    var tar_stream = std.io.fixedBufferStream(&tar_buffer);
    var tar_writer = tar.Writer(@TypeOf(&tar_stream)).init(&tar_stream);
    try tar_writer.addFile("test.txt", content);
    try tar_writer.finish();

    // Create ZIP
    var zip_buffer: [4096]u8 = undefined;
    var zip_stream = std.io.fixedBufferStream(&zip_buffer);
    var zip_writer = try zip.Writer(@TypeOf(&zip_stream)).init(allocator, &zip_stream);
    defer zip_writer.deinit();
    try zip_writer.addFile("test.txt", content);
    try zip_writer.finish();

    // Read TAR
    var tar_read_stream = std.io.fixedBufferStream(tar_stream.getWritten());
    var tar_reader = tar.Reader(@TypeOf(&tar_read_stream)).init(allocator, &tar_read_stream);
    defer tar_reader.deinit();
    const tar_entry = try tar_reader.next();
    const tar_data = try tar_entry.?.readAll(allocator);
    defer allocator.free(tar_data);

    // Read ZIP
    var zip_read_stream = std.io.fixedBufferStream(zip_stream.getWritten());
    var zip_reader = try zip.Reader(@TypeOf(&zip_read_stream)).init(allocator, &zip_read_stream);
    defer zip_reader.deinit();
    const zip_entry = try zip_reader.next();
    const zip_data = try zip_entry.?.readAll(allocator);
    defer allocator.free(zip_data);

    // Compare
    try testing.expectEqualSlices(u8, tar_data, zip_data);
    try testing.expectEqualStrings(content, tar_data);
}

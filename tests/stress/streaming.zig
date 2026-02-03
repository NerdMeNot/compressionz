//! Stress tests: Streaming API edge cases.
//!
//! Tests streaming compression/decompression with various buffer sizes,
//! chunked I/O patterns, and edge conditions.

const std = @import("std");
const cz = @import("compressionz");

const testing = std.testing;

// =============================================================================
// Small Buffer Read Tests
// =============================================================================

test "streaming: small buffer reads - gzip" {
    const allocator = testing.allocator;
    const input = "Test data for small buffer streaming verification. " ** 100;

    // Compress
    var compressed_buf: [16384]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.gzip.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress with small buffer (8 bytes at a time)
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    var result: std.ArrayListUnmanaged(u8) = .{};
    defer result.deinit(allocator);

    var small_buf: [8]u8 = undefined;
    while (true) {
        const n = try decomp.reader().read(&small_buf);
        if (n == 0) break;
        try result.appendSlice(allocator, small_buf[0..n]);
    }

    try testing.expectEqualStrings(input, result.items);
}

test "streaming: small buffer reads - zstd" {
    const allocator = testing.allocator;
    const input = "Test data for small buffer streaming verification. " ** 100;

    // Compress
    var compressed_buf: [16384]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.zstd.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress with small buffer (8 bytes at a time)
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.zstd.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    var result: std.ArrayListUnmanaged(u8) = .{};
    defer result.deinit(allocator);

    var small_buf: [8]u8 = undefined;
    while (true) {
        const n = try decomp.reader().read(&small_buf);
        if (n == 0) break;
        try result.appendSlice(allocator, small_buf[0..n]);
    }

    try testing.expectEqualStrings(input, result.items);
}

test "streaming: small buffer reads - lz4" {
    const allocator = testing.allocator;
    const input = "Test data for small buffer streaming verification. " ** 100;

    // Compress
    var compressed_buf: [16384]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.lz4.frame.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress with small buffer (8 bytes at a time)
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.lz4.frame.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader(), .{});
    defer decomp.deinit();

    var result: std.ArrayListUnmanaged(u8) = .{};
    defer result.deinit(allocator);

    var small_buf: [8]u8 = undefined;
    while (true) {
        const n = try decomp.reader().read(&small_buf);
        if (n == 0) break;
        try result.appendSlice(allocator, small_buf[0..n]);
    }

    try testing.expectEqualStrings(input, result.items);
}

test "streaming: small buffer reads - zlib" {
    const allocator = testing.allocator;
    const input = "Test data for small buffer streaming verification. " ** 100;

    // Compress
    var compressed_buf: [16384]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.zlib.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress with small buffer (8 bytes at a time)
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.zlib.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    var result: std.ArrayListUnmanaged(u8) = .{};
    defer result.deinit(allocator);

    var small_buf: [8]u8 = undefined;
    while (true) {
        const n = try decomp.reader().read(&small_buf);
        if (n == 0) break;
        try result.appendSlice(allocator, small_buf[0..n]);
    }

    try testing.expectEqualStrings(input, result.items);
}

test "streaming: single byte reads - gzip" {
    const allocator = testing.allocator;
    const input = "Byte by byte reading test data.";

    // Compress
    var compressed_buf: [1024]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.gzip.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress one byte at a time
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    var result: std.ArrayListUnmanaged(u8) = .{};
    defer result.deinit(allocator);

    while (true) {
        const byte = decomp.reader().readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        try result.append(allocator, byte);
    }

    try testing.expectEqualStrings(input, result.items);
}

// =============================================================================
// Small Buffer Write Tests
// =============================================================================

test "streaming: byte-by-byte writes - gzip" {
    const allocator = testing.allocator;
    const input = "Writing one byte at a time!";

    var compressed_buf: [1024]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.gzip.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();

    // Write one byte at a time
    for (input) |byte| {
        try comp.writer().writeByte(byte);
    }
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress and verify
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);

    try testing.expectEqualStrings(input, output);
}

test "streaming: byte-by-byte writes - zstd" {
    const allocator = testing.allocator;
    const input = "Writing one byte at a time!";

    var compressed_buf: [1024]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.zstd.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();

    // Write one byte at a time
    for (input) |byte| {
        try comp.writer().writeByte(byte);
    }
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress and verify
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.zstd.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);

    try testing.expectEqualStrings(input, output);
}

test "streaming: byte-by-byte writes - lz4" {
    const allocator = testing.allocator;
    const input = "Writing one byte at a time!";

    var compressed_buf: [1024]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.lz4.frame.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();

    // Write one byte at a time
    for (input) |byte| {
        try comp.writer().writeByte(byte);
    }
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress and verify
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.lz4.frame.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader(), .{});
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);

    try testing.expectEqualStrings(input, output);
}

test "streaming: variable chunk writes - gzip" {
    const allocator = testing.allocator;
    const input = "Variable chunk size writing test with enough data to span multiple chunks. " ** 20;

    var compressed_buf: [8192]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.gzip.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();

    // Write in variable chunk sizes: 1, 3, 7, 15, 31, 63, ...
    var offset: usize = 0;
    var chunk_size: usize = 1;
    while (offset < input.len) {
        const end = @min(offset + chunk_size, input.len);
        try comp.writer().writeAll(input[offset..end]);
        offset = end;
        chunk_size = @min(chunk_size * 2 + 1, 127);
    }
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress and verify
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(output);

    try testing.expectEqualStrings(input, output);
}

// =============================================================================
// Large Streaming Data Tests
// =============================================================================

test "streaming: large data 100KB - gzip" {
    const allocator = testing.allocator;

    // Generate 100KB of patterned data
    const input = try allocator.alloc(u8, 100 * 1024);
    defer allocator.free(input);
    for (input, 0..) |*b, i| {
        b.* = @intCast((i * 7 + 13) % 256);
    }

    // Compress to dynamic buffer
    var compressed: std.ArrayListUnmanaged(u8) = .{};
    defer compressed.deinit(allocator);

    var comp = try cz.gzip.Compressor(std.ArrayListUnmanaged(u8).Writer).init(allocator, compressed.writer(allocator), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    // Decompress
    var fbs = std.io.fixedBufferStream(compressed.items);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 200 * 1024);
    defer allocator.free(output);

    try testing.expectEqualSlices(u8, input, output);
}

test "streaming: large data 100KB - zstd" {
    const allocator = testing.allocator;

    // Generate 100KB of patterned data
    const input = try allocator.alloc(u8, 100 * 1024);
    defer allocator.free(input);
    for (input, 0..) |*b, i| {
        b.* = @intCast((i * 7 + 13) % 256);
    }

    // Compress to dynamic buffer
    var compressed: std.ArrayListUnmanaged(u8) = .{};
    defer compressed.deinit(allocator);

    var comp = try cz.zstd.Compressor(std.ArrayListUnmanaged(u8).Writer).init(allocator, compressed.writer(allocator), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    // Decompress
    var fbs = std.io.fixedBufferStream(compressed.items);
    var decomp = try cz.zstd.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 200 * 1024);
    defer allocator.free(output);

    try testing.expectEqualSlices(u8, input, output);
}

test "streaming: large data 100KB - lz4" {
    const allocator = testing.allocator;

    // Generate 100KB of patterned data
    const input = try allocator.alloc(u8, 100 * 1024);
    defer allocator.free(input);
    for (input, 0..) |*b, i| {
        b.* = @intCast((i * 7 + 13) % 256);
    }

    // Compress to dynamic buffer
    var compressed: std.ArrayListUnmanaged(u8) = .{};
    defer compressed.deinit(allocator);

    var comp = try cz.lz4.frame.Compressor(std.ArrayListUnmanaged(u8).Writer).init(allocator, compressed.writer(allocator), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    // Decompress
    var fbs = std.io.fixedBufferStream(compressed.items);
    var decomp = try cz.lz4.frame.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader(), .{});
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 200 * 1024);
    defer allocator.free(output);

    try testing.expectEqualSlices(u8, input, output);
}

test "streaming: highly compressible data - gzip" {
    const allocator = testing.allocator;

    // 50KB of zeros - should compress very well
    const input = try allocator.alloc(u8, 50 * 1024);
    defer allocator.free(input);
    @memset(input, 0);

    var compressed: std.ArrayListUnmanaged(u8) = .{};
    defer compressed.deinit(allocator);

    var comp = try cz.gzip.Compressor(std.ArrayListUnmanaged(u8).Writer).init(allocator, compressed.writer(allocator), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    // Should achieve good compression
    try testing.expect(compressed.items.len < input.len / 10);

    // Decompress and verify
    var fbs = std.io.fixedBufferStream(compressed.items);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 100 * 1024);
    defer allocator.free(output);

    try testing.expectEqualSlices(u8, input, output);
}

test "streaming: incompressible random data - gzip" {
    const allocator = testing.allocator;

    // Generate pseudo-random data (incompressible)
    const input = try allocator.alloc(u8, 10 * 1024);
    defer allocator.free(input);
    var rng = std.Random.DefaultPrng.init(12345);
    rng.fill(input);

    var compressed: std.ArrayListUnmanaged(u8) = .{};
    defer compressed.deinit(allocator);

    var comp = try cz.gzip.Compressor(std.ArrayListUnmanaged(u8).Writer).init(allocator, compressed.writer(allocator), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    // Decompress and verify
    var fbs = std.io.fixedBufferStream(compressed.items);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 20 * 1024);
    defer allocator.free(output);

    try testing.expectEqualSlices(u8, input, output);
}

// =============================================================================
// Edge Cases
// =============================================================================

test "streaming: read after EOF returns zero - gzip" {
    const allocator = testing.allocator;
    const input = "Short data";

    var compressed_buf: [256]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.gzip.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    // Read all data
    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);
    try testing.expectEqualStrings(input, output);

    // Additional reads should return 0
    var extra_buf: [16]u8 = undefined;
    const n1 = try decomp.reader().read(&extra_buf);
    try testing.expectEqual(@as(usize, 0), n1);

    // Multiple reads after EOF still return 0
    const n2 = try decomp.reader().read(&extra_buf);
    try testing.expectEqual(@as(usize, 0), n2);
}

test "streaming: read after EOF returns zero - zstd" {
    const allocator = testing.allocator;
    const input = "Short data";

    var compressed_buf: [256]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.zstd.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.zstd.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    // Read all data
    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);
    try testing.expectEqualStrings(input, output);

    // Additional reads should return 0
    var extra_buf: [16]u8 = undefined;
    const n1 = try decomp.reader().read(&extra_buf);
    try testing.expectEqual(@as(usize, 0), n1);

    // Multiple reads after EOF still return 0
    const n2 = try decomp.reader().read(&extra_buf);
    try testing.expectEqual(@as(usize, 0), n2);
}

test "streaming: read after EOF returns zero - lz4" {
    const allocator = testing.allocator;
    const input = "Short data";

    var compressed_buf: [256]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.lz4.frame.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.lz4.frame.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader(), .{});
    defer decomp.deinit();

    // Read all data
    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);
    try testing.expectEqualStrings(input, output);

    // Additional reads should return 0
    var extra_buf: [16]u8 = undefined;
    const n1 = try decomp.reader().read(&extra_buf);
    try testing.expectEqual(@as(usize, 0), n1);

    // Multiple reads after EOF still return 0
    const n2 = try decomp.reader().read(&extra_buf);
    try testing.expectEqual(@as(usize, 0), n2);
}

test "streaming: multiple small writes then single large read - gzip" {
    const allocator = testing.allocator;

    var compressed: std.ArrayListUnmanaged(u8) = .{};
    defer compressed.deinit(allocator);

    var comp = try cz.gzip.Compressor(std.ArrayListUnmanaged(u8).Writer).init(allocator, compressed.writer(allocator), .{});
    defer comp.deinit();

    // Many small writes
    for (0..100) |i| {
        var buf: [10]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, "Line {:0>3}\n", .{i}) catch unreachable;
        try comp.writer().writeAll(written);
    }
    try comp.finish();

    // Single large read
    var fbs = std.io.fixedBufferStream(compressed.items);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(output);

    // Verify content
    try testing.expectEqual(@as(usize, 900), output.len); // 100 lines * 9 bytes each
    try testing.expect(std.mem.startsWith(u8, output, "Line 000\n"));
    try testing.expect(std.mem.endsWith(u8, output, "Line 099\n"));
}

test "streaming: finish without any writes - gzip" {
    const allocator = testing.allocator;

    var compressed_buf: [256]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.gzip.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    // No writes, just finish
    try comp.finish();

    const compressed = compressed_stream.getWritten();
    try testing.expect(compressed.len > 0); // Should produce valid empty stream

    // Should decompress to empty
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);

    try testing.expectEqual(@as(usize, 0), output.len);
}

test "streaming: finish without any writes - zstd" {
    const allocator = testing.allocator;

    var compressed_buf: [256]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.zstd.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    // No writes, just finish
    try comp.finish();

    const compressed = compressed_stream.getWritten();
    try testing.expect(compressed.len > 0); // Should produce valid empty stream

    // Should decompress to empty
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.zstd.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);

    try testing.expectEqual(@as(usize, 0), output.len);
}

test "streaming: finish without any writes - lz4" {
    const allocator = testing.allocator;

    var compressed_buf: [256]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try cz.lz4.frame.Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    // No writes, just finish
    try comp.finish();

    const compressed = compressed_stream.getWritten();
    try testing.expect(compressed.len > 0); // Should produce valid empty stream

    // Should decompress to empty
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try cz.lz4.frame.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader(), .{});
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);

    try testing.expectEqual(@as(usize, 0), output.len);
}

// =============================================================================
// Interleaved Operations
// =============================================================================

test "streaming: interleaved compress operations" {
    const allocator = testing.allocator;

    // Test that multiple compressors can operate simultaneously
    var gzip_buf: [4096]u8 = undefined;
    var zstd_buf: [4096]u8 = undefined;
    var lz4_buf: [4096]u8 = undefined;

    var gzip_stream = std.io.fixedBufferStream(&gzip_buf);
    var zstd_stream = std.io.fixedBufferStream(&zstd_buf);
    var lz4_stream = std.io.fixedBufferStream(&lz4_buf);

    var gzip_comp = try cz.gzip.Compressor(@TypeOf(gzip_stream).Writer).init(allocator, gzip_stream.writer(), .{});
    defer gzip_comp.deinit();
    var zstd_comp = try cz.zstd.Compressor(@TypeOf(zstd_stream).Writer).init(allocator, zstd_stream.writer(), .{});
    defer zstd_comp.deinit();
    var lz4_comp = try cz.lz4.frame.Compressor(@TypeOf(lz4_stream).Writer).init(allocator, lz4_stream.writer(), .{});
    defer lz4_comp.deinit();

    const input = "Interleaved compression test data. " ** 20;

    // Write to all three in interleaved fashion
    var offset: usize = 0;
    while (offset < input.len) {
        const chunk_end = @min(offset + 10, input.len);
        const chunk = input[offset..chunk_end];

        try gzip_comp.writer().writeAll(chunk);
        try zstd_comp.writer().writeAll(chunk);
        try lz4_comp.writer().writeAll(chunk);

        offset = chunk_end;
    }

    try gzip_comp.finish();
    try zstd_comp.finish();
    try lz4_comp.finish();

    // Verify all three decompress correctly
    {
        var fbs = std.io.fixedBufferStream(gzip_stream.getWritten());
        var decomp = try cz.gzip.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
        defer decomp.deinit();
        const output = try decomp.reader().readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(output);
        try testing.expectEqualStrings(input, output);
    }
    {
        var fbs = std.io.fixedBufferStream(zstd_stream.getWritten());
        var decomp = try cz.zstd.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
        defer decomp.deinit();
        const output = try decomp.reader().readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(output);
        try testing.expectEqualStrings(input, output);
    }
    {
        var fbs = std.io.fixedBufferStream(lz4_stream.getWritten());
        var decomp = try cz.lz4.frame.Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader(), .{});
        defer decomp.deinit();
        const output = try decomp.reader().readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(output);
        try testing.expectEqualStrings(input, output);
    }
}

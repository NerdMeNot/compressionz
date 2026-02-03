//! Memory tests: Allocation failure and leak detection.
//!
//! Tests that the library handles out-of-memory conditions gracefully
//! and doesn't leak memory on error paths.

const std = @import("std");
const cz = @import("compressionz");
const Error = cz.Error;

const testing = std.testing;

// =============================================================================
// No Memory Leak Tests (using testing.allocator which detects leaks)
// =============================================================================

test "no memory leaks: compress then decompress - all codecs" {
    const allocator = testing.allocator; // Detects leaks
    const input = "Test data for memory leak testing. " ** 50;

    // gzip
    {
        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(input, decompressed);
    }
    // zlib
    {
        const compressed = try cz.zlib.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(input, decompressed);
    }
    // zstd
    {
        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(input, decompressed);
    }
    // lz4
    {
        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(input, decompressed);
    }
    // snappy
    {
        const compressed = try cz.snappy.compress(input, allocator);
        defer allocator.free(compressed);

        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(input, decompressed);
    }
    // brotli
    {
        const compressed = try cz.brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(input, decompressed);
    }
    // If we get here without the testing allocator complaining, no leaks!
}

test "no memory leaks: failed decompression - all codecs" {
    const allocator = testing.allocator;
    const garbage = [_]u8{ 0xFF, 0xFE, 0xFD, 0xFC, 0xFB };

    // Test each codec explicitly - should fail but not leak
    try testing.expectError(Error.InvalidData, cz.gzip.decompress(&garbage, allocator, .{}));
    try testing.expectError(Error.InvalidData, cz.zlib.decompress(&garbage, allocator, .{}));
    try testing.expectError(Error.InvalidData, cz.zstd.decompress(&garbage, allocator, .{}));
    try testing.expectError(Error.InvalidData, cz.lz4.frame.decompress(&garbage, allocator, .{}));
    try testing.expectError(Error.InvalidData, cz.brotli.decompress(&garbage, allocator, .{}));
}

test "no memory leaks: empty input" {
    const allocator = testing.allocator;

    // gzip
    {
        const compressed = try cz.gzip.compress("", allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqual(@as(usize, 0), decompressed.len);
    }
    // zlib
    {
        const compressed = try cz.zlib.compress("", allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqual(@as(usize, 0), decompressed.len);
    }
    // zstd
    {
        const compressed = try cz.zstd.compress("", allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqual(@as(usize, 0), decompressed.len);
    }
    // lz4
    {
        const compressed = try cz.lz4.frame.compress("", allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqual(@as(usize, 0), decompressed.len);
    }
    // snappy
    {
        const compressed = try cz.snappy.compress("", allocator);
        defer allocator.free(compressed);

        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);

        try testing.expectEqual(@as(usize, 0), decompressed.len);
    }
    // brotli
    {
        const compressed = try cz.brotli.compress("", allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqual(@as(usize, 0), decompressed.len);
    }
}

test "no memory leaks: large then small allocations" {
    const allocator = testing.allocator;

    // Large allocation
    const large_input = try allocator.alloc(u8, 100 * 1024);
    defer allocator.free(large_input);
    @memset(large_input, 'A');

    const large_compressed = try cz.gzip.compress(large_input, allocator, .{});
    defer allocator.free(large_compressed);

    const large_decompressed = try cz.gzip.decompress(large_compressed, allocator, .{});
    defer allocator.free(large_decompressed);

    // Small allocation after
    const small_compressed = try cz.gzip.compress("small", allocator, .{});
    defer allocator.free(small_compressed);

    const small_decompressed = try cz.gzip.decompress(small_compressed, allocator, .{});
    defer allocator.free(small_decompressed);

    try testing.expectEqualStrings("small", small_decompressed);
}

test "no memory leaks: repeated operations" {
    const allocator = testing.allocator;
    const input = "Repeated operations test data.";

    for (0..10) |_| {
        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(input, decompressed);
    }
}

test "no memory leaks: interleaved codecs" {
    const allocator = testing.allocator;
    const input = "Interleaved codec test data.";

    // Compress with different codecs in sequence
    const gzip_compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(gzip_compressed);

    const lz4_compressed = try cz.lz4.frame.compress(input, allocator, .{});
    defer allocator.free(lz4_compressed);

    const zstd_compressed = try cz.zstd.compress(input, allocator, .{});
    defer allocator.free(zstd_compressed);

    // Decompress in different order
    const zstd_decompressed = try cz.zstd.decompress(zstd_compressed, allocator, .{});
    defer allocator.free(zstd_decompressed);

    const gzip_decompressed = try cz.gzip.decompress(gzip_compressed, allocator, .{});
    defer allocator.free(gzip_decompressed);

    const lz4_decompressed = try cz.lz4.frame.decompress(lz4_compressed, allocator, .{});
    defer allocator.free(lz4_decompressed);

    try testing.expectEqualStrings(input, gzip_decompressed);
    try testing.expectEqualStrings(input, lz4_decompressed);
    try testing.expectEqualStrings(input, zstd_decompressed);
}

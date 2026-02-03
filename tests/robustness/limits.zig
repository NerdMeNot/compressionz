//! Robustness tests: Size limits and overflow protection.
//!
//! Tests that decompression bombs are prevented, buffer limits are enforced,
//! and integer overflow is handled safely.

const std = @import("std");
const cz = @import("compressionz");
const Error = cz.Error;

const testing = std.testing;

// =============================================================================
// Max Output Size Limit Tests
// =============================================================================

test "gzip: max_output_size prevents large decompression" {
    const allocator = testing.allocator;
    const input = "A" ** 1000;

    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Try to decompress with a limit smaller than actual size
    const result = cz.gzip.decompress(compressed, allocator, .{ .max_output_size = 100 });
    try testing.expectError(Error.OutputTooLarge, result);
}

test "zlib: max_output_size prevents large decompression" {
    const allocator = testing.allocator;
    const input = "B" ** 1000;

    const compressed = try cz.zlib.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const result = cz.zlib.decompress(compressed, allocator, .{ .max_output_size = 100 });
    try testing.expectError(Error.OutputTooLarge, result);
}

test "zstd: max_output_size prevents large decompression" {
    const allocator = testing.allocator;
    const input = "C" ** 1000;

    const compressed = try cz.zstd.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const result = cz.zstd.decompress(compressed, allocator, .{ .max_output_size = 100 });
    try testing.expectError(Error.OutputTooLarge, result);
}

test "lz4: max_output_size prevents large decompression" {
    const allocator = testing.allocator;
    const input = "D" ** 1000;

    const compressed = try cz.lz4.frame.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const result = cz.lz4.frame.decompress(compressed, allocator, .{ .max_output_size = 100 });
    try testing.expectError(Error.OutputTooLarge, result);
}

test "brotli: max_output_size prevents large decompression" {
    const allocator = testing.allocator;
    const input = "F" ** 1000;

    const compressed = try cz.brotli.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const result = cz.brotli.decompress(compressed, allocator, .{ .max_output_size = 100 });
    try testing.expectError(Error.OutputTooLarge, result);
}

// =============================================================================
// Output Buffer Too Small Tests
// =============================================================================

test "lz4 block: output buffer too small" {
    const allocator = testing.allocator;
    const input = "Hello, World! This is a test message for buffer size testing.";

    const compressed = try cz.lz4.block.compress(input, allocator);
    defer allocator.free(compressed);

    var small_buffer: [10]u8 = undefined;
    const result = cz.lz4.block.decompressInto(compressed, &small_buffer);
    try testing.expectError(Error.OutputTooSmall, result);
}

test "snappy: decompressInto buffer too small" {
    const allocator = testing.allocator;
    const input = "Hello, World! This is a test message for buffer size testing.";

    const compressed = try cz.snappy.compress(input, allocator);
    defer allocator.free(compressed);

    var small_buffer: [10]u8 = undefined;
    const result = cz.snappy.decompressInto(compressed, &small_buffer);
    try testing.expectError(Error.OutputTooSmall, result);
}

// =============================================================================
// maxCompressedSize Overflow Tests
// =============================================================================

test "lz4 block: maxCompressedSize handles near-max values" {
    const huge = std.math.maxInt(usize) - 100;
    const result = cz.lz4.block.maxCompressedSize(huge);
    try testing.expectEqual(std.math.maxInt(usize), result);
}

test "snappy: maxCompressedSize handles near-max values" {
    const huge = std.math.maxInt(usize) - 100;
    const result = cz.snappy.maxCompressedSize(huge);
    try testing.expectEqual(std.math.maxInt(usize), result);
}

test "gzip: maxCompressedSize handles near-max values" {
    const huge = std.math.maxInt(usize) - 10;
    const result = cz.gzip.maxCompressedSize(huge);
    try testing.expectEqual(std.math.maxInt(usize), result);
}

test "zlib: maxCompressedSize handles near-max values" {
    const huge = std.math.maxInt(usize) - 10;
    const result = cz.zlib.maxCompressedSize(huge);
    try testing.expectEqual(std.math.maxInt(usize), result);
}

test "brotli: maxCompressedSize handles near-max values" {
    const huge = std.math.maxInt(usize) - 10;
    const result = cz.brotli.maxCompressedSize(huge);
    try testing.expectEqual(std.math.maxInt(usize), result);
}

// =============================================================================
// Edge Case Size Tests
// =============================================================================

test "compress and decompress size = 1" {
    const allocator = testing.allocator;

    // Gzip
    {
        const compressed = try cz.gzip.compress("X", allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("X", decompressed);
    }

    // Zstd
    {
        const compressed = try cz.zstd.compress("X", allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("X", decompressed);
    }

    // LZ4 Frame
    {
        const compressed = try cz.lz4.frame.compress("X", allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("X", decompressed);
    }

    // Snappy
    {
        const compressed = try cz.snappy.compress("X", allocator);
        defer allocator.free(compressed);
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("X", decompressed);
    }

    // Brotli
    {
        const compressed = try cz.brotli.compress("X", allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("X", decompressed);
    }
}

test "compress and decompress exact limit" {
    const allocator = testing.allocator;
    const input = "A" ** 100;

    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Decompress with exact limit
    const decompressed = try cz.gzip.decompress(compressed, allocator, .{ .max_output_size = 100 });
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);
}

test "compress and decompress limit minus one fails" {
    const allocator = testing.allocator;
    const input = "A" ** 100;

    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Decompress with limit one less than actual
    const result = cz.gzip.decompress(compressed, allocator, .{ .max_output_size = 99 });
    try testing.expectError(Error.OutputTooLarge, result);
}

// =============================================================================
// Ratio-Based Bomb Detection
// =============================================================================

test "highly compressible data with reasonable limit" {
    const allocator = testing.allocator;

    // 10KB of zeros compresses very well
    const zeros = [_]u8{0} ** 10240;

    const compressed = try cz.gzip.compress(&zeros, allocator, .{});
    defer allocator.free(compressed);

    // The compressed size should be much smaller
    try testing.expect(compressed.len < 100);

    // Should decompress fine with adequate limit
    const decompressed = try cz.gzip.decompress(compressed, allocator, .{ .max_output_size = 20000 });
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, &zeros, decompressed);
}

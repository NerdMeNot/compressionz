//! Stress tests: Large file handling.
//!
//! Tests compression and decompression of large inputs (multi-MB)
//! to verify memory handling and performance at scale.

const std = @import("std");
const cz = @import("compressionz");

const testing = std.testing;

// =============================================================================
// Large Data Generation Helpers
// =============================================================================

fn generateRepetitiveData(allocator: std.mem.Allocator, size: usize) ![]u8 {
    const data = try allocator.alloc(u8, size);
    for (data, 0..) |*b, i| {
        b.* = @intCast((i % 256));
    }
    return data;
}

fn generateTextLikeData(allocator: std.mem.Allocator, size: usize) ![]u8 {
    const data = try allocator.alloc(u8, size);
    const pattern = "The quick brown fox jumps over the lazy dog. ";
    for (data, 0..) |*b, i| {
        b.* = pattern[i % pattern.len];
    }
    return data;
}

fn generateRandomData(allocator: std.mem.Allocator, size: usize, seed: u64) ![]u8 {
    const data = try allocator.alloc(u8, size);
    var rng = std.Random.DefaultPrng.init(seed);
    rng.fill(data);
    return data;
}

// =============================================================================
// 1 MB Tests
// =============================================================================

const MB = 1024 * 1024;

test "1MB repetitive data - all codecs" {
    const allocator = testing.allocator;

    const input = try generateRepetitiveData(allocator, 1 * MB);
    defer allocator.free(input);

    // gzip
    {
        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);
        try testing.expect(compressed.len < input.len);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // zlib
    {
        const compressed = try cz.zlib.compress(input, allocator, .{});
        defer allocator.free(compressed);
        try testing.expect(compressed.len < input.len);
        const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // zstd
    {
        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);
        try testing.expect(compressed.len < input.len);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // lz4
    {
        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);
        try testing.expect(compressed.len < input.len);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // snappy
    {
        const compressed = try cz.snappy.compress(input, allocator);
        defer allocator.free(compressed);
        try testing.expect(compressed.len < input.len);
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // brotli
    {
        const compressed = try cz.brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);
        try testing.expect(compressed.len < input.len);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
}

test "1MB text-like data - all codecs" {
    const allocator = testing.allocator;

    const input = try generateTextLikeData(allocator, 1 * MB);
    defer allocator.free(input);

    // gzip
    {
        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // zlib
    {
        const compressed = try cz.zlib.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // zstd
    {
        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // lz4
    {
        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // snappy
    {
        const compressed = try cz.snappy.compress(input, allocator);
        defer allocator.free(compressed);
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // brotli
    {
        const compressed = try cz.brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
}

test "1MB random data - all codecs" {
    const allocator = testing.allocator;

    const input = try generateRandomData(allocator, 1 * MB, 42);
    defer allocator.free(input);

    // gzip
    {
        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // zlib
    {
        const compressed = try cz.zlib.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // zstd
    {
        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // lz4
    {
        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // snappy
    {
        const compressed = try cz.snappy.compress(input, allocator);
        defer allocator.free(compressed);
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
    // brotli
    {
        const compressed = try cz.brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
}

// =============================================================================
// 4 MB Tests (typical block sizes)
// =============================================================================

test "4MB highly compressible - gzip" {
    const allocator = testing.allocator;

    // All zeros - maximum compression
    const input = try allocator.alloc(u8, 4 * MB);
    defer allocator.free(input);
    @memset(input, 0);

    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Should compress extremely well
    try testing.expect(compressed.len < 10000);

    const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, input, decompressed);
}

test "4MB highly compressible - lz4" {
    const allocator = testing.allocator;

    const input = try allocator.alloc(u8, 4 * MB);
    defer allocator.free(input);
    @memset(input, 'A');

    const compressed = try cz.lz4.frame.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, input, decompressed);
}

test "4MB highly compressible - zstd" {
    const allocator = testing.allocator;

    const input = try allocator.alloc(u8, 4 * MB);
    defer allocator.free(input);
    @memset(input, 0xFF);

    const compressed = try cz.zstd.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, input, decompressed);
}

// =============================================================================
// Compression Ratio Verification
// =============================================================================

test "compression ratio - text vs random" {
    const allocator = testing.allocator;

    const text_input = try generateTextLikeData(allocator, 100 * 1024);
    defer allocator.free(text_input);

    const random_input = try generateRandomData(allocator, 100 * 1024, 123);
    defer allocator.free(random_input);

    const text_compressed = try cz.gzip.compress(text_input, allocator, .{});
    defer allocator.free(text_compressed);

    const random_compressed = try cz.gzip.compress(random_input, allocator, .{});
    defer allocator.free(random_compressed);

    // Text should compress much better than random
    try testing.expect(text_compressed.len < random_compressed.len);

    // Text should achieve at least 50% compression
    try testing.expect(text_compressed.len < text_input.len / 2);
}

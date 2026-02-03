//! Integration tests: Compress → Decompress round-trip for all codecs.
//!
//! These tests verify that data survives a full compression/decompression cycle
//! across all supported codecs with various input patterns.

const std = @import("std");
const cz = @import("compressionz");
const Level = cz.Level;
const Error = cz.Error;

const testing = std.testing;

// =============================================================================
// Basic Round-Trip Tests
// =============================================================================

test "round-trip empty data" {
    const allocator = testing.allocator;

    // LZ4 Frame
    {
        const compressed = try cz.lz4.frame.compress("", allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("", decompressed);
    }

    // Snappy
    {
        const compressed = try cz.snappy.compress("", allocator);
        defer allocator.free(compressed);
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("", decompressed);
    }

    // Zstd
    {
        const compressed = try cz.zstd.compress("", allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("", decompressed);
    }

    // Gzip
    {
        const compressed = try cz.gzip.compress("", allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("", decompressed);
    }

    // Zlib
    {
        const compressed = try cz.zlib.compress("", allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("", decompressed);
    }

    // Brotli
    {
        const compressed = try cz.brotli.compress("", allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings("", decompressed);
    }
}

test "round-trip single byte" {
    const allocator = testing.allocator;
    const input = "X";

    // LZ4 Frame
    {
        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Snappy
    {
        const compressed = try cz.snappy.compress(input, allocator);
        defer allocator.free(compressed);
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Zstd
    {
        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Gzip
    {
        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Zlib
    {
        const compressed = try cz.zlib.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Brotli
    {
        const compressed = try cz.brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }
}

test "round-trip small string" {
    const allocator = testing.allocator;
    const input = "Hello, World!";

    // LZ4 Frame
    {
        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Snappy
    {
        const compressed = try cz.snappy.compress(input, allocator);
        defer allocator.free(compressed);
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Zstd
    {
        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Gzip
    {
        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Zlib
    {
        const compressed = try cz.zlib.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Brotli
    {
        const compressed = try cz.brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }
}

test "round-trip repeated pattern" {
    const allocator = testing.allocator;
    const input = "ABCD" ** 100;

    // LZ4 Frame
    {
        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Snappy
    {
        const compressed = try cz.snappy.compress(input, allocator);
        defer allocator.free(compressed);
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Zstd
    {
        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Gzip
    {
        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Brotli
    {
        const compressed = try cz.brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }
}

test "round-trip lorem ipsum" {
    const allocator = testing.allocator;
    const input = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
        "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";

    // Zstd
    {
        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Gzip
    {
        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }

    // Brotli
    {
        const compressed = try cz.brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }
}

test "round-trip binary data" {
    const allocator = testing.allocator;
    var input: [256]u8 = undefined;
    for (&input, 0..) |*b, i| {
        b.* = @intCast(i);
    }

    // LZ4 Frame
    {
        const compressed = try cz.lz4.frame.compress(&input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, &input, decompressed);
    }

    // Zstd
    {
        const compressed = try cz.zstd.compress(&input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, &input, decompressed);
    }
}

test "round-trip random-like data" {
    const allocator = testing.allocator;
    // Data that doesn't compress well
    var input: [1024]u8 = undefined;
    var rng = std.Random.DefaultPrng.init(12345);
    rng.fill(&input);

    // Zstd
    {
        const compressed = try cz.zstd.compress(&input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, &input, decompressed);
    }

    // Gzip
    {
        const compressed = try cz.gzip.compress(&input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, &input, decompressed);
    }
}

test "round-trip highly compressible" {
    const allocator = testing.allocator;
    // Single repeated byte - maximum compression
    const input = [_]u8{0} ** 10000;

    // Zstd
    {
        const compressed = try cz.zstd.compress(&input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, &input, decompressed);
    }

    // LZ4 Frame
    {
        const compressed = try cz.lz4.frame.compress(&input, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualSlices(u8, &input, decompressed);
    }
}

// =============================================================================
// Compression Level Tests
// =============================================================================

test "all levels - gzip" {
    const allocator = testing.allocator;
    const input = "Test data for compression level testing. " ** 50;
    const levels = [_]Level{ .fastest, .fast, .default, .better, .best };

    for (levels) |level| {
        const compressed = try cz.gzip.compress(input, allocator, .{ .level = level });
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }
}

test "all levels - zstd" {
    const allocator = testing.allocator;
    const input = "Test data for compression level testing. " ** 50;
    const levels = [_]Level{ .fastest, .fast, .default, .better, .best };

    for (levels) |level| {
        const compressed = try cz.zstd.compress(input, allocator, .{ .level = level });
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }
}

test "all levels - brotli" {
    const allocator = testing.allocator;
    const input = "Test data for compression level testing. " ** 50;
    const levels = [_]Level{ .fastest, .fast, .default, .better, .best };

    for (levels) |level| {
        const compressed = try cz.brotli.compress(input, allocator, .{ .level = level });
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try testing.expectEqualStrings(input, decompressed);
    }
}

// =============================================================================
// Codec-Specific Format Tests
// =============================================================================

test "gzip magic number" {
    const allocator = testing.allocator;
    const compressed = try cz.gzip.compress("test", allocator, .{});
    defer allocator.free(compressed);

    // Gzip magic: 0x1f 0x8b
    try testing.expect(compressed.len >= 2);
    try testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try testing.expectEqual(@as(u8, 0x8b), compressed[1]);
}

test "zlib header" {
    const allocator = testing.allocator;
    const compressed = try cz.zlib.compress("test", allocator, .{});
    defer allocator.free(compressed);

    // Zlib header: CMF (usually 0x78) + FLG
    try testing.expect(compressed.len >= 2);
    try testing.expectEqual(@as(u8, 0x78), compressed[0]);
}

test "lz4 frame magic" {
    const allocator = testing.allocator;
    const compressed = try cz.lz4.frame.compress("test data here", allocator, .{});
    defer allocator.free(compressed);

    // LZ4 frame magic: 0x04224D18 (little-endian)
    try testing.expect(compressed.len >= 4);
    const magic = std.mem.readInt(u32, compressed[0..4], .little);
    try testing.expectEqual(@as(u32, 0x184D2204), magic);
}

test "zstd magic number" {
    const allocator = testing.allocator;
    const compressed = try cz.zstd.compress("test", allocator, .{});
    defer allocator.free(compressed);

    // Zstd magic: 0xFD2FB528 (little-endian)
    try testing.expect(compressed.len >= 4);
    const magic = std.mem.readInt(u32, compressed[0..4], .little);
    try testing.expectEqual(@as(u32, 0xFD2FB528), magic);
}

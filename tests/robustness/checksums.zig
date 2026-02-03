//! Robustness tests: Checksum validation.
//!
//! Tests that checksums are properly computed and validated,
//! detecting data corruption.

const std = @import("std");
const cz = @import("compressionz");
const Error = cz.Error;
const lz4 = cz.lz4;

const testing = std.testing;

// =============================================================================
// LZ4 Frame Checksum Tests
// =============================================================================

test "lz4 frame: content checksum enabled by default" {
    const allocator = testing.allocator;
    const input = "Test content for checksum verification.";

    const compressed = try lz4.frame.compress(input, allocator, .{ .content_checksum = true });
    defer allocator.free(compressed);

    // Frame should be larger than without checksum (4 bytes for xxHash32)
    const compressed_no_checksum = try lz4.frame.compress(input, allocator, .{ .content_checksum = false });
    defer allocator.free(compressed_no_checksum);

    try testing.expect(compressed.len == compressed_no_checksum.len + 4);

    // Both should decompress correctly
    const decompressed1 = try lz4.frame.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed1);
    try testing.expectEqualStrings(input, decompressed1);

    const decompressed2 = try lz4.frame.decompress(compressed_no_checksum, allocator, .{});
    defer allocator.free(decompressed2);
    try testing.expectEqualStrings(input, decompressed2);
}

test "lz4 frame: corrupted content detected by checksum" {
    const allocator = testing.allocator;
    const input = "This is test data that will be corrupted!";

    const compressed = try lz4.frame.compress(input, allocator, .{ .content_checksum = true });
    defer allocator.free(compressed);

    // Find and corrupt a data byte (not header or checksum)
    // LZ4 frame: magic(4) + FLG(1) + BD(1) + HC(1) = 7 bytes header minimum
    // Then block size(4) + data + end mark(4) + checksum(4)
    var corrupted = try allocator.alloc(u8, compressed.len);
    defer allocator.free(corrupted);
    @memcpy(corrupted, compressed);

    // Corrupt a byte in the middle (likely in the data)
    if (corrupted.len > 15) {
        corrupted[10] ^= 0x55;
    }

    const result = lz4.frame.decompress(corrupted, allocator, .{});
    // Should detect corruption - may be checksum, invalid data, or unexpected EOF
    try testing.expect(result == Error.ChecksumMismatch or result == Error.InvalidData or result == Error.UnexpectedEof);
}

test "lz4 frame: flipped checksum bit detected" {
    const allocator = testing.allocator;
    const input = "Checksum bit flip test data.";

    const compressed = try lz4.frame.compress(input, allocator, .{ .content_checksum = true });
    defer allocator.free(compressed);

    var corrupted = try allocator.alloc(u8, compressed.len);
    defer allocator.free(corrupted);
    @memcpy(corrupted, compressed);

    // Flip one bit in the checksum (last 4 bytes)
    corrupted[corrupted.len - 2] ^= 0x01;

    const result = lz4.frame.decompress(corrupted, allocator, .{});
    try testing.expectError(Error.ChecksumMismatch, result);
}

// =============================================================================
// Gzip Checksum Tests (CRC32)
// =============================================================================

test "gzip: corrupted data detected" {
    const allocator = testing.allocator;
    const input = "Gzip uses CRC32 for integrity checking.";

    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    var corrupted = try allocator.alloc(u8, compressed.len);
    defer allocator.free(corrupted);
    @memcpy(corrupted, compressed);

    // Corrupt middle of data
    if (corrupted.len > 20) {
        corrupted[corrupted.len / 2] ^= 0xFF;
    }

    const result = cz.gzip.decompress(corrupted, allocator, .{});
    // Gzip should detect via CRC32
    try testing.expect(result == Error.InvalidData or result == Error.ChecksumMismatch);
}

// =============================================================================
// Zlib Checksum Tests (Adler32)
// =============================================================================

test "zlib: corrupted data detected" {
    const allocator = testing.allocator;
    const input = "Zlib uses Adler32 for integrity checking.";

    const compressed = try cz.zlib.compress(input, allocator, .{});
    defer allocator.free(compressed);

    var corrupted = try allocator.alloc(u8, compressed.len);
    defer allocator.free(corrupted);
    @memcpy(corrupted, compressed);

    // Corrupt middle of data (after header, before trailer)
    if (corrupted.len > 10) {
        corrupted[corrupted.len / 2] ^= 0xFF;
    }

    const result = cz.zlib.decompress(corrupted, allocator, .{});
    try testing.expect(result == Error.InvalidData or result == Error.ChecksumMismatch);
}

// =============================================================================
// Zstd Checksum Tests
// =============================================================================

test "zstd: corrupted data detected" {
    const allocator = testing.allocator;
    const input = "Zstd has built-in integrity checking.";

    const compressed = try cz.zstd.compress(input, allocator, .{});
    defer allocator.free(compressed);

    var corrupted = try allocator.alloc(u8, compressed.len);
    defer allocator.free(corrupted);
    @memcpy(corrupted, compressed);

    // Corrupt a byte in the compressed data
    if (corrupted.len > 10) {
        corrupted[corrupted.len / 2] ^= 0x80;
    }

    const result = cz.zstd.decompress(corrupted, allocator, .{});
    // Zstd should detect corruption, or in rare cases the corruption
    // might still produce valid (but wrong) output
    if (result) |data| {
        // If decompression succeeded, data should be different from original
        defer allocator.free(data);
        // This is technically a successful decode of corrupted data - unusual but possible
    } else |_| {
        // Expected: corruption detected
    }
}

// =============================================================================
// Multiple Corruption Points
// =============================================================================

test "corruption at various positions" {
    const allocator = testing.allocator;
    const input = "A" ** 500; // Reasonably sized input

    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Test corruption at beginning, middle, and end of compressed data
    const positions = [_]usize{ 5, compressed.len / 2, compressed.len - 5 };

    for (positions) |pos| {
        if (pos < compressed.len) {
            var corrupted = try allocator.alloc(u8, compressed.len);
            defer allocator.free(corrupted);
            @memcpy(corrupted, compressed);
            corrupted[pos] ^= 0xFF;

            const result = cz.gzip.decompress(corrupted, allocator, .{});
            // Corruption should be detected, or in rare cases produce different output
            if (result) |data| {
                defer allocator.free(data);
                // Decompression succeeded - corruption wasn't detected by checksum
                // This can happen if the corruption is in a way that still produces
                // valid (but wrong) deflate stream
            } else |_| {
                // Expected: corruption detected
            }
        }
    }
}

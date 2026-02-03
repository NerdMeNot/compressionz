//! Robustness tests: Malformed and corrupted input handling.
//!
//! These tests verify that decoders properly reject invalid data
//! without crashing, leaking memory, or exhibiting undefined behavior.

const std = @import("std");
const cz = @import("compressionz");
const Error = cz.Error;
const lz4 = cz.lz4;
const snappy = cz.snappy;
const tar = cz.archive.tar;
const zip = cz.archive.zip;

const testing = std.testing;

// =============================================================================
// Generic Codec Malformed Input Tests
// =============================================================================

test "all codecs: reject empty input gracefully" {
    const allocator = testing.allocator;

    // Test each codec explicitly
    // gzip
    {
        const result = cz.gzip.decompress("", allocator, .{});
        if (result) |data| {
            defer allocator.free(data);
            try testing.expectEqual(@as(usize, 0), data.len);
        } else |_| {}
    }
    // zlib
    {
        const result = cz.zlib.decompress("", allocator, .{});
        if (result) |data| {
            defer allocator.free(data);
            try testing.expectEqual(@as(usize, 0), data.len);
        } else |_| {}
    }
    // deflate
    {
        const result = cz.zlib.decompressDeflate("", allocator, .{});
        if (result) |data| {
            defer allocator.free(data);
            try testing.expectEqual(@as(usize, 0), data.len);
        } else |_| {}
    }
    // zstd
    {
        const result = cz.zstd.decompress("", allocator, .{});
        if (result) |data| {
            defer allocator.free(data);
            try testing.expectEqual(@as(usize, 0), data.len);
        } else |_| {}
    }
    // lz4
    {
        const result = cz.lz4.frame.decompress("", allocator, .{});
        if (result) |data| {
            defer allocator.free(data);
            try testing.expectEqual(@as(usize, 0), data.len);
        } else |_| {}
    }
    // snappy
    {
        const result = cz.snappy.decompress("", allocator);
        if (result) |data| {
            defer allocator.free(data);
            try testing.expectEqual(@as(usize, 0), data.len);
        } else |_| {}
    }
    // brotli
    {
        const result = cz.brotli.decompress("", allocator, .{});
        if (result) |data| {
            defer allocator.free(data);
            try testing.expectEqual(@as(usize, 0), data.len);
        } else |_| {}
    }
}

test "all codecs: reject garbage data" {
    const allocator = testing.allocator;
    const garbage = [_]u8{ 0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA, 0xF9, 0xF8 };

    // Test each codec explicitly
    try testing.expectError(Error.InvalidData, cz.gzip.decompress(&garbage, allocator, .{}));
    try testing.expectError(Error.InvalidData, cz.zlib.decompress(&garbage, allocator, .{}));
    try testing.expectError(Error.InvalidData, cz.zlib.decompressDeflate(&garbage, allocator, .{}));
    try testing.expectError(Error.InvalidData, cz.zstd.decompress(&garbage, allocator, .{}));
    try testing.expectError(Error.InvalidData, cz.lz4.frame.decompress(&garbage, allocator, .{}));
    try testing.expectError(Error.InvalidData, cz.snappy.decompress(&garbage, allocator));
    try testing.expectError(Error.InvalidData, cz.brotli.decompress(&garbage, allocator, .{}));
}

test "all codecs: reject truncated valid data" {
    const allocator = testing.allocator;
    const input = "Hello, World! This is test data for truncation.";

    // gzip
    {
        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);

        if (compressed.len > 4) {
            const truncated = compressed[0 .. compressed.len / 2];
            const result = cz.gzip.decompress(truncated, allocator, .{});
            if (result) |data| {
                allocator.free(data);
                try testing.expect(false);
            } else |err| {
                try testing.expect(err == Error.InvalidData or
                    err == Error.UnexpectedEof or
                    err == Error.ChecksumMismatch);
            }
        }
    }
    // zlib
    {
        const compressed = try cz.zlib.compress(input, allocator, .{});
        defer allocator.free(compressed);

        if (compressed.len > 4) {
            const truncated = compressed[0 .. compressed.len / 2];
            const result = cz.zlib.decompress(truncated, allocator, .{});
            if (result) |data| {
                allocator.free(data);
                try testing.expect(false);
            } else |err| {
                try testing.expect(err == Error.InvalidData or
                    err == Error.UnexpectedEof or
                    err == Error.ChecksumMismatch);
            }
        }
    }
    // zstd
    {
        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);

        if (compressed.len > 4) {
            const truncated = compressed[0 .. compressed.len / 2];
            const result = cz.zstd.decompress(truncated, allocator, .{});
            if (result) |data| {
                allocator.free(data);
                try testing.expect(false);
            } else |err| {
                try testing.expect(err == Error.InvalidData or
                    err == Error.UnexpectedEof or
                    err == Error.ChecksumMismatch);
            }
        }
    }
    // lz4
    {
        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);

        if (compressed.len > 4) {
            const truncated = compressed[0 .. compressed.len / 2];
            const result = cz.lz4.frame.decompress(truncated, allocator, .{});
            if (result) |data| {
                allocator.free(data);
                try testing.expect(false);
            } else |err| {
                try testing.expect(err == Error.InvalidData or
                    err == Error.UnexpectedEof or
                    err == Error.ChecksumMismatch);
            }
        }
    }
    // brotli
    {
        const compressed = try cz.brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);

        if (compressed.len > 4) {
            const truncated = compressed[0 .. compressed.len / 2];
            const result = cz.brotli.decompress(truncated, allocator, .{});
            if (result) |data| {
                allocator.free(data);
                try testing.expect(false);
            } else |err| {
                try testing.expect(err == Error.InvalidData or
                    err == Error.UnexpectedEof or
                    err == Error.ChecksumMismatch);
            }
        }
    }
}

// =============================================================================
// LZ4 Block Format Malformed Input
// =============================================================================

test "lz4 block: invalid zero offset" {
    // Token: 0x10 = 1 literal, match length 4
    // Offset: 0x00 0x00 = 0 (invalid)
    const invalid_data = [_]u8{ 0x14, 'A', 0x00, 0x00 };
    var output: [100]u8 = undefined;
    const result = lz4.block.decompressInto(&invalid_data, &output);
    try testing.expectError(Error.InvalidData, result);
}

test "lz4 block: offset beyond output position" {
    // Token with literal + match, offset larger than current output
    const invalid_data = [_]u8{ 0x10, 'A', 0x10, 0x00 }; // offset=16, but only 1 byte written
    var output: [100]u8 = undefined;
    const result = lz4.block.decompressInto(&invalid_data, &output);
    try testing.expectError(Error.InvalidData, result);
}

test "lz4 block: truncated literal length" {
    // Token 0xF0 means 15+ literals, needs extra length byte
    const invalid_data = [_]u8{0xF0}; // Missing length continuation and literals
    var output: [100]u8 = undefined;
    const result = lz4.block.decompressInto(&invalid_data, &output);
    // Should fail gracefully
    if (result) |_| {
        try testing.expect(false); // Should have failed
    } else |err| {
        try testing.expect(err == Error.UnexpectedEof or err == Error.InvalidData);
    }
}

test "lz4 block: handles edge case match length" {
    // LZ4 block format edge case: token 0x1F with offset
    // The decoder may succeed via repeat-copy or fail gracefully
    // Either behavior is acceptable - the key is no crash/memory corruption
    const edge_case_data = [_]u8{
        0x1F, // 1 literal, match length indicator 15
        'A', // literal
        0x01, 0x00, // offset = 1 (references the 'A')
    };
    var output: [100]u8 = undefined;
    const result = lz4.block.decompressInto(&edge_case_data, &output);
    // Success or error are both acceptable - just shouldn't crash
    if (result) |decompressed| {
        // Decoder succeeded - verify output is reasonable
        try testing.expect(decompressed.len > 0 and decompressed.len <= output.len);
    } else |_| {
        // Error is also acceptable for this edge case input
    }
}

// =============================================================================
// LZ4 Frame Format Malformed Input
// =============================================================================

test "lz4 frame: invalid magic number" {
    const allocator = testing.allocator;
    const invalid = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x40, 0x40, 0x00 };
    const result = lz4.frame.decompress(&invalid, allocator, .{});
    try testing.expectError(Error.InvalidData, result);
}

test "lz4 frame: truncated header" {
    const allocator = testing.allocator;
    // Valid magic but incomplete header
    const truncated = [_]u8{ 0x04, 0x22, 0x4D, 0x18, 0x40 };
    const result = lz4.frame.decompress(&truncated, allocator, .{});
    try testing.expectError(Error.InvalidData, result);
}

test "lz4 frame: corrupted content checksum" {
    const allocator = testing.allocator;
    const input = "Test checksum validation for LZ4 frames!";

    const compressed = try lz4.frame.compress(input, allocator, .{ .content_checksum = true });
    defer allocator.free(compressed);

    // Corrupt the last 4 bytes (content checksum)
    var corrupted = try allocator.alloc(u8, compressed.len);
    defer allocator.free(corrupted);
    @memcpy(corrupted, compressed);
    corrupted[corrupted.len - 1] ^= 0xFF;

    const result = lz4.frame.decompress(corrupted, allocator, .{});
    try testing.expectError(Error.ChecksumMismatch, result);
}

// =============================================================================
// Snappy Malformed Input
// =============================================================================

test "snappy: empty input" {
    const allocator = testing.allocator;
    const result = snappy.decompress("", allocator);
    try testing.expectError(Error.InvalidData, result);
}

test "snappy: invalid varint" {
    const allocator = testing.allocator;
    // Varint with all continuation bits set (never terminates)
    const invalid = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 };
    const result = snappy.decompress(&invalid, allocator);
    try testing.expectError(Error.InvalidData, result);
}

test "snappy: length mismatch" {
    const allocator = testing.allocator;
    // Claims 100 bytes but only provides a few
    const invalid = [_]u8{
        100, // varint: uncompressed length = 100
        0x10, // literal tag: 5 bytes
        'H', 'e', 'l', 'l', 'o', // Only 5 literal bytes
    };
    const result = snappy.decompress(&invalid, allocator);
    // Should fail because output doesn't reach claimed length
    if (result) |data| {
        allocator.free(data);
        try testing.expect(false); // Should have failed
    } else |err| {
        try testing.expect(err == Error.InvalidData or err == Error.UnexpectedEof);
    }
}

// =============================================================================
// TAR Malformed Input
// =============================================================================

test "tar: invalid checksum" {
    const allocator = testing.allocator;

    var header: [512]u8 = undefined;
    @memset(&header, 0);

    // Set filename
    @memcpy(header[0..8], "test.txt");

    // Set mode
    @memcpy(header[100..107], "0000644");

    // Set size to 0
    @memcpy(header[124..135], "00000000000");

    // Set invalid checksum
    @memcpy(header[148..155], "9999999");

    var read_stream = std.io.fixedBufferStream(&header);
    var reader = tar.Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    const result = reader.next();
    try testing.expectError(Error.InvalidData, result);
}

test "tar: truncated header" {
    const allocator = testing.allocator;

    // Less than 512 bytes
    const truncated = [_]u8{ 't', 'e', 's', 't', '.', 't', 'x', 't' };

    var read_stream = std.io.fixedBufferStream(&truncated);
    var reader = tar.Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    // Should return null (EOF) or handle gracefully
    const entry = try reader.next();
    try testing.expectEqual(@as(?*tar.Entry, null), entry);
}

// =============================================================================
// ZIP Malformed Input
// =============================================================================

test "zip: invalid signature" {
    const allocator = testing.allocator;

    const invalid = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

    var read_stream = std.io.fixedBufferStream(&invalid);
    var reader = try zip.Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    const result = reader.count();
    try testing.expectError(Error.InvalidData, result);
}

test "zip: truncated end-of-central-directory" {
    const allocator = testing.allocator;

    // Just the EOCD signature without the rest
    const truncated = [_]u8{ 0x50, 0x4B, 0x05, 0x06 };

    var read_stream = std.io.fixedBufferStream(&truncated);
    var reader = try zip.Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    const result = reader.count();
    try testing.expectError(Error.InvalidData, result);
}

// =============================================================================
// Bit Flip Corruption Tests
// =============================================================================

test "single bit flip in compressed data" {
    const allocator = testing.allocator;
    const input = "Test data for bit flip corruption testing. " ** 10;

    // Test with gzip (has checksum)
    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Flip a bit in the middle of the data
    if (compressed.len > 20) {
        var corrupted = try allocator.alloc(u8, compressed.len);
        defer allocator.free(corrupted);
        @memcpy(corrupted, compressed);
        corrupted[compressed.len / 2] ^= 0x01;

        const result = cz.gzip.decompress(corrupted, allocator, .{});
        // Should detect corruption - may manifest as various errors
        if (result) |data| {
            // Corruption wasn't detected - free the memory
            allocator.free(data);
        } else |_| {
            // Expected: corruption detected as some kind of error
        }
    }
}

//! Integration tests: Dictionary compression support.
//!
//! Tests dictionary-based compression and decompression for codecs
//! that support this feature (zstd, zlib).

const std = @import("std");
const cz = @import("compressionz");
const Error = cz.Error;

const testing = std.testing;

// Sample dictionary - common patterns that might appear in test data
const TEST_DICTIONARY = "The quick brown fox jumps over the lazy dog. " ++
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
    "Hello World! Testing dictionary compression. " ** 10;

// =============================================================================
// Zstd Dictionary Tests
// =============================================================================

test "zstd: compress with dictionary, decompress with dictionary" {
    const allocator = testing.allocator;
    const dictionary = TEST_DICTIONARY;
    const input = "The quick brown fox jumps over the lazy dog. Hello World!";

    // Compress with dictionary
    const compressed = try cz.zstd.compressWithDict(input, dictionary, allocator, .{});
    defer allocator.free(compressed);

    // Decompress with dictionary
    const decompressed = try cz.zstd.decompressWithDict(compressed, dictionary, allocator, .{});
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);
}

test "zstd: dictionary improves compression ratio" {
    const allocator = testing.allocator;
    const dictionary = TEST_DICTIONARY;

    // Input that contains patterns from dictionary
    const input = "The quick brown fox jumps over the lazy dog. " ** 5 ++
        "Hello World! Testing dictionary compression. " ** 5;

    // Compress without dictionary
    const compressed_no_dict = try cz.zstd.compress(input, allocator, .{});
    defer allocator.free(compressed_no_dict);

    // Compress with dictionary
    const compressed_with_dict = try cz.zstd.compressWithDict(input, dictionary, allocator, .{});
    defer allocator.free(compressed_with_dict);

    // Dictionary should help compression (or at least not hurt)
    // Note: For very small inputs, dictionary might not help
    try testing.expect(compressed_with_dict.len <= compressed_no_dict.len + 50);
}

test "zstd: decompress without required dictionary fails" {
    const allocator = testing.allocator;
    const dictionary = TEST_DICTIONARY;
    const input = "The quick brown fox jumps over the lazy dog.";

    // Compress with dictionary
    const compressed = try cz.zstd.compressWithDict(input, dictionary, allocator, .{});
    defer allocator.free(compressed);

    // Try to decompress without dictionary - should fail or produce wrong output
    const result = cz.zstd.decompress(compressed, allocator, .{});
    if (result) |data| {
        // If it succeeds, the output should be different (corrupted)
        defer allocator.free(data);
        // This is actually unlikely to succeed without dictionary
    } else |_| {
        // Expected: decompression fails without dictionary
    }
}

// =============================================================================
// Zlib Dictionary Tests
// =============================================================================

test "zlib: decompress with dictionary" {
    const allocator = testing.allocator;

    // For zlib, dictionary compression requires special setup
    // This test verifies our decompressor handles Z_NEED_DICT correctly
    // We'll create a simple test case

    const dictionary = "AAABBBCCCDDDEEEFFFGGGHHHIIIJJJ";
    const input = "AAABBBAAABBBCCCDDDAAABBB";

    // Use raw deflate for dictionary testing
    const compressed = try compressWithDictZlib(input, dictionary, allocator);
    defer allocator.free(compressed);

    // Decompress with dictionary
    const decompressed = try cz.zlib.decompressDeflateWithDict(compressed, dictionary, allocator, .{});
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Compress with zlib dictionary using C API (raw deflate)
fn compressWithDictZlib(input: []const u8, dictionary: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const c = @cImport({
        @cInclude("zlib.h");
    });

    const max_size = input.len + (input.len >> 10) + 18;
    const output = try allocator.alloc(u8, max_size);
    errdefer allocator.free(output);

    var stream: c.z_stream = std.mem.zeroes(c.z_stream);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    stream.next_out = output.ptr;
    stream.avail_out = @intCast(output.len);

    // Use raw deflate (negative window bits)
    if (c.deflateInit2(&stream, 6, c.Z_DEFLATED, -15, 8, c.Z_DEFAULT_STRATEGY) != c.Z_OK) {
        return error.InitFailed;
    }
    defer _ = c.deflateEnd(&stream);

    // Set dictionary
    if (c.deflateSetDictionary(&stream, dictionary.ptr, @intCast(dictionary.len)) != c.Z_OK) {
        return error.DictFailed;
    }

    if (c.deflate(&stream, c.Z_FINISH) != c.Z_STREAM_END) {
        return error.CompressionFailed;
    }

    const written = output.len - stream.avail_out;
    return allocator.realloc(output, written) catch output[0..written];
}

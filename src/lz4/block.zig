//! LZ4 block compression and decompression.
//!
//! Block format is raw LZ4 without any framing. The decompressed size
//! must be known beforehand.
//!
//! ## Format
//! A sequence is: token + [extra literal length] + literals + offset + [extra match length]
//! - Token: high nibble = literal length (0-14, or 15=more), low nibble = match length - 4
//! - If literal length is 15, read additional bytes until < 255
//! - Literals: raw bytes to copy to output
//! - Offset: 2-byte little-endian distance to match start
//! - If match length nibble is 15, read additional bytes until < 255

const std = @import("std");
const err = @import("../error.zig");
const Error = err.Error;
const shrinkAllocation = err.shrinkAllocation;
const builtin = @import("builtin");

const MIN_MATCH = 4;
const ML_BITS = 4;
const ML_MASK = (1 << ML_BITS) - 1;
const RUN_BITS = 4;
const RUN_MASK = (1 << RUN_BITS) - 1;

// Hash table parameters for compression
const HASH_LOG = 16;
const HASH_SIZE = 1 << HASH_LOG;
const SKIP_STRENGTH = 6;

// SIMD vector type for accelerated matching
const Vec16 = @Vector(16, u8);

// SIMD vector types for accelerated operations
const Vec8 = @Vector(8, u8);

/// Copy match data with SIMD acceleration when possible.
/// For offset >= 8, we can safely copy 8 bytes at a time.
fn copyMatch(output: []u8, dst: usize, offset: usize, length: usize) void {
    const src = dst - offset;

    if (offset >= 8) {
        // Safe to copy 8 bytes at a time (no overlap within copy unit)
        var i: usize = 0;
        while (i + 8 <= length) {
            const chunk: Vec8 = output[src + i ..][0..8].*;
            output[dst + i ..][0..8].* = chunk;
            i += 8;
        }
        // Handle remaining bytes
        while (i < length) : (i += 1) {
            output[dst + i] = output[src + i];
        }
    } else {
        // Small offset - must handle overlap byte-by-byte
        for (0..length) |i| {
            output[dst + i] = output[src + i];
        }
    }
}

/// Count matching bytes using SIMD acceleration.
/// Compares 16 bytes at a time for faster match extension.
fn countMatchLength(src: []const u8, match: []const u8, max_len: usize) usize {
    var len: usize = 0;

    // Ensure we have enough bytes in both slices for SIMD comparison
    const safe_max = @min(max_len, @min(src.len, match.len));

    // Use SIMD to compare 16 bytes at a time
    while (len + 16 <= safe_max) {
        const src_vec: Vec16 = src[len..][0..16].*;
        const match_vec: Vec16 = match[len..][0..16].*;

        // Compare vectors - result is a vector of 0xFF (equal) or 0x00 (not equal)
        const eq_mask = src_vec == match_vec;

        // Convert boolean vector to integer for analysis
        const mask_int: u16 = @bitCast(eq_mask);

        if (mask_int != 0xFFFF) {
            // Found mismatch - count trailing matching bytes
            // Each bit represents one byte comparison
            const mismatches = ~mask_int;
            const trailing_matches = @ctz(mismatches);
            return @min(len + trailing_matches, safe_max);
        }
        len += 16;
    }

    // Handle remaining bytes with scalar comparison
    while (len < safe_max and src[len] == match[len]) {
        len += 1;
    }

    return len;
}

/// Compress data into a newly allocated buffer.
pub fn compress(input: []const u8, allocator: std.mem.Allocator) Error![]u8 {
    const max_size = maxCompressedSize(input.len);
    const output = allocator.alloc(u8, max_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    const result = try compressInto(input, output);
    return shrinkAllocation(allocator, output, result.len);
}

/// Compress data into provided buffer. Returns slice of written data.
pub fn compressInto(input: []const u8, output: []u8) Error![]u8 {
    if (input.len == 0) {
        return output[0..0];
    }

    if (output.len < maxCompressedSize(input.len)) {
        return Error.OutputTooSmall;
    }

    // For very small inputs, just emit literals
    if (input.len < 13) {
        return compressSmall(input, output);
    }

    // Hash table for finding matches
    var hash_table: [HASH_SIZE]u32 = undefined;
    @memset(&hash_table, 0);

    var src_idx: usize = 0;
    var dst_idx: usize = 0;
    var anchor: usize = 0;

    const src_end = input.len;
    const match_limit = if (src_end > 12) src_end - 12 else 0;
    const mf_limit = if (src_end > 5) src_end - 5 else 0;

    // Main compression loop
    while (src_idx < mf_limit) {
        // Find a match using hash
        const hash_val = hash4(input[src_idx..]);
        const match_idx = hash_table[hash_val];
        hash_table[hash_val] = @intCast(src_idx);

        // Check if we have a valid match (u32 compare is faster than mem.eql)
        if (match_idx > 0 and
            src_idx - match_idx <= 65535 and
            src_idx > match_idx and
            std.mem.readInt(u32, input[match_idx..][0..4], .little) == std.mem.readInt(u32, input[src_idx..][0..4], .little))
        {
            // Found a match - encode literals before it
            const lit_len = src_idx - anchor;
            const match_offset = src_idx - match_idx;

            // Count match length using SIMD-accelerated comparison
            const max_match = @min(src_end - src_idx, src_end - match_idx);
            const match_len = MIN_MATCH + countMatchLength(
                input[src_idx + MIN_MATCH ..],
                input[match_idx + MIN_MATCH ..],
                max_match - MIN_MATCH,
            );

            // Encode sequence
            dst_idx = encodeSequence(output, dst_idx, input[anchor..][0..lit_len], match_offset, match_len);

            src_idx += match_len;
            anchor = src_idx;
        } else {
            src_idx += 1;
        }

        if (src_idx >= match_limit) break;
    }

    // Encode remaining literals
    const remaining = input.len - anchor;
    if (remaining > 0) {
        dst_idx = encodeLiterals(output, dst_idx, input[anchor..]);
    }

    return output[0..dst_idx];
}

fn compressSmall(input: []const u8, output: []u8) []u8 {
    var dst_idx: usize = 0;
    dst_idx = encodeLiterals(output, dst_idx, input);
    return output[0..dst_idx];
}

fn hash4(data: []const u8) u32 {
    if (data.len < 4) return 0;
    const val = std.mem.readInt(u32, data[0..4], .little);
    return @intCast((val *% 2654435761) >> (32 - HASH_LOG));
}

fn encodeSequence(output: []u8, start: usize, literals: []const u8, offset: usize, match_len: usize) usize {
    var dst = start;
    const lit_len = literals.len;
    const ml = match_len - MIN_MATCH;

    // Encode token
    var token: u8 = 0;
    if (lit_len >= 15) {
        token = 0xF0;
    } else {
        token = @intCast(lit_len << 4);
    }
    if (ml >= 15) {
        token |= 0x0F;
    } else {
        token |= @intCast(ml);
    }
    output[dst] = token;
    dst += 1;

    // Encode extra literal length
    if (lit_len >= 15) {
        var remaining = lit_len - 15;
        while (remaining >= 255) {
            output[dst] = 255;
            dst += 1;
            remaining -= 255;
        }
        output[dst] = @intCast(remaining);
        dst += 1;
    }

    // Copy literals
    @memcpy(output[dst..][0..lit_len], literals);
    dst += lit_len;

    // Encode offset (little-endian)
    output[dst] = @intCast(offset & 0xFF);
    output[dst + 1] = @intCast((offset >> 8) & 0xFF);
    dst += 2;

    // Encode extra match length
    if (ml >= 15) {
        var remaining = ml - 15;
        while (remaining >= 255) {
            output[dst] = 255;
            dst += 1;
            remaining -= 255;
        }
        output[dst] = @intCast(remaining);
        dst += 1;
    }

    return dst;
}

fn encodeLiterals(output: []u8, start: usize, literals: []const u8) usize {
    var dst = start;
    const lit_len = literals.len;

    // Token with no match (match length = 0)
    var token: u8 = 0;
    if (lit_len >= 15) {
        token = 0xF0;
    } else {
        token = @intCast(lit_len << 4);
    }
    output[dst] = token;
    dst += 1;

    // Extra literal length
    if (lit_len >= 15) {
        var remaining = lit_len - 15;
        while (remaining >= 255) {
            output[dst] = 255;
            dst += 1;
            remaining -= 255;
        }
        output[dst] = @intCast(remaining);
        dst += 1;
    }

    // Copy literals
    @memcpy(output[dst..][0..lit_len], literals);
    dst += lit_len;

    return dst;
}

/// Decompress data with known output size.
pub fn decompressWithSize(input: []const u8, output_size: usize, allocator: std.mem.Allocator) Error![]u8 {
    const output = allocator.alloc(u8, output_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    const result = decompressInto(input, output) catch |e| {
        allocator.free(output);
        return e;
    };

    if (result.len != output_size) {
        allocator.free(output);
        return Error.InvalidData;
    }

    return output;
}

/// Decompress into provided buffer. Returns slice of written data.
pub fn decompressInto(input: []const u8, output: []u8) Error![]u8 {
    if (input.len == 0) {
        return output[0..0];
    }

    var src_idx: usize = 0;
    var dst_idx: usize = 0;

    while (src_idx < input.len) {
        // Read token
        if (src_idx >= input.len) return Error.UnexpectedEof;
        const token = input[src_idx];
        src_idx += 1;

        // Decode literal length
        var lit_len: usize = (token >> 4) & 0x0F;
        if (lit_len == 15) {
            while (src_idx < input.len) {
                const extra = input[src_idx];
                src_idx += 1;
                lit_len += extra;
                if (extra != 255) break;
            }
        }

        // Copy literals
        if (lit_len > 0) {
            if (src_idx + lit_len > input.len) return Error.UnexpectedEof;
            if (dst_idx + lit_len > output.len) return Error.OutputTooSmall;
            @memcpy(output[dst_idx..][0..lit_len], input[src_idx..][0..lit_len]);
            src_idx += lit_len;
            dst_idx += lit_len;
        }

        // Check if this is the last sequence (no match follows)
        if (src_idx >= input.len) break;

        // Read match offset
        if (src_idx + 2 > input.len) return Error.UnexpectedEof;
        const offset: usize = @as(usize, input[src_idx]) | (@as(usize, input[src_idx + 1]) << 8);
        src_idx += 2;

        if (offset == 0) return Error.InvalidData;
        if (offset > dst_idx) return Error.InvalidData;

        // Decode match length
        var match_len: usize = (token & 0x0F) + MIN_MATCH;
        if ((token & 0x0F) == 15) {
            while (src_idx < input.len) {
                const extra = input[src_idx];
                src_idx += 1;
                match_len += extra;
                if (extra != 255) break;
            }
        }

        // Copy match using SIMD-accelerated copy when possible
        if (dst_idx + match_len > output.len) return Error.OutputTooSmall;

        copyMatch(output, dst_idx, offset, match_len);
        dst_idx += match_len;
    }

    return output[0..dst_idx];
}

/// Maximum compressed size for given input size.
/// LZ4 worst case is input + (input / 255) + 16.
/// Returns maxInt on overflow.
pub fn maxCompressedSize(input_size: usize) usize {
    const overhead = input_size / 255;
    const with_overhead = @addWithOverflow(input_size, overhead);
    if (with_overhead[1] != 0) return std.math.maxInt(usize);
    const with_header = @addWithOverflow(with_overhead[0], 16);
    if (with_header[1] != 0) return std.math.maxInt(usize);
    return with_header[0];
}

// Tests
test "compress and decompress empty" {
    const allocator = std.testing.allocator;

    const compressed = try compress("", allocator);
    defer allocator.free(compressed);

    var output: [0]u8 = undefined;
    const decompressed = try decompressInto(compressed, &output);
    try std.testing.expectEqual(@as(usize, 0), decompressed.len);
}

test "compress and decompress small" {
    const allocator = std.testing.allocator;
    const input = "Hello!";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    const decompressed = try decompressWithSize(compressed, input.len, allocator);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "compress and decompress with repeats" {
    const allocator = std.testing.allocator;
    const input = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    // Should compress well
    try std.testing.expect(compressed.len < input.len);

    const decompressed = try decompressWithSize(compressed, input.len, allocator);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "compress and decompress lorem ipsum" {
    const allocator = std.testing.allocator;
    const input = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
        "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    const decompressed = try decompressWithSize(compressed, input.len, allocator);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "decompress into insufficient buffer" {
    const allocator = std.testing.allocator;
    const input = "Hello, World! This is a test message.";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    var small_buffer: [10]u8 = undefined;
    const result = decompressInto(compressed, &small_buffer);
    try std.testing.expectError(Error.OutputTooSmall, result);
}

test "decompress truncated input" {
    const allocator = std.testing.allocator;
    const input = "Hello, World! This needs some repeated text text text.";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    // Truncate the compressed data
    if (compressed.len > 5) {
        var output: [100]u8 = undefined;
        const result = decompressInto(compressed[0 .. compressed.len / 2], &output);
        // Should fail with UnexpectedEof or InvalidData
        try std.testing.expect(result == Error.UnexpectedEof or result == Error.OutputTooSmall or result == Error.InvalidData);
    }
}

test "decompress invalid offset" {
    // Manually craft data with invalid back-reference offset
    // Token: 0x10 = 1 literal, 0 match length extension (min match = 4)
    // Literal: 'A'
    // Offset: 0x00 0x00 = 0 (invalid - must be > 0)
    const invalid_data = [_]u8{ 0x14, 'A', 0x00, 0x00 };
    var output: [100]u8 = undefined;
    const result = decompressInto(&invalid_data, &output);
    try std.testing.expectError(Error.InvalidData, result);
}

test "decompress offset larger than output" {
    // Token: 0x10 = 1 literal, match length 4
    // Literal: 'A'
    // Offset: 0x10 0x00 = 16 (larger than current output position of 1)
    const invalid_data = [_]u8{ 0x10, 'A', 0x10, 0x00 };
    var output: [100]u8 = undefined;
    const result = decompressInto(&invalid_data, &output);
    try std.testing.expectError(Error.InvalidData, result);
}

test "maxCompressedSize overflow" {
    // Test that maxCompressedSize handles near-max values without overflow
    const huge = std.math.maxInt(usize) - 100;
    const result = maxCompressedSize(huge);
    try std.testing.expectEqual(std.math.maxInt(usize), result);
}

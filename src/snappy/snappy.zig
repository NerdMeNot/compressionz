//! Snappy compression and decompression.
//!
//! Snappy is optimized for speed over compression ratio.
//!
//! ## Format
//! - Preamble: varint-encoded uncompressed length
//! - Data: sequence of literals and copies
//!
//! Element types (2-bit tag):
//! - 0b00: Literal
//! - 0b01: Copy with 1-byte offset
//! - 0b10: Copy with 2-byte offset
//! - 0b11: Copy with 4-byte offset

const std = @import("std");
const err = @import("../error.zig");
const Error = err.Error;
const shrinkAllocation = err.shrinkAllocation;

// SIMD vector types for accelerated operations
const Vec8 = @Vector(8, u8);
const Vec16 = @Vector(16, u8);

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

const TAG_LITERAL = 0;
const TAG_COPY1 = 1;
const TAG_COPY2 = 2;
const TAG_COPY4 = 3;

const HASH_LOG = 14;
const HASH_SIZE = 1 << HASH_LOG;

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

        // Compare vectors
        const eq_mask = src_vec == match_vec;
        const mask_int: u16 = @bitCast(eq_mask);

        if (mask_int != 0xFFFF) {
            // Found mismatch - count trailing matching bytes
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

/// Compress into provided buffer. Returns slice of written data.
pub fn compressInto(input: []const u8, output: []u8) Error![]u8 {
    if (output.len < maxCompressedSize(input.len)) {
        return Error.OutputTooSmall;
    }

    var dst: usize = 0;

    // Write uncompressed length as varint
    var len = input.len;
    while (len >= 0x80) {
        output[dst] = @intCast((len & 0x7F) | 0x80);
        dst += 1;
        len >>= 7;
    }
    output[dst] = @intCast(len);
    dst += 1;

    if (input.len == 0) {
        return output[0..dst];
    }

    // For very small inputs, just emit literals
    if (input.len < 15) {
        dst = emitLiteral(output, dst, input);
        return output[0..dst];
    }

    // Hash table for finding matches
    var hash_table: [HASH_SIZE]u32 = undefined;
    @memset(&hash_table, 0);

    var src_idx: usize = 0;
    var anchor: usize = 0;

    const src_end = input.len;
    const match_limit = if (src_end > 4) src_end - 4 else 0;

    // Main compression loop
    while (src_idx < match_limit) {
        const hash_val = hash4(input[src_idx..]);
        const match_idx = hash_table[hash_val];
        hash_table[hash_val] = @intCast(src_idx);

        // Check for valid match (u32 compare is faster than mem.eql)
        if (match_idx > 0 and
            src_idx - match_idx < 65536 and
            src_idx > match_idx and
            std.mem.readInt(u32, input[match_idx..][0..4], .little) == std.mem.readInt(u32, input[src_idx..][0..4], .little))
        {
            // Emit pending literals
            if (src_idx > anchor) {
                dst = emitLiteral(output, dst, input[anchor..src_idx]);
            }

            // Count match length using SIMD-accelerated comparison
            const max_match = @min(src_end - src_idx, src_end - match_idx);
            const match_len = 4 + countMatchLength(
                input[src_idx + 4 ..],
                input[match_idx + 4 ..],
                max_match - 4,
            );

            // Emit copy
            const offset = src_idx - match_idx;
            dst = emitCopy(output, dst, offset, match_len);

            src_idx += match_len;
            anchor = src_idx;
        } else {
            src_idx += 1;
        }
    }

    // Emit remaining literals
    if (anchor < input.len) {
        dst = emitLiteral(output, dst, input[anchor..]);
    }

    return output[0..dst];
}

fn hash4(data: []const u8) u32 {
    if (data.len < 4) return 0;
    const val = std.mem.readInt(u32, data[0..4], .little);
    return @intCast((val *% 0x1E35A7BD) >> (32 - HASH_LOG));
}

fn emitLiteral(output: []u8, start: usize, literal: []const u8) usize {
    var dst = start;
    const n = literal.len;

    if (n < 60) {
        output[dst] = @intCast((n - 1) << 2 | TAG_LITERAL);
        dst += 1;
    } else if (n < 256) {
        output[dst] = 60 << 2 | TAG_LITERAL;
        output[dst + 1] = @intCast(n - 1);
        dst += 2;
    } else if (n < 65536) {
        output[dst] = 61 << 2 | TAG_LITERAL;
        std.mem.writeInt(u16, output[dst + 1 ..][0..2], @intCast(n - 1), .little);
        dst += 3;
    } else if (n < 16777216) {
        output[dst] = 62 << 2 | TAG_LITERAL;
        output[dst + 1] = @intCast((n - 1) & 0xFF);
        output[dst + 2] = @intCast(((n - 1) >> 8) & 0xFF);
        output[dst + 3] = @intCast(((n - 1) >> 16) & 0xFF);
        dst += 4;
    } else {
        output[dst] = 63 << 2 | TAG_LITERAL;
        std.mem.writeInt(u32, output[dst + 1 ..][0..4], @intCast(n - 1), .little);
        dst += 5;
    }

    @memcpy(output[dst..][0..n], literal);
    return dst + n;
}

fn emitCopy(output: []u8, start: usize, offset: usize, length: usize) usize {
    var dst = start;
    var len = length;

    // Emit copies in chunks
    while (len >= 68) {
        // Emit maximum copy (64 bytes) using COPY2
        output[dst] = 63 << 2 | 0 << 2 | TAG_COPY2;
        std.mem.writeInt(u16, output[dst + 1 ..][0..2], @intCast(offset), .little);
        dst += 3;
        len -= 64;
    }

    if (len > 64) {
        // Emit 60-byte copy
        output[dst] = 59 << 2 | 0 << 2 | TAG_COPY2;
        std.mem.writeInt(u16, output[dst + 1 ..][0..2], @intCast(offset), .little);
        dst += 3;
        len -= 60;
    }

    // Handle remaining length
    if (len >= 12 or offset >= 2048) {
        // Use COPY2 format
        output[dst] = @intCast((len - 1) << 2 | TAG_COPY2);
        std.mem.writeInt(u16, output[dst + 1 ..][0..2], @intCast(offset), .little);
        dst += 3;
    } else {
        // Use COPY1 format (4-11 bytes, offset < 2048)
        output[dst] = @intCast(((offset >> 8) << 5) | ((len - 4) << 2) | TAG_COPY1);
        output[dst + 1] = @intCast(offset & 0xFF);
        dst += 2;
    }

    return dst;
}

/// Decompress data into a newly allocated buffer.
pub fn decompress(input: []const u8, allocator: std.mem.Allocator) Error![]u8 {
    return decompressWithLimit(input, allocator, null);
}

/// Decompress with optional size limit (protection against decompression bombs).
pub fn decompressWithLimit(input: []const u8, allocator: std.mem.Allocator, max_output_size: ?usize) Error![]u8 {
    // Read uncompressed length
    const len_result = readVarint(input) catch return Error.InvalidData;
    const uncompressed_len = len_result.value;

    // Check against limit before allocating
    if (max_output_size) |limit| {
        if (uncompressed_len > limit) return Error.OutputTooLarge;
    }

    const output = allocator.alloc(u8, uncompressed_len) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    // Use internal function to avoid re-parsing varint
    const result = try decompressData(input, len_result.bytes_read, uncompressed_len, output);

    if (result.len != uncompressed_len) {
        return Error.InvalidData;
    }

    return output;
}

/// Decompress into provided buffer.
pub fn decompressInto(input: []const u8, output: []u8) Error![]u8 {
    // Read uncompressed length
    const len_result = readVarint(input) catch return Error.InvalidData;
    const uncompressed_len = len_result.value;

    if (uncompressed_len > output.len) {
        return Error.OutputTooSmall;
    }

    return decompressData(input, len_result.bytes_read, uncompressed_len, output);
}

/// Internal: decompress data starting at given offset with known length.
fn decompressData(input: []const u8, start_offset: usize, uncompressed_len: usize, output: []u8) Error![]u8 {
    var src = start_offset;
    var dst: usize = 0;

    while (src < input.len and dst < uncompressed_len) {
        const tag = input[src] & 0x03;
        const tag_byte = input[src];
        src += 1;

        switch (@as(u2, @intCast(tag))) {
            TAG_LITERAL => {
                var len: usize = (tag_byte >> 2) + 1;

                if (len > 60) {
                    const extra_bytes = len - 60;
                    if (src + extra_bytes > input.len) return Error.UnexpectedEof;
                    len = 1;
                    for (0..extra_bytes) |i| {
                        len += @as(usize, input[src + i]) << @intCast(i * 8);
                    }
                    src += extra_bytes;
                }

                if (src + len > input.len) return Error.UnexpectedEof;
                if (dst + len > output.len) return Error.OutputTooSmall;

                @memcpy(output[dst..][0..len], input[src..][0..len]);
                src += len;
                dst += len;
            },
            TAG_COPY1 => {
                if (src >= input.len) return Error.UnexpectedEof;

                const len: usize = 4 + ((tag_byte >> 2) & 0x07);
                const offset: usize = (@as(usize, tag_byte >> 5) << 8) | input[src];
                src += 1;

                if (offset == 0 or offset > dst) return Error.InvalidData;
                if (dst + len > output.len) return Error.OutputTooSmall;

                // Copy with SIMD acceleration when possible
                copyMatch(output, dst, offset, len);
                dst += len;
            },
            TAG_COPY2 => {
                if (src + 2 > input.len) return Error.UnexpectedEof;

                const len: usize = 1 + (tag_byte >> 2);
                const offset: usize = std.mem.readInt(u16, input[src..][0..2], .little);
                src += 2;

                if (offset == 0 or offset > dst) return Error.InvalidData;
                if (dst + len > output.len) return Error.OutputTooSmall;

                copyMatch(output, dst, offset, len);
                dst += len;
            },
            TAG_COPY4 => {
                if (src + 4 > input.len) return Error.UnexpectedEof;

                const len: usize = 1 + (tag_byte >> 2);
                const offset: usize = std.mem.readInt(u32, input[src..][0..4], .little);
                src += 4;

                if (offset == 0 or offset > dst) return Error.InvalidData;
                if (dst + len > output.len) return Error.OutputTooSmall;

                copyMatch(output, dst, offset, len);
                dst += len;
            },
        }
    }

    return output[0..dst];
}

/// Get decompressed size from header (fast, no decompression).
pub fn getDecompressedSize(input: []const u8) Error!usize {
    const result = readVarint(input) catch return Error.InvalidData;
    return result.value;
}

/// Maximum compressed size for given input.
/// Returns null if the calculation would overflow.
pub fn maxCompressedSize(input_size: usize) usize {
    // Snappy worst case: 32 + input + input/6
    const overhead = input_size / 6;
    const with_overhead = @addWithOverflow(input_size, overhead);
    if (with_overhead[1] != 0) return std.math.maxInt(usize);
    const with_header = @addWithOverflow(with_overhead[0], 32);
    if (with_header[1] != 0) return std.math.maxInt(usize);
    return with_header[0];
}

fn readVarint(data: []const u8) !struct { value: usize, bytes_read: usize } {
    var value: usize = 0;
    var shift: u7 = 0; // u7 to handle up to 10 iterations (max shift = 63)
    var i: usize = 0;

    // Max 10 bytes for 64-bit varint, but check shift doesn't exceed usize bits
    const max_shift: u7 = @bitSizeOf(usize) - 1;
    while (i < data.len and i < 10) {
        const b = data[i];
        if (shift > max_shift) {
            return error.InvalidVarint; // Overflow protection
        }
        value |= @as(usize, b & 0x7F) << @intCast(shift);
        i += 1;
        if ((b & 0x80) == 0) {
            return .{ .value = value, .bytes_read = i };
        }
        shift += 7;
    }

    return error.InvalidVarint;
}

// Tests
test "snappy compress and decompress empty" {
    const allocator = std.testing.allocator;

    const compressed = try compress("", allocator);
    defer allocator.free(compressed);

    const decompressed = try decompress(compressed, allocator);
    defer allocator.free(decompressed);

    try std.testing.expectEqual(@as(usize, 0), decompressed.len);
}

test "snappy compress and decompress small" {
    const allocator = std.testing.allocator;
    const input = "Hello!";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    const decompressed = try decompress(compressed, allocator);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "snappy compress and decompress with repeats" {
    const allocator = std.testing.allocator;
    const input = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    // Should compress well
    try std.testing.expect(compressed.len < input.len);

    const decompressed = try decompress(compressed, allocator);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "snappy compress and decompress lorem ipsum" {
    const allocator = std.testing.allocator;
    const input = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
        "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    const decompressed = try decompress(compressed, allocator);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "snappy get decompressed size" {
    const allocator = std.testing.allocator;
    const input = "Test for getting decompressed size.";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    const size = try getDecompressedSize(compressed);
    try std.testing.expectEqual(input.len, size);
}

test "snappy decompress truncated input" {
    const allocator = std.testing.allocator;
    const input = "Hello, World! This needs some repeated text text text.";

    const compressed = try compress(input, allocator);
    defer allocator.free(compressed);

    // Truncate the compressed data (but keep the varint header)
    if (compressed.len > 5) {
        const result = decompress(compressed[0 .. compressed.len / 2], allocator);
        // Should fail with UnexpectedEof or InvalidData
        try std.testing.expect(result == Error.UnexpectedEof or result == Error.InvalidData);
    }
}

test "snappy decompress empty input" {
    const allocator = std.testing.allocator;
    const result = decompress("", allocator);
    // Empty input is invalid - no varint length can be read
    try std.testing.expectError(Error.InvalidData, result);
}

test "snappy decompress invalid copy offset" {
    const allocator = std.testing.allocator;
    // Craft input that claims a certain uncompressed length but has an invalid copy
    // Snappy copy-1 format: tag byte = 0bXXX_YYY_01 where XXX=offset_high, YYY=len-4
    // followed by offset_low byte
    // We need: valid literal first, then copy with offset > current position
    const invalid_data = [_]u8{
        10, // varint: uncompressed length = 10
        0x10, // literal tag: (0x10 >> 2) + 1 = 5 bytes
        'H', 'e', 'l', 'l', 'o', // 5 literal bytes (position now 5)
        0b111_000_01, // copy-1: len=4, offset_high=7
        0xFF, // offset_low=255, total offset = 7*256 + 255 = 2047 (way > 5)
    };
    const result = decompress(&invalid_data, allocator);
    // May return InvalidData or UnexpectedEof depending on validation order
    try std.testing.expect(result == Error.InvalidData or result == Error.UnexpectedEof);
}

test "snappy maxCompressedSize overflow" {
    const huge = std.math.maxInt(usize) - 100;
    const result = maxCompressedSize(huge);
    try std.testing.expectEqual(std.math.maxInt(usize), result);
}

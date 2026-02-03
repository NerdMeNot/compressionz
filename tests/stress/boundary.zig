//! Stress tests: Block size boundary conditions.
//!
//! Tests behavior at exact block boundaries and edge cases
//! for internal buffer sizes.

const std = @import("std");
const cz = @import("compressionz");
const lz4 = cz.lz4;

const testing = std.testing;

// Common block sizes used by compression algorithms
const KB = 1024;

const BLOCK_SIZES = [_]usize{
    64, // LZ4 minimum
    256,
    512,
    1 * KB,
    4 * KB, // Common page size
    8 * KB,
    16 * KB,
    32 * KB,
    64 * KB, // LZ4 default block
    128 * KB,
    256 * KB,
    512 * KB,
    1024 * KB, // 1 MB
    4 * 1024 * KB, // 4 MB - LZ4 max block
};

// =============================================================================
// Exact Block Size Tests
// =============================================================================

test "exact block sizes - gzip" {
    const allocator = testing.allocator;

    for (BLOCK_SIZES) |size| {
        if (size > 1024 * KB) continue; // Skip very large for speed

        const input = try allocator.alloc(u8, size);
        defer allocator.free(input);
        @memset(input, 'X');

        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqual(size, decompressed.len);
    }
}

test "exact block sizes - lz4" {
    const allocator = testing.allocator;

    for (BLOCK_SIZES) |size| {
        if (size > 1024 * KB) continue;

        const input = try allocator.alloc(u8, size);
        defer allocator.free(input);
        @memset(input, 'Y');

        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqual(size, decompressed.len);
    }
}

test "exact block sizes - zstd" {
    const allocator = testing.allocator;

    for (BLOCK_SIZES) |size| {
        if (size > 1024 * KB) continue;

        const input = try allocator.alloc(u8, size);
        defer allocator.free(input);
        @memset(input, 'Z');

        const compressed = try cz.zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqual(size, decompressed.len);
    }
}

// =============================================================================
// Block Size +/- 1 Tests
// =============================================================================

test "block size boundaries - off by one" {
    const allocator = testing.allocator;

    for (BLOCK_SIZES[0..8]) |size| { // Test smaller sizes for speed
        const sizes_to_test = [_]usize{ size - 1, size, size + 1 };

        for (sizes_to_test) |test_size| {
            if (test_size == 0) continue;

            const input = try allocator.alloc(u8, test_size);
            defer allocator.free(input);
            for (input, 0..) |*b, i| {
                b.* = @intCast(i % 256);
            }

            // gzip
            {
                const compressed = try cz.gzip.compress(input, allocator, .{});
                defer allocator.free(compressed);
                const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
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
            // zstd
            {
                const compressed = try cz.zstd.compress(input, allocator, .{});
                defer allocator.free(compressed);
                const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
                defer allocator.free(decompressed);
                try testing.expectEqualSlices(u8, input, decompressed);
            }
        }
    }
}

// =============================================================================
// LZ4 Block Size Options
// =============================================================================

test "lz4 frame: all block sizes" {
    const allocator = testing.allocator;
    const input = "Test data for LZ4 block size testing. " ** 100;

    const block_sizes = [_]lz4.BlockSize{ .@"64KB", .@"256KB", .@"1MB", .@"4MB" };

    for (block_sizes) |block_size| {
        const compressed = try lz4.frame.compress(input, allocator, .{ .block_size = block_size });
        defer allocator.free(compressed);

        const decompressed = try lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualStrings(input, decompressed);
    }
}

// =============================================================================
// Power of Two Tests
// =============================================================================

test "powers of two sizes" {
    const allocator = testing.allocator;

    var size: usize = 1;
    while (size <= 64 * KB) : (size *= 2) {
        const input = try allocator.alloc(u8, size);
        defer allocator.free(input);
        @memset(input, @intCast(size % 256));

        const compressed = try cz.gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqual(size, decompressed.len);
    }
}

// =============================================================================
// Prime Number Sizes (Non-aligned)
// =============================================================================

test "prime number sizes" {
    const allocator = testing.allocator;

    const primes = [_]usize{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 127, 251, 509, 1021, 2039, 4093, 8191, 16381 };

    for (primes) |size| {
        const input = try allocator.alloc(u8, size);
        defer allocator.free(input);
        for (input, 0..) |*b, i| {
            b.* = @intCast((i * 7) % 256);
        }

        const compressed = try cz.lz4.frame.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualSlices(u8, input, decompressed);
    }
}

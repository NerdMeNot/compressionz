//! Fuzz tests: Random and malformed input testing.
//!
//! These tests generate random inputs to stress-test decoders and
//! ensure they handle arbitrary data without crashing.
//!
//! The tests use deterministic seeding for reproducibility.

const std = @import("std");
const cz = @import("compressionz");
const Error = cz.Error;

const testing = std.testing;

// Number of iterations for fuzz tests
// Kept low for CI - increase for more thorough local testing
const FUZZ_ITERATIONS = 10;

/// Generate random bytes with given seed
fn generateRandomBytes(allocator: std.mem.Allocator, size: usize, seed: u64) ![]u8 {
    const data = try allocator.alloc(u8, size);
    var rng = std.Random.DefaultPrng.init(seed);
    rng.fill(data);
    return data;
}

/// Generate bytes that look somewhat like compressed data
fn generatePseudoCompressed(allocator: std.mem.Allocator, size: usize, seed: u64) ![]u8 {
    const data = try allocator.alloc(u8, size);
    var rng = std.Random.DefaultPrng.init(seed);

    // Mix of common compressed data patterns
    for (data, 0..) |*b, i| {
        const r = rng.random().int(u8);
        if (i < 4) {
            // Might be magic number
            b.* = r;
        } else if (r < 50) {
            // Repeated byte
            b.* = 0;
        } else if (r < 100) {
            // Common value
            b.* = 0xFF;
        } else if (r < 150) {
            // ASCII-ish
            b.* = @intCast(32 + (r % 95));
        } else {
            // Random
            b.* = r;
        }
    }
    return data;
}

// =============================================================================
// Random Input Fuzz Tests
// =============================================================================

test "fuzz: random bytes to all decoders" {
    const allocator = testing.allocator;

    for (0..FUZZ_ITERATIONS) |i| {
        const size = (i % 256) + 1; // 1 to 256 bytes
        const seed = @as(u64, @intCast(i)) * 12345;

        const random_data = try generateRandomBytes(allocator, size, seed);
        defer allocator.free(random_data);

        // Try to decompress with each codec - should either fail gracefully or succeed
        // Use max_output_size to prevent memory explosion from corrupted size fields

        // Gzip
        {
            const result = cz.gzip.decompress(random_data, allocator, .{ .max_output_size = 1024 * 1024 });
            if (result) |data| allocator.free(data) else |_| {}
        }

        // Zlib
        {
            const result = cz.zlib.decompress(random_data, allocator, .{ .max_output_size = 1024 * 1024 });
            if (result) |data| allocator.free(data) else |_| {}
        }

        // Zstd
        {
            const result = cz.zstd.decompress(random_data, allocator, .{ .max_output_size = 1024 * 1024 });
            if (result) |data| allocator.free(data) else |_| {}
        }

        // LZ4 Frame
        {
            const result = cz.lz4.frame.decompress(random_data, allocator, .{ .max_output_size = 1024 * 1024 });
            if (result) |data| allocator.free(data) else |_| {}
        }

        // Brotli
        {
            const result = cz.brotli.decompress(random_data, allocator, .{ .max_output_size = 1024 * 1024 });
            if (result) |data| allocator.free(data) else |_| {}
        }
    }
}

test "fuzz: pseudo-compressed data to all decoders" {
    const allocator = testing.allocator;

    for (0..FUZZ_ITERATIONS) |i| {
        const size = (i % 512) + 8; // 8 to 520 bytes
        const seed = @as(u64, @intCast(i)) * 67890;

        const pseudo_data = try generatePseudoCompressed(allocator, size, seed);
        defer allocator.free(pseudo_data);

        // Use max_output_size to prevent memory explosion from corrupted size fields

        // Gzip
        {
            const result = cz.gzip.decompress(pseudo_data, allocator, .{ .max_output_size = 1024 * 1024 });
            if (result) |data| allocator.free(data) else |_| {}
        }

        // Zstd
        {
            const result = cz.zstd.decompress(pseudo_data, allocator, .{ .max_output_size = 1024 * 1024 });
            if (result) |data| allocator.free(data) else |_| {}
        }

        // LZ4 Frame
        {
            const result = cz.lz4.frame.decompress(pseudo_data, allocator, .{ .max_output_size = 1024 * 1024 });
            if (result) |data| allocator.free(data) else |_| {}
        }

        // Brotli
        {
            const result = cz.brotli.decompress(pseudo_data, allocator, .{ .max_output_size = 1024 * 1024 });
            if (result) |data| allocator.free(data) else |_| {}
        }
    }
}

// =============================================================================
// Mutation Fuzz Tests
// =============================================================================

test "fuzz: mutate valid compressed data - gzip" {
    const allocator = testing.allocator;
    const input = "Original data for mutation testing.";

    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    var rng = std.Random.DefaultPrng.init(42);

    for (0..FUZZ_ITERATIONS) |_| {
        // Create mutated copy
        var mutated = try allocator.alloc(u8, compressed.len);
        defer allocator.free(mutated);
        @memcpy(mutated, compressed);

        // Apply random mutations
        const num_mutations = rng.random().intRangeAtMost(usize, 1, 5);
        for (0..num_mutations) |_| {
            const pos = rng.random().uintLessThan(usize, mutated.len);
            mutated[pos] = rng.random().int(u8);
        }

        // Try to decompress - should not crash
        // Use max_output_size to prevent memory explosion from corrupted size fields
        const result = cz.gzip.decompress(mutated, allocator, .{ .max_output_size = 1024 * 1024 });
        if (result) |data| allocator.free(data) else |_| {}
    }
}

test "fuzz: mutate valid compressed data - lz4" {
    const allocator = testing.allocator;
    const input = "Original data for LZ4 mutation testing.";

    const compressed = try cz.lz4.frame.compress(input, allocator, .{});
    defer allocator.free(compressed);

    var rng = std.Random.DefaultPrng.init(123);

    for (0..FUZZ_ITERATIONS) |_| {
        var mutated = try allocator.alloc(u8, compressed.len);
        defer allocator.free(mutated);
        @memcpy(mutated, compressed);

        const num_mutations = rng.random().intRangeAtMost(usize, 1, 5);
        for (0..num_mutations) |_| {
            const pos = rng.random().uintLessThan(usize, mutated.len);
            mutated[pos] = rng.random().int(u8);
        }

        // Use max_output_size to prevent memory explosion from corrupted size fields
        const result = cz.lz4.frame.decompress(mutated, allocator, .{ .max_output_size = 1024 * 1024 });
        if (result) |data| allocator.free(data) else |_| {}
    }
}

test "fuzz: mutate valid compressed data - zstd" {
    const allocator = testing.allocator;
    const input = "Original data for Zstd mutation testing.";

    const compressed = try cz.zstd.compress(input, allocator, .{});
    defer allocator.free(compressed);

    var rng = std.Random.DefaultPrng.init(456);

    for (0..FUZZ_ITERATIONS) |_| {
        var mutated = try allocator.alloc(u8, compressed.len);
        defer allocator.free(mutated);
        @memcpy(mutated, compressed);

        const num_mutations = rng.random().intRangeAtMost(usize, 1, 5);
        for (0..num_mutations) |_| {
            const pos = rng.random().uintLessThan(usize, mutated.len);
            mutated[pos] = rng.random().int(u8);
        }

        // Use max_output_size to prevent memory explosion from corrupted size fields
        const result = cz.zstd.decompress(mutated, allocator, .{ .max_output_size = 1024 * 1024 });
        if (result) |data| allocator.free(data) else |_| {}
    }
}

// =============================================================================
// Truncation Fuzz Tests
// =============================================================================

test "fuzz: truncate at random positions - gzip" {
    const allocator = testing.allocator;
    const input = "Data to compress and then truncate at various positions for testing.";

    var rng = std.Random.DefaultPrng.init(789);

    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    for (0..5) |_| {
        if (compressed.len < 2) continue;

        const truncate_at = rng.random().intRangeAtMost(usize, 1, compressed.len - 1);
        const truncated = compressed[0..truncate_at];

        // Use max_output_size to prevent memory explosion from corrupted size fields
        const result = cz.gzip.decompress(truncated, allocator, .{ .max_output_size = 1024 * 1024 });
        if (result) |data| allocator.free(data) else |_| {}
    }
}

test "fuzz: truncate at random positions - zstd" {
    const allocator = testing.allocator;
    const input = "Data to compress and then truncate at various positions for testing.";

    var rng = std.Random.DefaultPrng.init(790);

    const compressed = try cz.zstd.compress(input, allocator, .{});
    defer allocator.free(compressed);

    for (0..5) |_| {
        if (compressed.len < 2) continue;

        const truncate_at = rng.random().intRangeAtMost(usize, 1, compressed.len - 1);
        const truncated = compressed[0..truncate_at];

        const result = cz.zstd.decompress(truncated, allocator, .{ .max_output_size = 1024 * 1024 });
        if (result) |data| allocator.free(data) else |_| {}
    }
}

test "fuzz: truncate at random positions - lz4" {
    const allocator = testing.allocator;
    const input = "Data to compress and then truncate at various positions for testing.";

    var rng = std.Random.DefaultPrng.init(791);

    const compressed = try cz.lz4.frame.compress(input, allocator, .{});
    defer allocator.free(compressed);

    for (0..5) |_| {
        if (compressed.len < 2) continue;

        const truncate_at = rng.random().intRangeAtMost(usize, 1, compressed.len - 1);
        const truncated = compressed[0..truncate_at];

        const result = cz.lz4.frame.decompress(truncated, allocator, .{ .max_output_size = 1024 * 1024 });
        if (result) |data| allocator.free(data) else |_| {}
    }
}

// =============================================================================
// Size Variation Fuzz Tests
// =============================================================================

test "fuzz: various sizes round-trip" {
    const allocator = testing.allocator;

    var rng = std.Random.DefaultPrng.init(999);

    for (0..10) |_| {
        const size = rng.random().intRangeAtMost(usize, 0, 5000);
        const data = try allocator.alloc(u8, size);
        defer allocator.free(data);
        rng.fill(data);

        // Gzip
        {
            const compressed = cz.gzip.compress(data, allocator, .{}) catch continue;
            defer allocator.free(compressed);

            const decompressed = cz.gzip.decompress(compressed, allocator, .{}) catch continue;
            defer allocator.free(decompressed);

            try testing.expectEqualSlices(u8, data, decompressed);
        }

        // LZ4 Frame
        {
            const compressed = cz.lz4.frame.compress(data, allocator, .{}) catch continue;
            defer allocator.free(compressed);

            const decompressed = cz.lz4.frame.decompress(compressed, allocator, .{}) catch continue;
            defer allocator.free(decompressed);

            try testing.expectEqualSlices(u8, data, decompressed);
        }

        // Zstd
        {
            const compressed = cz.zstd.compress(data, allocator, .{}) catch continue;
            defer allocator.free(compressed);

            const decompressed = cz.zstd.decompress(compressed, allocator, .{}) catch continue;
            defer allocator.free(decompressed);

            try testing.expectEqualSlices(u8, data, decompressed);
        }

        // Snappy
        {
            const compressed = cz.snappy.compress(data, allocator) catch continue;
            defer allocator.free(compressed);

            const decompressed = cz.snappy.decompress(compressed, allocator) catch continue;
            defer allocator.free(decompressed);

            try testing.expectEqualSlices(u8, data, decompressed);
        }
    }
}

// =============================================================================
// Edge Case Patterns
// =============================================================================

test "fuzz: all zeros various sizes" {
    const allocator = testing.allocator;
    const sizes = [_]usize{ 0, 1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 255, 256, 511, 512, 1023, 1024, 4095, 4096 };

    for (sizes) |size| {
        const data = try allocator.alloc(u8, size);
        defer allocator.free(data);
        @memset(data, 0);

        const compressed = try cz.gzip.compress(data, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualSlices(u8, data, decompressed);
    }
}

test "fuzz: all 0xFF various sizes" {
    const allocator = testing.allocator;
    const sizes = [_]usize{ 1, 16, 64, 256, 1024, 4096 };

    for (sizes) |size| {
        const data = try allocator.alloc(u8, size);
        defer allocator.free(data);
        @memset(data, 0xFF);

        const compressed = try cz.lz4.frame.compress(data, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualSlices(u8, data, decompressed);
    }
}

test "fuzz: alternating bytes" {
    const allocator = testing.allocator;

    for ([_]usize{ 100, 1000, 5000 }) |size| {
        const data = try allocator.alloc(u8, size);
        defer allocator.free(data);
        for (data, 0..) |*b, i| {
            b.* = if (i % 2 == 0) 0xAA else 0x55;
        }

        const compressed = try cz.zstd.compress(data, allocator, .{});
        defer allocator.free(compressed);

        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try testing.expectEqualSlices(u8, data, decompressed);
    }
}

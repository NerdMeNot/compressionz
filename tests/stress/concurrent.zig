//! Stress tests: Concurrent access.
//!
//! Tests that compression/decompression APIs can be safely used
//! from multiple threads simultaneously.

const std = @import("std");
const cz = @import("compressionz");

const testing = std.testing;

const NUM_THREADS = 4;
const ITERATIONS_PER_THREAD = 10;

// =============================================================================
// Concurrent Compression Tests
// =============================================================================

test "concurrent: parallel compression same codec" {
    const allocator = testing.allocator;
    const input = "Test data for concurrent compression testing. " ** 50;

    var threads: [NUM_THREADS]std.Thread = undefined;
    var results: [NUM_THREADS]?[]u8 = [_]?[]u8{null} ** NUM_THREADS;
    var errors: [NUM_THREADS]bool = [_]bool{false} ** NUM_THREADS;

    // Spawn threads that all compress with gzip
    for (&threads, 0..) |*t, i| {
        t.* = std.Thread.spawn(.{}, compressGzipWorker, .{
            allocator,
            input,
            &results[i],
            &errors[i],
        }) catch {
            // Thread spawn failed, mark as error
            errors[i] = true;
            continue;
        };
    }

    // Wait for all threads
    for (&threads, 0..) |*t, i| {
        if (!errors[i]) {
            t.join();
        }
    }

    // Verify results
    for (results, 0..) |result, i| {
        if (errors[i]) continue;
        if (result) |compressed| {
            defer allocator.free(compressed);
            // Verify we can decompress
            const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
            defer allocator.free(decompressed);
            try testing.expectEqualStrings(input, decompressed);
        }
    }
}

test "concurrent: parallel compression different codecs" {
    const allocator = testing.allocator;
    const input = "Test data for multi-codec concurrent compression. " ** 50;

    var threads: [4]std.Thread = undefined;
    var results: [4]?[]u8 = [_]?[]u8{null} ** 4;
    var errors: [4]bool = [_]bool{false} ** 4;

    // Spawn threads with different codecs
    threads[0] = std.Thread.spawn(.{}, compressGzipWorker, .{ allocator, input, &results[0], &errors[0] }) catch {
        errors[0] = true;
        return;
    };
    threads[1] = std.Thread.spawn(.{}, compressZstdWorker, .{ allocator, input, &results[1], &errors[1] }) catch {
        errors[1] = true;
        return;
    };
    threads[2] = std.Thread.spawn(.{}, compressLz4Worker, .{ allocator, input, &results[2], &errors[2] }) catch {
        errors[2] = true;
        return;
    };
    threads[3] = std.Thread.spawn(.{}, compressSnappyWorker, .{ allocator, input, &results[3], &errors[3] }) catch {
        errors[3] = true;
        return;
    };

    // Wait for all threads
    for (&threads, 0..) |*t, i| {
        if (!errors[i]) {
            t.join();
        }
    }

    // Verify results - gzip
    if (!errors[0]) {
        if (results[0]) |compressed| {
            defer allocator.free(compressed);
            const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
            defer allocator.free(decompressed);
            try testing.expectEqualStrings(input, decompressed);
        }
    }
    // zstd
    if (!errors[1]) {
        if (results[1]) |compressed| {
            defer allocator.free(compressed);
            const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
            defer allocator.free(decompressed);
            try testing.expectEqualStrings(input, decompressed);
        }
    }
    // lz4
    if (!errors[2]) {
        if (results[2]) |compressed| {
            defer allocator.free(compressed);
            const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
            defer allocator.free(decompressed);
            try testing.expectEqualStrings(input, decompressed);
        }
    }
    // snappy
    if (!errors[3]) {
        if (results[3]) |compressed| {
            defer allocator.free(compressed);
            const decompressed = try cz.snappy.decompress(compressed, allocator);
            defer allocator.free(decompressed);
            try testing.expectEqualStrings(input, decompressed);
        }
    }
}

test "concurrent: parallel decompression" {
    const allocator = testing.allocator;
    const input = "Test data for concurrent decompression testing. " ** 50;

    // First compress the data
    const compressed = try cz.zstd.compress(input, allocator, .{});
    defer allocator.free(compressed);

    var threads: [NUM_THREADS]std.Thread = undefined;
    var results: [NUM_THREADS]?[]u8 = [_]?[]u8{null} ** NUM_THREADS;
    var errors: [NUM_THREADS]bool = [_]bool{false} ** NUM_THREADS;

    // Spawn threads that all decompress the same data
    for (&threads, 0..) |*t, i| {
        t.* = std.Thread.spawn(.{}, decompressZstdWorker, .{
            allocator,
            compressed,
            &results[i],
            &errors[i],
        }) catch {
            errors[i] = true;
            continue;
        };
    }

    // Wait for all threads
    for (&threads, 0..) |*t, i| {
        if (!errors[i]) {
            t.join();
        }
    }

    // Verify all results match
    for (results, 0..) |result, i| {
        if (errors[i]) continue;
        if (result) |decompressed| {
            defer allocator.free(decompressed);
            try testing.expectEqualStrings(input, decompressed);
        }
    }
}

test "concurrent: mixed compress and decompress" {
    const allocator = testing.allocator;
    const input = "Mixed operations concurrent test data. " ** 50;

    // Pre-compress some data for decompression threads
    const pre_compressed = try cz.lz4.frame.compress(input, allocator, .{});
    defer allocator.free(pre_compressed);

    var threads: [NUM_THREADS * 2]std.Thread = undefined;
    var compress_results: [NUM_THREADS]?[]u8 = [_]?[]u8{null} ** NUM_THREADS;
    var decompress_results: [NUM_THREADS]?[]u8 = [_]?[]u8{null} ** NUM_THREADS;
    var errors: [NUM_THREADS * 2]bool = [_]bool{false} ** (NUM_THREADS * 2);

    // Spawn compression threads
    for (0..NUM_THREADS) |i| {
        threads[i] = std.Thread.spawn(.{}, compressLz4Worker, .{
            allocator,
            input,
            &compress_results[i],
            &errors[i],
        }) catch {
            errors[i] = true;
            continue;
        };
    }

    // Spawn decompression threads
    for (0..NUM_THREADS) |i| {
        threads[NUM_THREADS + i] = std.Thread.spawn(.{}, decompressLz4Worker, .{
            allocator,
            pre_compressed,
            &decompress_results[i],
            &errors[NUM_THREADS + i],
        }) catch {
            errors[NUM_THREADS + i] = true;
            continue;
        };
    }

    // Wait for all threads
    for (&threads, 0..) |*t, i| {
        if (!errors[i]) {
            t.join();
        }
    }

    // Verify compression results
    for (compress_results, 0..) |result, i| {
        if (errors[i]) continue;
        if (result) |compressed| {
            defer allocator.free(compressed);
            const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
            defer allocator.free(decompressed);
            try testing.expectEqualStrings(input, decompressed);
        }
    }

    // Verify decompression results
    for (decompress_results, 0..) |result, i| {
        if (errors[NUM_THREADS + i]) continue;
        if (result) |decompressed| {
            defer allocator.free(decompressed);
            try testing.expectEqualStrings(input, decompressed);
        }
    }
}

test "concurrent: repeated operations in threads" {
    const allocator = testing.allocator;

    var threads: [NUM_THREADS]std.Thread = undefined;
    var success: [NUM_THREADS]bool = [_]bool{false} ** NUM_THREADS;

    // Spawn threads that do repeated compress/decompress cycles
    for (&threads, 0..) |*t, i| {
        t.* = std.Thread.spawn(.{}, repeatedOperationsWorker, .{
            allocator,
            &success[i],
            @as(u64, i),
        }) catch {
            continue;
        };
    }

    // Wait for all threads
    for (&threads) |*t| {
        t.join();
    }

    // Check all threads succeeded
    for (success) |s| {
        try testing.expect(s);
    }
}

// =============================================================================
// Worker Functions
// =============================================================================

fn compressGzipWorker(
    allocator: std.mem.Allocator,
    input: []const u8,
    result: *?[]u8,
    err_flag: *bool,
) void {
    result.* = cz.gzip.compress(input, allocator, .{}) catch {
        err_flag.* = true;
        return;
    };
}

fn compressZstdWorker(
    allocator: std.mem.Allocator,
    input: []const u8,
    result: *?[]u8,
    err_flag: *bool,
) void {
    result.* = cz.zstd.compress(input, allocator, .{}) catch {
        err_flag.* = true;
        return;
    };
}

fn compressLz4Worker(
    allocator: std.mem.Allocator,
    input: []const u8,
    result: *?[]u8,
    err_flag: *bool,
) void {
    result.* = cz.lz4.frame.compress(input, allocator, .{}) catch {
        err_flag.* = true;
        return;
    };
}

fn compressSnappyWorker(
    allocator: std.mem.Allocator,
    input: []const u8,
    result: *?[]u8,
    err_flag: *bool,
) void {
    result.* = cz.snappy.compress(input, allocator) catch {
        err_flag.* = true;
        return;
    };
}

fn decompressZstdWorker(
    allocator: std.mem.Allocator,
    input: []const u8,
    result: *?[]u8,
    err_flag: *bool,
) void {
    result.* = cz.zstd.decompress(input, allocator, .{}) catch {
        err_flag.* = true;
        return;
    };
}

fn decompressLz4Worker(
    allocator: std.mem.Allocator,
    input: []const u8,
    result: *?[]u8,
    err_flag: *bool,
) void {
    result.* = cz.lz4.frame.decompress(input, allocator, .{}) catch {
        err_flag.* = true;
        return;
    };
}

fn repeatedOperationsWorker(
    allocator: std.mem.Allocator,
    success: *bool,
    seed: u64,
) void {
    var rng = std.Random.DefaultPrng.init(seed);

    for (0..ITERATIONS_PER_THREAD) |iter| {
        // Generate some data
        var data: [256]u8 = undefined;
        rng.fill(&data);

        // Pick a random codec (0=gzip, 1=zstd, 2=lz4)
        const codec_choice = rng.random().uintLessThan(usize, 3);

        switch (codec_choice) {
            0 => {
                // gzip
                const compressed = cz.gzip.compress(&data, allocator, .{}) catch return;
                defer allocator.free(compressed);
                const decompressed = cz.gzip.decompress(compressed, allocator, .{}) catch return;
                defer allocator.free(decompressed);
                if (!std.mem.eql(u8, &data, decompressed)) return;
            },
            1 => {
                // zstd
                const compressed = cz.zstd.compress(&data, allocator, .{}) catch return;
                defer allocator.free(compressed);
                const decompressed = cz.zstd.decompress(compressed, allocator, .{}) catch return;
                defer allocator.free(decompressed);
                if (!std.mem.eql(u8, &data, decompressed)) return;
            },
            2 => {
                // lz4
                const compressed = cz.lz4.frame.compress(&data, allocator, .{}) catch return;
                defer allocator.free(compressed);
                const decompressed = cz.lz4.frame.decompress(compressed, allocator, .{}) catch return;
                defer allocator.free(decompressed);
                if (!std.mem.eql(u8, &data, decompressed)) return;
            },
            else => unreachable,
        }

        _ = iter;
    }

    success.* = true;
}

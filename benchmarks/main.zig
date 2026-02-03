//! Comprehensive compression benchmark suite.
//!
//! Measures:
//! - Compression/decompression time (wall clock)
//! - Compression ratio
//! - Memory allocations (bytes allocated)
//! - CPU time (user + system)
//!
//! Run with: zig build bench

const std = @import("std");
const builtin = @import("builtin");
const cz = @import("compressionz");

const CountingAllocator = @import("counting_allocator.zig").CountingAllocator;
const ResourceUsage = @import("resource_usage.zig").ResourceUsage;

const WARMUP_ITERS = 3;
const BENCH_ITERS = 20;

// Test data sizes
const DATA_SIZES = [_]usize{
    1_000, // 1 KB
    10_000, // 10 KB
    100_000, // 100 KB
    1_000_000, // 1 MB
};

const BenchResult = struct {
    codec_name: []const u8,
    level_name: []const u8,
    data_size: usize,
    compressed_size: usize,
    compress_time_us: f64,
    decompress_time_us: f64,
    compress_mem_bytes: usize,
    decompress_mem_bytes: usize,
    compress_cpu_us: f64,
    decompress_cpu_us: f64,

    /// Returns compression ratio as percentage (how much data was reduced).
    /// E.g., 99.5% means compressed is 0.5% of original size.
    fn ratioPercent(self: BenchResult) f64 {
        if (self.compressed_size == 0 or self.data_size == 0) return 0;
        const compressed_fraction = @as(f64, @floatFromInt(self.compressed_size)) /
            @as(f64, @floatFromInt(self.data_size));
        return (1.0 - compressed_fraction) * 100.0;
    }

    fn compressThroughputMBs(self: BenchResult) f64 {
        if (self.compress_time_us == 0) return 0;
        return @as(f64, @floatFromInt(self.data_size)) / self.compress_time_us;
    }

    fn decompressThroughputMBs(self: BenchResult) f64 {
        if (self.decompress_time_us == 0) return 0;
        return @as(f64, @floatFromInt(self.data_size)) / self.decompress_time_us;
    }
};

fn print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    print("\n", .{});
    print("=" ** 120 ++ "\n", .{});
    print("  COMPRESSIONZ BENCHMARK SUITE\n", .{});
    print("=" ** 120 ++ "\n", .{});
    print("\n", .{});
    print("Iterations: {} (warmup: {})\n", .{ BENCH_ITERS, WARMUP_ITERS });
    print("Platform: {s} {s}\n", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) });
    print("\n", .{});

    // Collect all results
    var results: std.ArrayList(BenchResult) = .{ .items = &.{}, .capacity = 0 };
    defer results.deinit(base_allocator);

    for (DATA_SIZES) |size| {
        print("-" ** 120 ++ "\n", .{});
        print("Data Size: {} bytes ({d:.1} KB)\n", .{ size, @as(f64, @floatFromInt(size)) / 1024.0 });
        print("-" ** 120 ++ "\n", .{});

        // Generate test data - mix of patterns for realistic compression
        const data = try generateTestData(base_allocator, size);
        defer base_allocator.free(data);

        printTableHeader();

        // LZ4 Frame
        for ([_]cz.Level{ .fast, .default }) |level| {
            const result = try benchmarkLz4Frame(base_allocator, data, level);
            try results.append(base_allocator, result);
            printResultRow(result);
        }

        // LZ4 Block (no levels)
        {
            const result = try benchmarkLz4Block(base_allocator, data);
            try results.append(base_allocator, result);
            printResultRow(result);
        }

        // Snappy (no levels)
        {
            const result = try benchmarkSnappy(base_allocator, data);
            try results.append(base_allocator, result);
            printResultRow(result);
        }

        // Zstd
        for ([_]cz.Level{ .fast, .default, .best }) |level| {
            const result = try benchmarkZstd(base_allocator, data, level);
            try results.append(base_allocator, result);
            printResultRow(result);
        }

        // Gzip
        for ([_]cz.Level{ .fast, .default, .best }) |level| {
            const result = try benchmarkGzip(base_allocator, data, level);
            try results.append(base_allocator, result);
            printResultRow(result);
        }

        // Brotli
        for ([_]cz.Level{ .fast, .default, .best }) |level| {
            const result = try benchmarkBrotli(base_allocator, data, level);
            try results.append(base_allocator, result);
            printResultRow(result);
        }

        print("\n", .{});
    }

    // Print summary
    printSummary(results.items);
}

fn generateTestData(allocator: std.mem.Allocator, size: usize) ![]u8 {
    const data = try allocator.alloc(u8, size);

    // Mix of patterns:
    // 1. Repetitive text (highly compressible)
    // 2. Sequential bytes (moderately compressible)
    // 3. Random-ish data (less compressible)

    const text = "The quick brown fox jumps over the lazy dog. ";
    const text_len = text.len;

    var i: usize = 0;
    while (i < size) {
        const section = (i / (size / 4)) % 4;
        switch (section) {
            0 => {
                // Repetitive text
                const idx = i % text_len;
                data[i] = text[idx];
            },
            1 => {
                // Sequential with small variations
                data[i] = @intCast((i * 7) % 256);
            },
            2 => {
                // Repetitive text again
                const idx = i % text_len;
                data[i] = text[idx];
            },
            else => {
                // More varied data
                data[i] = @intCast((i * 31 + 17) % 256);
            },
        }
        i += 1;
    }

    return data;
}

fn benchmarkLz4Frame(base_allocator: std.mem.Allocator, data: []const u8, level: cz.Level) !BenchResult {
    var counting = CountingAllocator.init(base_allocator);
    const allocator = counting.allocator();

    // Warmup
    for (0..WARMUP_ITERS) |_| {
        const compressed = cz.lz4.frame.compress(data, allocator, .{ .level = level }) catch {
            return errorResult("LZ4 Frame", levelName(level), data.len);
        };
        defer allocator.free(compressed);

        const decompressed = cz.lz4.frame.decompress(compressed, allocator, .{}) catch continue;
        allocator.free(decompressed);
    }

    counting.reset();

    // Benchmark compression
    var compress_time_total: u64 = 0;
    var compress_cpu_total: u64 = 0;
    var compressed_size: usize = 0;

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const compressed = cz.lz4.frame.compress(data, allocator, .{ .level = level }) catch {
            return errorResult("LZ4 Frame", levelName(level), data.len);
        };
        compressed_size = compressed.len;

        compress_time_total += timer.read();
        compress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(compressed);
    }

    const compress_mem = counting.peak_allocated;
    counting.reset();

    // Get compressed data for decompression benchmark
    const compressed = cz.lz4.frame.compress(data, allocator, .{ .level = level }) catch {
        return errorResult("LZ4 Frame", levelName(level), data.len);
    };
    defer allocator.free(compressed);

    // Benchmark decompression
    var decompress_time_total: u64 = 0;
    var decompress_cpu_total: u64 = 0;

    counting.reset();

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const decompressed = cz.lz4.frame.decompress(compressed, allocator, .{}) catch {
            return errorResult("LZ4 Frame", levelName(level), data.len);
        };

        decompress_time_total += timer.read();
        decompress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(decompressed);
    }

    const decompress_mem = counting.peak_allocated;

    return BenchResult{
        .codec_name = "LZ4 Frame",
        .level_name = levelName(level),
        .data_size = data.len,
        .compressed_size = compressed_size,
        .compress_time_us = @as(f64, @floatFromInt(compress_time_total)) / BENCH_ITERS / 1000.0,
        .decompress_time_us = @as(f64, @floatFromInt(decompress_time_total)) / BENCH_ITERS / 1000.0,
        .compress_mem_bytes = compress_mem,
        .decompress_mem_bytes = decompress_mem,
        .compress_cpu_us = @as(f64, @floatFromInt(compress_cpu_total)) / BENCH_ITERS / 1000.0,
        .decompress_cpu_us = @as(f64, @floatFromInt(decompress_cpu_total)) / BENCH_ITERS / 1000.0,
    };
}

fn benchmarkLz4Block(base_allocator: std.mem.Allocator, data: []const u8) !BenchResult {
    var counting = CountingAllocator.init(base_allocator);
    const allocator = counting.allocator();

    // Warmup
    for (0..WARMUP_ITERS) |_| {
        const compressed = cz.lz4.block.compress(data, allocator) catch {
            return errorResult("LZ4 Block", "default", data.len);
        };
        defer allocator.free(compressed);

        const decompressed = cz.lz4.block.decompressWithSize(compressed, data.len, allocator) catch continue;
        allocator.free(decompressed);
    }

    counting.reset();

    // Benchmark compression
    var compress_time_total: u64 = 0;
    var compress_cpu_total: u64 = 0;
    var compressed_size: usize = 0;

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const compressed = cz.lz4.block.compress(data, allocator) catch {
            return errorResult("LZ4 Block", "default", data.len);
        };
        compressed_size = compressed.len;

        compress_time_total += timer.read();
        compress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(compressed);
    }

    const compress_mem = counting.peak_allocated;
    counting.reset();

    // Get compressed data for decompression benchmark
    const compressed = cz.lz4.block.compress(data, allocator) catch {
        return errorResult("LZ4 Block", "default", data.len);
    };
    defer allocator.free(compressed);

    // Benchmark decompression
    var decompress_time_total: u64 = 0;
    var decompress_cpu_total: u64 = 0;

    counting.reset();

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const decompressed = cz.lz4.block.decompressWithSize(compressed, data.len, allocator) catch {
            return errorResult("LZ4 Block", "default", data.len);
        };

        decompress_time_total += timer.read();
        decompress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(decompressed);
    }

    const decompress_mem = counting.peak_allocated;

    return BenchResult{
        .codec_name = "LZ4 Block",
        .level_name = "default",
        .data_size = data.len,
        .compressed_size = compressed_size,
        .compress_time_us = @as(f64, @floatFromInt(compress_time_total)) / BENCH_ITERS / 1000.0,
        .decompress_time_us = @as(f64, @floatFromInt(decompress_time_total)) / BENCH_ITERS / 1000.0,
        .compress_mem_bytes = compress_mem,
        .decompress_mem_bytes = decompress_mem,
        .compress_cpu_us = @as(f64, @floatFromInt(compress_cpu_total)) / BENCH_ITERS / 1000.0,
        .decompress_cpu_us = @as(f64, @floatFromInt(decompress_cpu_total)) / BENCH_ITERS / 1000.0,
    };
}

fn benchmarkSnappy(base_allocator: std.mem.Allocator, data: []const u8) !BenchResult {
    var counting = CountingAllocator.init(base_allocator);
    const allocator = counting.allocator();

    // Warmup
    for (0..WARMUP_ITERS) |_| {
        const compressed = cz.snappy.compress(data, allocator) catch {
            return errorResult("Snappy", "default", data.len);
        };
        defer allocator.free(compressed);

        const decompressed = cz.snappy.decompress(compressed, allocator) catch continue;
        allocator.free(decompressed);
    }

    counting.reset();

    // Benchmark compression
    var compress_time_total: u64 = 0;
    var compress_cpu_total: u64 = 0;
    var compressed_size: usize = 0;

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const compressed = cz.snappy.compress(data, allocator) catch {
            return errorResult("Snappy", "default", data.len);
        };
        compressed_size = compressed.len;

        compress_time_total += timer.read();
        compress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(compressed);
    }

    const compress_mem = counting.peak_allocated;
    counting.reset();

    // Get compressed data for decompression benchmark
    const compressed = cz.snappy.compress(data, allocator) catch {
        return errorResult("Snappy", "default", data.len);
    };
    defer allocator.free(compressed);

    // Benchmark decompression
    var decompress_time_total: u64 = 0;
    var decompress_cpu_total: u64 = 0;

    counting.reset();

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const decompressed = cz.snappy.decompress(compressed, allocator) catch {
            return errorResult("Snappy", "default", data.len);
        };

        decompress_time_total += timer.read();
        decompress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(decompressed);
    }

    const decompress_mem = counting.peak_allocated;

    return BenchResult{
        .codec_name = "Snappy",
        .level_name = "default",
        .data_size = data.len,
        .compressed_size = compressed_size,
        .compress_time_us = @as(f64, @floatFromInt(compress_time_total)) / BENCH_ITERS / 1000.0,
        .decompress_time_us = @as(f64, @floatFromInt(decompress_time_total)) / BENCH_ITERS / 1000.0,
        .compress_mem_bytes = compress_mem,
        .decompress_mem_bytes = decompress_mem,
        .compress_cpu_us = @as(f64, @floatFromInt(compress_cpu_total)) / BENCH_ITERS / 1000.0,
        .decompress_cpu_us = @as(f64, @floatFromInt(decompress_cpu_total)) / BENCH_ITERS / 1000.0,
    };
}

fn benchmarkZstd(base_allocator: std.mem.Allocator, data: []const u8, level: cz.Level) !BenchResult {
    var counting = CountingAllocator.init(base_allocator);
    const allocator = counting.allocator();

    // Warmup
    for (0..WARMUP_ITERS) |_| {
        const compressed = cz.zstd.compress(data, allocator, .{ .level = level }) catch {
            return errorResult("Zstd", levelName(level), data.len);
        };
        defer allocator.free(compressed);

        const decompressed = cz.zstd.decompress(compressed, allocator, .{}) catch continue;
        allocator.free(decompressed);
    }

    counting.reset();

    // Benchmark compression
    var compress_time_total: u64 = 0;
    var compress_cpu_total: u64 = 0;
    var compressed_size: usize = 0;

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const compressed = cz.zstd.compress(data, allocator, .{ .level = level }) catch {
            return errorResult("Zstd", levelName(level), data.len);
        };
        compressed_size = compressed.len;

        compress_time_total += timer.read();
        compress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(compressed);
    }

    const compress_mem = counting.peak_allocated;
    counting.reset();

    // Get compressed data for decompression benchmark
    const compressed = cz.zstd.compress(data, allocator, .{ .level = level }) catch {
        return errorResult("Zstd", levelName(level), data.len);
    };
    defer allocator.free(compressed);

    // Benchmark decompression
    var decompress_time_total: u64 = 0;
    var decompress_cpu_total: u64 = 0;

    counting.reset();

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const decompressed = cz.zstd.decompress(compressed, allocator, .{}) catch {
            return errorResult("Zstd", levelName(level), data.len);
        };

        decompress_time_total += timer.read();
        decompress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(decompressed);
    }

    const decompress_mem = counting.peak_allocated;

    return BenchResult{
        .codec_name = "Zstd",
        .level_name = levelName(level),
        .data_size = data.len,
        .compressed_size = compressed_size,
        .compress_time_us = @as(f64, @floatFromInt(compress_time_total)) / BENCH_ITERS / 1000.0,
        .decompress_time_us = @as(f64, @floatFromInt(decompress_time_total)) / BENCH_ITERS / 1000.0,
        .compress_mem_bytes = compress_mem,
        .decompress_mem_bytes = decompress_mem,
        .compress_cpu_us = @as(f64, @floatFromInt(compress_cpu_total)) / BENCH_ITERS / 1000.0,
        .decompress_cpu_us = @as(f64, @floatFromInt(decompress_cpu_total)) / BENCH_ITERS / 1000.0,
    };
}

fn benchmarkGzip(base_allocator: std.mem.Allocator, data: []const u8, level: cz.Level) !BenchResult {
    var counting = CountingAllocator.init(base_allocator);
    const allocator = counting.allocator();

    // Warmup
    for (0..WARMUP_ITERS) |_| {
        const compressed = cz.gzip.compress(data, allocator, .{ .level = level }) catch {
            return errorResult("Gzip", levelName(level), data.len);
        };
        defer allocator.free(compressed);

        const decompressed = cz.gzip.decompress(compressed, allocator, .{}) catch continue;
        allocator.free(decompressed);
    }

    counting.reset();

    // Benchmark compression
    var compress_time_total: u64 = 0;
    var compress_cpu_total: u64 = 0;
    var compressed_size: usize = 0;

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const compressed = cz.gzip.compress(data, allocator, .{ .level = level }) catch {
            return errorResult("Gzip", levelName(level), data.len);
        };
        compressed_size = compressed.len;

        compress_time_total += timer.read();
        compress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(compressed);
    }

    const compress_mem = counting.peak_allocated;
    counting.reset();

    // Get compressed data for decompression benchmark
    const compressed = cz.gzip.compress(data, allocator, .{ .level = level }) catch {
        return errorResult("Gzip", levelName(level), data.len);
    };
    defer allocator.free(compressed);

    // Benchmark decompression
    var decompress_time_total: u64 = 0;
    var decompress_cpu_total: u64 = 0;

    counting.reset();

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const decompressed = cz.gzip.decompress(compressed, allocator, .{}) catch {
            return errorResult("Gzip", levelName(level), data.len);
        };

        decompress_time_total += timer.read();
        decompress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(decompressed);
    }

    const decompress_mem = counting.peak_allocated;

    return BenchResult{
        .codec_name = "Gzip",
        .level_name = levelName(level),
        .data_size = data.len,
        .compressed_size = compressed_size,
        .compress_time_us = @as(f64, @floatFromInt(compress_time_total)) / BENCH_ITERS / 1000.0,
        .decompress_time_us = @as(f64, @floatFromInt(decompress_time_total)) / BENCH_ITERS / 1000.0,
        .compress_mem_bytes = compress_mem,
        .decompress_mem_bytes = decompress_mem,
        .compress_cpu_us = @as(f64, @floatFromInt(compress_cpu_total)) / BENCH_ITERS / 1000.0,
        .decompress_cpu_us = @as(f64, @floatFromInt(decompress_cpu_total)) / BENCH_ITERS / 1000.0,
    };
}

fn benchmarkBrotli(base_allocator: std.mem.Allocator, data: []const u8, level: cz.Level) !BenchResult {
    var counting = CountingAllocator.init(base_allocator);
    const allocator = counting.allocator();

    // Warmup
    for (0..WARMUP_ITERS) |_| {
        const compressed = cz.brotli.compress(data, allocator, .{ .level = level }) catch {
            return errorResult("Brotli", levelName(level), data.len);
        };
        defer allocator.free(compressed);

        const decompressed = cz.brotli.decompress(compressed, allocator, .{}) catch continue;
        allocator.free(decompressed);
    }

    counting.reset();

    // Benchmark compression
    var compress_time_total: u64 = 0;
    var compress_cpu_total: u64 = 0;
    var compressed_size: usize = 0;

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const compressed = cz.brotli.compress(data, allocator, .{ .level = level }) catch {
            return errorResult("Brotli", levelName(level), data.len);
        };
        compressed_size = compressed.len;

        compress_time_total += timer.read();
        compress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(compressed);
    }

    const compress_mem = counting.peak_allocated;
    counting.reset();

    // Get compressed data for decompression benchmark
    const compressed = cz.brotli.compress(data, allocator, .{ .level = level }) catch {
        return errorResult("Brotli", levelName(level), data.len);
    };
    defer allocator.free(compressed);

    // Benchmark decompression
    var decompress_time_total: u64 = 0;
    var decompress_cpu_total: u64 = 0;

    counting.reset();

    for (0..BENCH_ITERS) |_| {
        counting.reset();
        const cpu_before = ResourceUsage.getCpuTime();
        var timer = try std.time.Timer.start();

        const decompressed = cz.brotli.decompress(compressed, allocator, .{}) catch {
            return errorResult("Brotli", levelName(level), data.len);
        };

        decompress_time_total += timer.read();
        decompress_cpu_total += ResourceUsage.getCpuTime() - cpu_before;

        allocator.free(decompressed);
    }

    const decompress_mem = counting.peak_allocated;

    return BenchResult{
        .codec_name = "Brotli",
        .level_name = levelName(level),
        .data_size = data.len,
        .compressed_size = compressed_size,
        .compress_time_us = @as(f64, @floatFromInt(compress_time_total)) / BENCH_ITERS / 1000.0,
        .decompress_time_us = @as(f64, @floatFromInt(decompress_time_total)) / BENCH_ITERS / 1000.0,
        .compress_mem_bytes = compress_mem,
        .decompress_mem_bytes = decompress_mem,
        .compress_cpu_us = @as(f64, @floatFromInt(compress_cpu_total)) / BENCH_ITERS / 1000.0,
        .decompress_cpu_us = @as(f64, @floatFromInt(decompress_cpu_total)) / BENCH_ITERS / 1000.0,
    };
}

fn errorResult(codec_name: []const u8, level_name: []const u8, data_size: usize) BenchResult {
    return BenchResult{
        .codec_name = codec_name,
        .level_name = level_name,
        .data_size = data_size,
        .compressed_size = 0,
        .compress_time_us = 0,
        .decompress_time_us = 0,
        .compress_mem_bytes = 0,
        .decompress_mem_bytes = 0,
        .compress_cpu_us = 0,
        .decompress_cpu_us = 0,
    };
}

fn formatBytes(bytes: usize) struct { value: f64, unit: []const u8 } {
    if (bytes >= 1024 * 1024) {
        return .{ .value = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0), .unit = "MB" };
    } else if (bytes >= 1024) {
        return .{ .value = @as(f64, @floatFromInt(bytes)) / 1024.0, .unit = "KB" };
    } else {
        return .{ .value = @as(f64, @floatFromInt(bytes)), .unit = "B" };
    }
}

fn formatTime(us: f64) struct { value: f64, unit: []const u8 } {
    if (us >= 1000.0) {
        return .{ .value = us / 1000.0, .unit = "ms" };
    } else {
        return .{ .value = us, .unit = "us" };
    }
}

fn printTableHeader() void {
    print(
        "{s:<15} {s:<8} {s:>8} {s:>10} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n",
        .{
            "Codec",
            "Level",
            "Ratio %",
            "Comp.Sz",
            "Comp Time",
            "Dec Time",
            "Comp Mem",
            "Dec Mem",
            "Comp CPU",
            "Dec CPU",
        },
    );
    print("-" ** 120 ++ "\n", .{});
}

fn printResultRow(r: BenchResult) void {
    if (r.compressed_size == 0) {
        print(
            "{s:<15} {s:<8} {s:>8} {s:>10} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n",
            .{ r.codec_name, r.level_name, "ERR", "-", "-", "-", "-", "-", "-", "-" },
        );
        return;
    }

    const comp_time = formatTime(r.compress_time_us);
    const dec_time = formatTime(r.decompress_time_us);
    const comp_mem = formatBytes(r.compress_mem_bytes);
    const dec_mem = formatBytes(r.decompress_mem_bytes);
    const comp_cpu = formatTime(r.compress_cpu_us);
    const dec_cpu = formatTime(r.decompress_cpu_us);

    // Build formatted strings with units
    var comp_time_buf: [16]u8 = undefined;
    var dec_time_buf: [16]u8 = undefined;
    var comp_mem_buf: [16]u8 = undefined;
    var dec_mem_buf: [16]u8 = undefined;
    var comp_cpu_buf: [16]u8 = undefined;
    var dec_cpu_buf: [16]u8 = undefined;

    const comp_time_str = std.fmt.bufPrint(&comp_time_buf, "{d:.1} {s}", .{ comp_time.value, comp_time.unit }) catch "-";
    const dec_time_str = std.fmt.bufPrint(&dec_time_buf, "{d:.1} {s}", .{ dec_time.value, dec_time.unit }) catch "-";
    const comp_mem_str = std.fmt.bufPrint(&comp_mem_buf, "{d:.1} {s}", .{ comp_mem.value, comp_mem.unit }) catch "-";
    const dec_mem_str = std.fmt.bufPrint(&dec_mem_buf, "{d:.1} {s}", .{ dec_mem.value, dec_mem.unit }) catch "-";
    const comp_cpu_str = std.fmt.bufPrint(&comp_cpu_buf, "{d:.1} {s}", .{ comp_cpu.value, comp_cpu.unit }) catch "-";
    const dec_cpu_str = std.fmt.bufPrint(&dec_cpu_buf, "{d:.1} {s}", .{ dec_cpu.value, dec_cpu.unit }) catch "-";

    print(
        "{s:<15} {s:<8} {d:>7.1}% {d:>10} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n",
        .{
            r.codec_name,
            r.level_name,
            r.ratioPercent(),
            r.compressed_size,
            comp_time_str,
            dec_time_str,
            comp_mem_str,
            dec_mem_str,
            comp_cpu_str,
            dec_cpu_str,
        },
    );
}

fn levelName(level: cz.Level) []const u8 {
    return switch (level) {
        .fastest => "fastest",
        .fast => "fast",
        .default => "default",
        .better => "better",
        .best => "best",
    };
}

fn printSummary(results: []const BenchResult) void {
    print("=" ** 120 ++ "\n", .{});
    print("  SUMMARY (1 MB data, throughput in MB/s)\n", .{});
    print("=" ** 120 ++ "\n", .{});
    print("\n", .{});

    print("{s:<20} {s:>10} {s:>12} {s:>12} {s:>14}\n", .{
        "Codec",
        "Ratio %",
        "Comp MB/s",
        "Decomp MB/s",
        "Peak Mem",
    });
    print("-" ** 72 ++ "\n", .{});

    for (results) |r| {
        if (r.data_size == 1_000_000 and r.compressed_size > 0) {
            const mem = formatBytes(r.compress_mem_bytes);
            var mem_buf: [16]u8 = undefined;
            const mem_str = std.fmt.bufPrint(&mem_buf, "{d:.1} {s}", .{ mem.value, mem.unit }) catch "-";

            print("{s:<12} {s:<7} {d:>9.1}% {d:>12.1} {d:>12.1} {s:>14}\n", .{
                r.codec_name,
                r.level_name,
                r.ratioPercent(),
                r.compressThroughputMBs(),
                r.decompressThroughputMBs(),
                mem_str,
            });
        }
    }

    print("\n", .{});
    print("Note: Ratio % shows percentage of data reduced (99% = compressed to 1% of original)\n", .{});
    print("      CPU time measures user+system CPU cycles (via getrusage)\n", .{});
    print("      Memory shows peak allocation during operation\n", .{});
}

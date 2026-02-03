---
title: Optimization Guide
description: Tips for maximizing compression performance.
---

This guide covers optimization strategies for getting the best performance from compressionz.

## Build Optimization

### Always Use ReleaseFast

Performance differs dramatically between debug and release builds:

```bash
# Debug build (default)
zig build
# LZ4: ~500 MB/s

# Release build
zig build -Doptimize=ReleaseFast
# LZ4: ~36 GB/s (72× faster!)
```

| Build Mode | LZ4 Speed | Use Case |
|------------|-----------|----------|
| Debug | ~500 MB/s | Development |
| ReleaseSafe | ~20 GB/s | Production with checks |
| ReleaseFast | ~36 GB/s | Maximum performance |
| ReleaseSmall | ~25 GB/s | Minimal binary size |

### Recommendation

- **Development:** Debug (fast compilation)
- **Testing:** ReleaseSafe (catches bugs)
- **Production:** ReleaseFast (maximum speed)

## Codec Selection

### Speed Priority

```zig
// Fastest compression
const result = try cz.lz4.block.compress(data, allocator);

// Fast with self-describing format
const result = try cz.snappy.compress(data, allocator);

// Best balance of speed and ratio
const result = try cz.zstd.compress(data, allocator, .{});
```

### Ratio Priority

```zig
// Best ratio for one-time compression
const result = try cz.brotli.compress(data, allocator, .{
    .level = .best,
});

// Best ratio with reasonable speed
const result = try cz.zstd.compress(data, allocator, .{
    .level = .best,
});
```

### Use Case Matrix

| Scenario | Codec | Level | Throughput |
|----------|-------|-------|------------|
| Real-time | LZ4 Block | default | 36 GB/s |
| Messaging | Snappy | default | 31 GB/s |
| General | Zstd | default | 12 GB/s |
| Archival | Zstd | best | 1.3 GB/s |
| Web assets | Brotli | best | 86 MB/s |

## Memory Optimization

### Zero-Copy for Hot Paths

Avoid allocation overhead with pre-allocated buffers:

```zig
// Standard API (allocates each time)
for (items) |item| {
    const compressed = try cz.lz4.frame.compress(item, allocator, .{});
    defer allocator.free(compressed);  // Free each iteration
    try process(compressed);
}

// Zero-copy (no allocations)
var buffer: [65536]u8 = undefined;
for (items) |item| {
    const compressed = try cz.lz4.block.compressInto(item, &buffer);
    try process(compressed);
}
```

### Buffer Reuse Pattern

```zig
const Compressor = struct {
    buffer: []u8,

    pub fn init(allocator: std.mem.Allocator, max_input_size: usize) !Compressor {
        const buffer_size = cz.lz4.block.maxCompressedSize(max_input_size);
        return .{
            .buffer = try allocator.alloc(u8, buffer_size),
        };
    }

    pub fn compress(self: *Compressor, data: []const u8) ![]u8 {
        return cz.lz4.block.compressInto(data, self.buffer);
    }
};
```

### Arena Allocators for Batches

```zig
pub fn processBatch(items: []const []const u8, backing: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();  // One free for all allocations

    for (items) |item| {
        const compressed = try cz.zstd.compress(item, arena.allocator(), .{});
        try sendData(compressed);
        // No individual frees needed
    }
}
```

## Compression Level Selection

### Level Impact by Codec

**Zstd:**

| Level | Compress | Ratio | Notes |
|-------|----------|-------|-------|
| fast | 12 GB/s | 99.9% | **Recommended** |
| default | 12 GB/s | 99.9% | Same as fast |
| best | 1.3 GB/s | 99.9% | 9× slower, marginal gain |

**Brotli:**

| Level | Compress | Ratio | Notes |
|-------|----------|-------|-------|
| fast | 1.3 GB/s | 99.9% | Dynamic content |
| default | 1.3 GB/s | 99.9% | Same as fast |
| best | 86 MB/s | 99.9%+ | **Only for static content** |

### Recommendation

Use `.default` unless you have a specific reason:
- `.fast` rarely helps (often same as default)
- `.best` has diminishing returns for most data

## Streaming Optimization

### Chunk Size

Larger chunks = better throughput, more memory:

```zig
// Small chunks (more overhead)
var buf: [4096]u8 = undefined;

// Large chunks (better throughput)
var buf: [65536]u8 = undefined;  // Recommended

// Very large (diminishing returns)
var buf: [1048576]u8 = undefined;
```

### Pipeline Pattern

Process data as it arrives:

```zig
pub fn streamProcess(input: anytype, output: anytype, allocator: std.mem.Allocator) !void {
    var decomp = try cz.gzip.Decompressor(@TypeOf(input)).init(allocator, input);
    defer decomp.deinit();

    var comp = try cz.zstd.Compressor(@TypeOf(output)).init(allocator, output, .{});
    defer comp.deinit();

    var buf: [65536]u8 = undefined;
    while (true) {
        const n = try decomp.reader().read(&buf);
        if (n == 0) break;
        try comp.writer().writeAll(buf[0..n]);
    }
    try comp.finish();
}
```

## Dictionary Optimization

### When to Use Dictionaries

| Data Size | Without Dict | With Dict | Use Dict? |
|-----------|--------------|-----------|-----------|
| 100 B | 105 B | 45 B | ✅ Yes |
| 1 KB | 780 B | 380 B | ✅ Yes |
| 10 KB | 3 KB | 1.9 KB | ✅ Yes |
| 100 KB | 28 KB | 24 KB | Maybe |
| 1 MB | 684 B | 680 B | ❌ No |

**Rule of thumb:** Use dictionaries for data < 10 KB with known patterns.

### Dictionary Size

| Use Case | Size | Notes |
|----------|------|-------|
| JSON APIs | 16-32 KB | Common field names |
| Log messages | 32-64 KB | Common log patterns |
| Protocol buffers | 8-16 KB | Schema patterns |

Larger dictionaries have diminishing returns.

## Parallelization

### Independent Data

Compress multiple items in parallel:

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn compressParallel(items: []const []const u8, allocator: std.mem.Allocator) ![][]u8 {
    const results = try allocator.alloc([]u8, items.len);

    var pool = std.Thread.Pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    for (items, 0..) |item, i| {
        try pool.spawn(compressOne, .{ item, allocator, &results[i] });
    }

    pool.waitForAll();
    return results;
}

fn compressOne(item: []const u8, allocator: std.mem.Allocator, result: *[]u8) void {
    result.* = cz.zstd.compress(item, allocator, .{}) catch unreachable;
}
```

### Large Single File

Split into chunks:

```zig
pub fn compressLargeFile(data: []const u8, chunk_size: usize, allocator: std.mem.Allocator) ![][]u8 {
    const num_chunks = (data.len + chunk_size - 1) / chunk_size;
    const chunks = try allocator.alloc([]u8, num_chunks);

    // Compress chunks in parallel...
}
```

## Benchmarking Your Data

Test with your actual data:

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn benchmark(data: []const u8, allocator: std.mem.Allocator) !void {
    std.debug.print("Input size: {d} bytes\n\n", .{data.len});
    std.debug.print("{s:<12} {s:>10} {s:>10} {s:>10}\n", .{
        "Codec", "Size", "Compress", "Decompress",
    });

    // LZ4 Frame
    {
        var timer = try std.time.Timer.start();
        const compressed = try cz.lz4.frame.compress(data, allocator, .{});
        const compress_ns = timer.read();

        timer.reset();
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        const decompress_ns = timer.read();

        allocator.free(compressed);
        allocator.free(decompressed);

        std.debug.print("{s:<12} {d:>10} {d:>9}µs {d:>9}µs\n", .{
            "lz4.frame", compressed.len, compress_ns / 1000, decompress_ns / 1000,
        });
    }

    // Snappy
    {
        var timer = try std.time.Timer.start();
        const compressed = try cz.snappy.compress(data, allocator);
        const compress_ns = timer.read();

        timer.reset();
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        const decompress_ns = timer.read();

        allocator.free(compressed);
        allocator.free(decompressed);

        std.debug.print("{s:<12} {d:>10} {d:>9}µs {d:>9}µs\n", .{
            "snappy", compressed.len, compress_ns / 1000, decompress_ns / 1000,
        });
    }

    // Zstd
    {
        var timer = try std.time.Timer.start();
        const compressed = try cz.zstd.compress(data, allocator, .{});
        const compress_ns = timer.read();

        timer.reset();
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        const decompress_ns = timer.read();

        allocator.free(compressed);
        allocator.free(decompressed);

        std.debug.print("{s:<12} {d:>10} {d:>9}µs {d:>9}µs\n", .{
            "zstd", compressed.len, compress_ns / 1000, decompress_ns / 1000,
        });
    }

    // Gzip
    {
        var timer = try std.time.Timer.start();
        const compressed = try cz.gzip.compress(data, allocator, .{});
        const compress_ns = timer.read();

        timer.reset();
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        const decompress_ns = timer.read();

        allocator.free(compressed);
        allocator.free(decompressed);

        std.debug.print("{s:<12} {d:>10} {d:>9}µs {d:>9}µs\n", .{
            "gzip", compressed.len, compress_ns / 1000, decompress_ns / 1000,
        });
    }

    // Brotli
    {
        var timer = try std.time.Timer.start();
        const compressed = try cz.brotli.compress(data, allocator, .{});
        const compress_ns = timer.read();

        timer.reset();
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        const decompress_ns = timer.read();

        allocator.free(compressed);
        allocator.free(decompressed);

        std.debug.print("{s:<12} {d:>10} {d:>9}µs {d:>9}µs\n", .{
            "brotli", compressed.len, compress_ns / 1000, decompress_ns / 1000,
        });
    }
}
```

## Common Pitfalls

### 1. Debug Builds in Production

```zig
// Wrong: 72× slower
$ zig build && ./app

// Right: Full speed
$ zig build -Doptimize=ReleaseFast && ./app
```

### 2. Over-Compressing

```zig
// Wrong: Compressing already compressed data
const gzip_data = try cz.gzip.compress(image_data, allocator, .{});
const zstd_data = try cz.zstd.compress(gzip_data, allocator, .{});  // Waste of CPU!

// Right: Compress once
const compressed = try cz.zstd.compress(raw_data, allocator, .{});
```

### 3. Wrong Codec for Use Case

```zig
// Wrong: Brotli best for real-time data
const compressed = try cz.brotli.compress(message, allocator, .{
    .level = .best,  // 86 MB/s is too slow for real-time!
});

// Right: Use LZ4 or Snappy for real-time
const compressed = try cz.lz4.block.compress(message, allocator);
```

### 4. Allocating in Hot Loops

```zig
// Wrong: Allocation per iteration
while (hasData()) {
    const compressed = try cz.lz4.frame.compress(getData(), allocator, .{});
    defer allocator.free(compressed);
    try send(compressed);
}

// Right: Reuse buffer
var buffer: [65536]u8 = undefined;
while (hasData()) {
    const compressed = try cz.lz4.block.compressInto(getData(), &buffer);
    try send(compressed);
}
```

## Summary

1. **Use ReleaseFast** for production
2. **Choose the right codec** for your use case
3. **Use `.default` level** unless you have specific needs
4. **Reuse buffers** in hot paths
5. **Use dictionaries** for small, structured data
6. **Benchmark with your actual data**

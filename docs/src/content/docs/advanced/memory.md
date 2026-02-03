---
title: Memory Management
description: Understanding and optimizing memory usage in compressionz.
---

This guide covers memory usage patterns, allocation strategies, and optimization techniques for compressionz.

## Memory Usage by Codec

### Compression Memory

| Codec | Memory | Notes |
|-------|--------|-------|
| LZ4 Block | ~input size | Hash table + output buffer |
| LZ4 Frame | ~input size | + frame overhead |
| Snappy | ~1.1x input | Hash table + output |
| Zstd | ~input size | Efficient internal state |
| Gzip | ~input + 256KB | zlib internal state |
| Brotli | ~input + 1MB | Larger dictionary state |

### Decompression Memory

| Codec | Memory | Notes |
|-------|--------|-------|
| LZ4 | ~output size | Direct output allocation |
| Snappy | ~output size | Direct output allocation |
| Zstd | ~output size | Efficient decoding |
| Gzip | ~output + 32KB | Sliding window |
| Brotli | ~output + 256KB | Dictionary buffer |

## Allocation Patterns

### Standard API

The standard API allocates for each operation:

```zig
const cz = @import("compressionz");

// Allocates compressed buffer
const compressed = try cz.zstd.compress(data, allocator, .{});
defer allocator.free(compressed);

// Allocates decompressed buffer
const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

### Zero-Copy API

Avoid allocations with pre-allocated buffers:

```zig
var buffer: [65536]u8 = undefined;

// No allocation
const compressed = try cz.lz4.block.compressInto(data, &buffer);
const decompressed = try cz.lz4.block.decompressInto(compressed, &output_buf);
```

**Supported:** `lz4.frame`, `lz4.block`, `snappy`

### Streaming API

Streaming uses internal buffers but processes incrementally:

```zig
var comp = try cz.gzip.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();  // Frees internal buffers

// Write in chunks - constant memory regardless of total size
try comp.writer().writeAll(chunk1);
try comp.writer().writeAll(chunk2);
try comp.finish();
```

## Memory Optimization Strategies

### 1. Reuse Buffers

For repeated operations, reuse buffers:

```zig
const cz = @import("compressionz");

pub const Processor = struct {
    compress_buf: []u8,
    decompress_buf: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Processor {
        return .{
            .compress_buf = try allocator.alloc(u8, 1024 * 1024),
            .decompress_buf = try allocator.alloc(u8, 1024 * 1024),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Processor) void {
        self.allocator.free(self.compress_buf);
        self.allocator.free(self.decompress_buf);
    }

    pub fn compress(self: *Processor, data: []const u8) ![]u8 {
        return cz.lz4.block.compressInto(data, self.compress_buf);
    }

    pub fn decompress(self: *Processor, data: []const u8, original_size: usize) ![]u8 {
        return cz.lz4.block.decompressIntoWithSize(data, self.decompress_buf, original_size);
    }
};
```

### 2. Limit Output Size

Prevent memory exhaustion with `max_output_size`:

```zig
// Limits memory allocation to 100 MB
const safe = try cz.gzip.decompress(untrusted_data, allocator, .{
    .max_output_size = 100 * 1024 * 1024,
});
```

### 3. Stream Large Data

For large files, use streaming instead of loading everything:

```zig
// Bad: Loads entire file into memory
const data = try std.fs.cwd().readFileAlloc(allocator, "huge.gz", 10 * 1024 * 1024 * 1024);
const decompressed = try cz.gzip.decompress(data, allocator, .{});

// Good: Stream with bounded memory
var file = try std.fs.cwd().openFile("huge.gz", .{});
defer file.close();

var decomp = try cz.gzip.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
defer decomp.deinit();

var buf: [65536]u8 = undefined;
while (true) {
    const n = try decomp.reader().read(&buf);
    if (n == 0) break;
    try processChunk(buf[0..n]);
}
```

### 4. Pre-Calculate Buffer Sizes

Use `maxCompressedSize` for compression buffers:

```zig
const max_size = cz.lz4.block.maxCompressedSize(input.len);
var buffer = try allocator.alloc(u8, max_size);
defer allocator.free(buffer);

const compressed = try cz.lz4.block.compressInto(input, buffer);
// compressed.len <= max_size
```

### 5. Arena Allocators

For batch operations, use arena allocators:

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn processBatch(items: []const []const u8, backing: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();  // Frees everything at once
    const allocator = arena.allocator();

    for (items) |item| {
        const compressed = try cz.zstd.compress(item, allocator, .{});
        try sendData(compressed);
        // No individual free needed
    }
    // All memory freed when arena.deinit() is called
}
```

## Memory Tracking

Use a counting allocator to measure usage:

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn measureMemory(data: []const u8) !void {
    var counting = std.heap.counting_allocator(.{}).init(std.heap.page_allocator);
    const allocator = counting.allocator();

    const compressed = try cz.zstd.compress(data, allocator, .{});
    defer allocator.free(compressed);

    std.debug.print("Allocated: {d} bytes\n", .{counting.total_allocated_bytes});
}
```

## Per-Codec Memory Details

### LZ4

LZ4 is the most memory-efficient:

```
Compression:
  - Hash table: 64 KB (fixed)
  - Output buffer: max_compressed_size

Decompression:
  - Output buffer only
```

### Zstd

Zstd uses more memory but is still efficient:

```
Compression:
  - Window: 128 KB - 128 MB (level dependent)
  - Hash tables: level dependent
  - Output buffer

Decompression:
  - Window: determined by compressed stream
  - Output buffer
```

### Gzip/Zlib

zlib has fixed internal state:

```
Compression:
  - Internal state: ~256 KB
  - Output buffer

Decompression:
  - Sliding window: 32 KB
  - Output buffer
```

### Brotli

Brotli uses the most memory:

```
Compression:
  - Ring buffer: up to 16 MB
  - Hash tables: ~1 MB
  - Output buffer

Decompression:
  - Ring buffer: up to 16 MB (typically 256 KB)
  - Dictionary: 120 KB (static)
  - Output buffer
```

## Memory-Constrained Environments

For embedded or limited-memory systems:

### 1. Prefer LZ4 or Snappy

```zig
// Minimal memory overhead
const compressed = try cz.lz4.block.compress(data, allocator);
```

### 2. Use Fixed Buffers

```zig
// No dynamic allocation
var compress_buf: [65536]u8 = undefined;
var decompress_buf: [65536]u8 = undefined;

const compressed = try cz.lz4.block.compressInto(data, &compress_buf);
const decompressed = try cz.lz4.block.decompressInto(compressed, &decompress_buf);
```

### 3. Process in Chunks

```zig
pub fn compressInChunks(input: []const u8, chunk_size: usize, output: *std.ArrayList(u8)) !void {
    var compress_buf: [4096]u8 = undefined;
    var i: usize = 0;

    while (i < input.len) {
        const chunk = input[i..@min(i + chunk_size, input.len)];
        const compressed = try cz.lz4.block.compressInto(chunk, &compress_buf);

        // Write length prefix + compressed data
        try output.appendSlice(std.mem.asBytes(&@as(u32, @intCast(compressed.len))));
        try output.appendSlice(compressed);

        i += chunk_size;
    }
}
```

## Common Memory Issues

### Issue: Out of Memory on Large Files

```zig
// Problem: Tries to load entire file
const data = try fs.readFileAlloc(allocator, "10gb.zst", max);
const decompressed = try cz.zstd.decompress(data, allocator, .{});

// Solution: Use streaming
var decomp = try cz.zstd.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
// Process incrementally...
```

### Issue: Memory Fragmentation

```zig
// Problem: Many small allocations
for (items) |item| {
    const compressed = try cz.zstd.compress(item, allocator, .{});
    // ... use compressed ...
    allocator.free(compressed);
}

// Solution: Use arena allocator
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
for (items) |item| {
    const compressed = try cz.zstd.compress(item, arena.allocator(), .{});
    // ... use compressed ...
}
// One free at the end
```

### Issue: Decompression Bombs

```zig
// Problem: Malicious input expands to huge size
const decompressed = try cz.gzip.decompress(untrusted, allocator, .{});

// Solution: Limit output size
const safe = try cz.gzip.decompress(untrusted, allocator, .{
    .max_output_size = 10 * 1024 * 1024,  // 10 MB limit
});
```

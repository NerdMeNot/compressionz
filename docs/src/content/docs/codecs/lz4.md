---
title: LZ4
description: Deep dive into the LZ4 compression codec.
---

LZ4 is an extremely fast compression algorithm, prioritizing speed over compression ratio. compressionz provides a pure Zig implementation with SIMD optimizations.

## At a Glance

| Property | Value |
|----------|-------|
| **Developer** | Yann Collet |
| **First Release** | 2011 |
| **Implementation** | Pure Zig with SIMD |
| **License** | Apache 2.0 (compressionz implementation) |

### Performance

| Variant | Compress | Decompress | Ratio |
|---------|----------|------------|-------|
| LZ4 Block | **36.6 GB/s** | 8.1 GB/s | 99.5% |
| LZ4 Frame | 4.8 GB/s | 3.8 GB/s | 99.3% |

### Features

| Feature | LZ4 Frame | LZ4 Block |
|---------|-----------|-----------|
| Streaming | Yes | No |
| Checksum | Yes | No |
| Auto-detect | Yes | No |
| Zero-copy | Yes | Yes |
| Size in header | Yes | No |

## Two Variants

compressionz supports two LZ4 variants:

### LZ4 Frame (`cz.lz4.frame`)

Self-describing format with headers, checksums, and streaming support.

```zig
const cz = @import("compressionz");

// Compress
const compressed = try cz.lz4.frame.compress(data, allocator, .{});
defer allocator.free(compressed);

// Decompress - size is in frame header
const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

### LZ4 Block (`cz.lz4.block`)

Raw block format for maximum speed. **Requires tracking original size.**

```zig
const cz = @import("compressionz");

// Compress
const compressed = try cz.lz4.block.compress(data, allocator);
const original_size = data.len;  // MUST save this!
defer allocator.free(compressed);

// Decompress - MUST provide original size
const decompressed = try cz.lz4.block.decompressWithSize(compressed, original_size, allocator);
defer allocator.free(decompressed);
```

## Which Variant to Use?

| Use Case | Recommended |
|----------|-------------|
| File storage | LZ4 Frame |
| Network protocols | LZ4 Frame |
| In-memory caching | LZ4 Block |
| IPC / message passing | LZ4 Block |
| Database pages | LZ4 Block |
| Unknown recipient | LZ4 Frame |

## Compression Levels

```zig
// Fast (default for LZ4)
const fast = try cz.lz4.frame.compress(data, allocator, .{
    .level = .fast,
});

// Default (slightly better ratio)
const default = try cz.lz4.frame.compress(data, allocator, .{
    .level = .default,
});
```

LZ4 has a narrower speed/ratio trade-off than Zstd. Both levels are extremely fast.

## Frame Options

When using LZ4 Frame, you can control:

```zig
const cz = @import("compressionz");

const compressed = try cz.lz4.frame.compress(data, allocator, .{
    .level = .fast,
    .content_checksum = true,   // Include XXH32 checksum
    .block_checksum = false,    // Per-block checksum
    .content_size = data.len,   // Store size in header
    .block_size = .max64KB,     // Block size
});
```

### Checksum Options

```zig
// With checksum (default) - detects corruption
const safe = try cz.lz4.frame.compress(data, allocator, .{
    .content_checksum = true,
});

// Without checksum - slightly faster/smaller
const fast = try cz.lz4.frame.compress(data, allocator, .{
    .content_checksum = false,
});
```

## Zero-Copy Operations

Both variants support zero-copy for allocation-free compression:

```zig
const cz = @import("compressionz");

var compress_buf: [65536]u8 = undefined;
var decompress_buf: [65536]u8 = undefined;

// Compress into buffer
const compressed = try cz.lz4.block.compressInto(data, &compress_buf);

// Decompress into buffer
const decompressed = try cz.lz4.block.decompressInto(compressed, &decompress_buf);
```

### Buffer Sizing

```zig
// Calculate maximum compressed size
const max_block = cz.lz4.block.maxCompressedSize(data.len);
const max_frame = cz.lz4.frame.maxCompressedSize(data.len);
```

## Streaming (Frame Only)

```zig
const cz = @import("compressionz");
const std = @import("std");

// Compress to file
pub fn compressToFile(allocator: std.mem.Allocator, data: []const u8, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var comp = try cz.lz4.frame.Compressor(@TypeOf(file.writer())).init(allocator, file.writer(), .{});
    defer comp.deinit();

    try comp.writer().writeAll(data);
    try comp.finish();
}

// Decompress from file
pub fn decompressFromFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var decomp = try cz.lz4.frame.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
    defer decomp.deinit();

    return decomp.reader().readAllAlloc(allocator, 1024 * 1024 * 1024);
}
```

## Format Details

### Frame Format

```
+-----------------------------------------------------+
| Magic Number (4 bytes): 0x184D2204                  |
+-----------------------------------------------------+
| Frame Descriptor                                    |
|  - FLG byte (flags)                                 |
|  - BD byte (block descriptor)                       |
|  - Content Size (0-8 bytes, optional)               |
|  - Header Checksum (1 byte)                         |
+-----------------------------------------------------+
| Data Blocks                                         |
|  - Block Size (4 bytes)                             |
|  - Block Data (variable)                            |
|  - Block Checksum (4 bytes, optional)               |
|  - ... more blocks ...                              |
+-----------------------------------------------------+
| End Mark (4 bytes): 0x00000000                      |
+-----------------------------------------------------+
| Content Checksum (4 bytes, optional)                |
+-----------------------------------------------------+
```

### Block Format (Raw)

```
+-----------------------------------------------------+
| Sequence of tokens:                                 |
|                                                     |
| Token (1 byte)                                      |
|  - High 4 bits: literal length                      |
|  - Low 4 bits: match length                         |
|                                                     |
| [Extended literal length] (0+ bytes)                |
| Literals (literal_length bytes)                     |
| Offset (2 bytes, little-endian)                     |
| [Extended match length] (0+ bytes)                  |
+-----------------------------------------------------+
```

### Magic Bytes

```zig
// LZ4 frame magic (little-endian)
const LZ4_MAGIC: u32 = 0x184D2204;

// Detection
if (data.len >= 4 and
    data[0] == 0x04 and data[1] == 0x22 and
    data[2] == 0x4D and data[3] == 0x18)
{
    // It's LZ4 frame
}
```

## Algorithm Details

LZ4 is a byte-oriented LZ77 variant optimized for speed:

1. **Hash table** — 4-byte sequences hashed to find matches
2. **Greedy parsing** — Takes first match found (no optimal parsing)
3. **Simple encoding** — Minimal overhead per token
4. **No entropy coding** — Raw bytes, no Huffman/ANS

### Why It's Fast

- Cache-friendly linear scanning
- Minimal branching
- Simple token format
- SIMD-optimized match extension and copy
- No dictionary or entropy coding overhead

### SIMD Optimizations

Our pure Zig implementation uses explicit SIMD:

```zig
// 16-byte vectorized match extension
const v1: @Vector(16, u8) = src[pos..][0..16].*;
const v2: @Vector(16, u8) = src[match_pos..][0..16].*;
const eq = v1 == v2;
const mask = @as(u16, @bitCast(eq));
// Count trailing ones for match length

// 8-byte vectorized copy
const chunk: @Vector(8, u8) = src[offset..][0..8].*;
dest[0..8].* = @as([8]u8, chunk);
```

## When to Use LZ4

**Best for:**
- Maximum throughput requirements
- Real-time compression
- In-memory data structures
- Game asset compression
- Database page compression

**Not ideal for:**
- Maximum compression ratio (use Zstd/Brotli)
- Web content delivery (use Gzip/Brotli)
- Dictionary compression (use Zstd)

## Comparison

| Metric | LZ4 Block | LZ4 Frame | Zstd |
|--------|-----------|-----------|------|
| Compress | **36.6 GB/s** | 4.8 GB/s | 12 GB/s |
| Decompress | 8.1 GB/s | 3.8 GB/s | **11.6 GB/s** |
| Ratio | 99.5% | 99.3% | **99.9%** |
| Checksum | No | Yes | Yes |
| Streaming | No | Yes | Yes |

## Resources

- [LZ4 GitHub](https://github.com/lz4/lz4)
- [LZ4 Frame Format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md)
- [LZ4 Block Format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md)

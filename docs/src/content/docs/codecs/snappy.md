---
title: Snappy
description: Deep dive into the Snappy compression codec.
---

Snappy is a fast compression algorithm developed by Google, optimized for speed rather than compression ratio. compressionz provides a pure Zig implementation.

## At a Glance

| Property | Value |
|----------|-------|
| **Developer** | Google |
| **First Release** | 2011 |
| **Implementation** | Pure Zig with SIMD |
| **License** | Apache 2.0 (compressionz implementation) |

### Performance

| Metric | Value |
|--------|-------|
| Compress | **31.6 GB/s** |
| Decompress | **9.2 GB/s** |
| Ratio | 95.3% |

### Features

- Self-describing format
- Auto-detection (magic bytes)
- Zero-copy operations
- Pure Zig implementation
- No streaming
- No dictionary
- No checksum

## Basic Usage

Snappy has the simplest API — no options needed:

```zig
const cz = @import("compressionz");

// Compress (no options)
const compressed = try cz.snappy.compress(data, allocator);
defer allocator.free(compressed);

// Decompress (no options)
const decompressed = try cz.snappy.decompress(compressed, allocator);
defer allocator.free(decompressed);
```

## When to Use Snappy

**Best for:**
- Real-time applications
- Message queues and streaming
- Caching systems
- Log aggregation
- When speed matters more than ratio

**Not ideal for:**
- Storage (use Zstd for better ratio)
- Network bandwidth constraints
- Web content (use Gzip/Brotli)

## Zero-Copy Operations

Snappy supports zero-copy for allocation-free hot paths:

```zig
const cz = @import("compressionz");

var compress_buf: [65536]u8 = undefined;
var decompress_buf: [65536]u8 = undefined;

// Compress into buffer
const compressed = try cz.snappy.compressInto(data, &compress_buf);

// Decompress into buffer
const decompressed = try cz.snappy.decompressInto(compressed, &decompress_buf);
```

### Buffer Sizing

```zig
// Calculate maximum compressed size
const max_size = cz.snappy.maxCompressedSize(data.len);
```

## Size-Limited Decompression

For security, you can limit the decompressed size:

```zig
const decompressed = try cz.snappy.decompressWithLimit(compressed, allocator, max_size);
```

## Get Uncompressed Length

Snappy stores the uncompressed length in the header:

```zig
const size = try cz.snappy.getUncompressedLength(compressed);
```

## Format Details

### Framing Format

Snappy uses a simple framing format:

```
+-----------------------------------------------------+
| Stream Identifier (10 bytes)                        |
|  - Chunk type: 0xff                                 |
|  - Length: 6 (little-endian, 3 bytes)               |
|  - "sNaPpY"                                         |
+-----------------------------------------------------+
| Compressed Data Chunk                               |
|  - Chunk type: 0x00                                 |
|  - Length (3 bytes)                                 |
|  - CRC32C masked (4 bytes)                          |
|  - Compressed data                                  |
+-----------------------------------------------------+
| ... more chunks ...                                 |
+-----------------------------------------------------+
```

### Block Format

Within each chunk:

```
+-----------------------------------------------------+
| Uncompressed length (varint)                        |
+-----------------------------------------------------+
| Elements (sequence of):                             |
|                                                     |
| Literal:                                            |
|  - Tag byte: 00xxxxxx (length-1 in bits)            |
|  - [Extended length bytes]                          |
|  - Literal data                                     |
|                                                     |
| Copy with 1-byte offset:                            |
|  - Tag byte: 01xxxxxx xxxxxxxx                      |
|  - (length-4 in high bits, offset in low)           |
|                                                     |
| Copy with 2-byte offset:                            |
|  - Tag byte: 10xxxxxx + 2 offset bytes              |
|                                                     |
| Copy with 4-byte offset:                            |
|  - Tag byte: 11xxxxxx + 4 offset bytes              |
+-----------------------------------------------------+
```

### Magic Bytes

```zig
// Snappy stream identifier
const SNAPPY_MAGIC = "sNaPpY";

// Detection
if (data.len >= 6 and std.mem.eql(u8, data[0..6], "sNaPpY")) {
    // It's Snappy
}
```

## Algorithm Details

Snappy is a byte-oriented LZ77 variant:

1. **Hash table** — 4-byte sequences hashed for matching
2. **Greedy parsing** — Takes first sufficient match
3. **Variable-length encoding** — For offsets and lengths
4. **No entropy coding** — Raw bytes only

### Why Snappy is Fast

- Optimized for 64-bit processors
- Cache-efficient memory access
- Minimal branching
- Simple tag format
- SIMD-optimized operations

### SIMD Optimizations

Our implementation uses explicit SIMD:

```zig
// 16-byte vectorized match finding
const v1: @Vector(16, u8) = src[pos..][0..16].*;
const v2: @Vector(16, u8) = src[match_pos..][0..16].*;
const eq = v1 == v2;

// 8-byte fast copy
const chunk: @Vector(8, u8) = src[..8].*;
dest[0..8].* = @as([8]u8, chunk);
```

## Snappy vs LZ4

Both are speed-focused LZ77 variants. Comparison:

| Aspect | Snappy | LZ4 Block | LZ4 Frame |
|--------|--------|-----------|-----------|
| Compress | 31.6 GB/s | **36.6 GB/s** | 4.8 GB/s |
| Decompress | **9.2 GB/s** | 8.1 GB/s | 3.8 GB/s |
| Ratio | 95.3% | **99.5%** | 99.3% |
| Self-describing | Yes | No | Yes |
| Checksum | No | No | Yes |
| Streaming | No | No | Yes |

**Choose Snappy when:**
- You need a self-describing format without checksums
- Decompression speed is critical
- Working with Snappy-native systems

**Choose LZ4 when:**
- Maximum compression speed needed
- Better compression ratio desired
- Checksum verification needed (frame)

## Use Cases

### Message Queues

```zig
pub fn publishMessage(queue: *Queue, message: []const u8) !void {
    var buf: [65536]u8 = undefined;
    const compressed = try cz.snappy.compressInto(message, &buf);
    try queue.publish(compressed);
}

pub fn consumeMessage(allocator: Allocator, queue: *Queue) ![]u8 {
    const compressed = try queue.consume();
    return cz.snappy.decompress(compressed, allocator);
}
```

### Caching

```zig
pub fn cacheGet(cache: *Cache, key: []const u8, allocator: Allocator) !?[]u8 {
    const compressed = cache.get(key) orelse return null;
    return cz.snappy.decompress(compressed, allocator);
}

pub fn cacheSet(cache: *Cache, key: []const u8, value: []const u8, allocator: Allocator) !void {
    const compressed = try cz.snappy.compress(value, allocator);
    defer allocator.free(compressed);
    try cache.set(key, compressed);
}
```

## Error Handling

```zig
const result = cz.snappy.decompress(data, allocator) catch |err| switch (err) {
    error.InvalidData => {
        // Not valid Snappy data
        return error.CorruptedMessage;
    },
    error.OutputTooLarge => {
        // Exceeds max_output_size
        return error.MessageTooLarge;
    },
    else => return err,
};
```

## Comparison with Zstd

| Metric | Snappy | Zstd |
|--------|--------|------|
| Compress | **31.6 GB/s** | 12 GB/s |
| Decompress | 9.2 GB/s | **11.6 GB/s** |
| Ratio | 95.3% | **99.9%** |
| Dictionary | No | Yes |
| Streaming | No | Yes |
| Checksum | No | Yes |

**Summary:** Snappy is ~2.6x faster at compression but achieves worse ratios and lacks features. Use Snappy when compression speed is paramount.

## Resources

- [Snappy GitHub](https://github.com/google/snappy)
- [Snappy Format Description](https://github.com/google/snappy/blob/main/format_description.txt)

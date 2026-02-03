---
title: Zstandard (Zstd)
description: Deep dive into the Zstd compression codec.
---

Zstandard (Zstd) is a fast compression algorithm providing high compression ratios. It's the recommended codec for most use cases.

## At a Glance

| Property | Value |
|----------|-------|
| **Developer** | Meta (Facebook) |
| **First Release** | 2016 |
| **Implementation** | Vendored C (zstd 1.5.7) |
| **License** | BSD |

### Performance

| Level | Compress | Decompress | Ratio |
|-------|----------|------------|-------|
| fast | 12.2 GB/s | 11.4 GB/s | 99.9% |
| default | 12.0 GB/s | 11.6 GB/s | 99.9% |
| best | 1.3 GB/s | 12.1 GB/s | 99.9% |

### Features

- Streaming compression/decompression
- Dictionary compression
- Content checksum
- Auto-detection (magic bytes)
- Multiple compression levels

## Basic Usage

```zig
const cz = @import("compressionz");

// Compress
const compressed = try cz.zstd.compress(data, allocator, .{});
defer allocator.free(compressed);

// Decompress
const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

## Compression Levels

```zig
// Fast compression (12+ GB/s)
const fast = try cz.zstd.compress(data, allocator, .{
    .level = .fast,
});

// Default (balanced)
const default = try cz.zstd.compress(data, allocator, .{
    .level = .default,
});

// Best compression (1.3 GB/s, maximum ratio)
const best = try cz.zstd.compress(data, allocator, .{
    .level = .best,
});
```

### Level Selection Guide

| Level | Use Case |
|-------|----------|
| `fastest` | Real-time, CPU-bound |
| `fast` | General purpose, speed priority |
| `default` | **Recommended** — balanced |
| `better` | Storage, archival |
| `best` | Maximum compression, one-time |

## Dictionary Compression

Zstd excels at dictionary compression for small data with known patterns:

```zig
// Create or load a dictionary
const dictionary = @embedFile("my_dictionary.bin");

// Compress with dictionary
const compressed = try cz.zstd.compressWithDict(data, dictionary, allocator, .{});
defer allocator.free(compressed);

// Decompress with same dictionary
const decompressed = try cz.zstd.decompressWithDict(compressed, dictionary, allocator, .{});
defer allocator.free(decompressed);
```

### Dictionary Benefits

Without dictionary (1 KB JSON):
- Original: 1,024 bytes
- Compressed: 890 bytes (13% reduction)

With trained dictionary:
- Original: 1,024 bytes
- Compressed: 312 bytes (70% reduction)

### Training Dictionaries

Use the `zstd` CLI to train a dictionary:

```bash
# Collect representative samples
ls samples/*.json > sample_files.txt

# Train dictionary (32KB is a good size)
zstd --train -o my_dictionary.bin --maxdict=32768 samples/*.json
```

## Streaming

Process large files without loading into memory:

```zig
const cz = @import("compressionz");
const std = @import("std");

// Streaming compression
pub fn compressFile(allocator: std.mem.Allocator, input: []const u8, output: []const u8) !void {
    const in_file = try std.fs.cwd().openFile(input, .{});
    defer in_file.close();

    const out_file = try std.fs.cwd().createFile(output, .{});
    defer out_file.close();

    var comp = try cz.zstd.Compressor(@TypeOf(out_file.writer())).init(allocator, out_file.writer(), .{});
    defer comp.deinit();

    var buf: [65536]u8 = undefined;
    while (true) {
        const n = try in_file.read(&buf);
        if (n == 0) break;
        try comp.writer().writeAll(buf[0..n]);
    }
    try comp.finish();
}

// Streaming decompression
pub fn decompressFile(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(input, .{});
    defer file.close();

    var decomp = try cz.zstd.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
    defer decomp.deinit();

    return decomp.reader().readAllAlloc(allocator, 1024 * 1024 * 1024);
}
```

## Decompression Safety

Protect against decompression bombs:

```zig
const safe = try cz.zstd.decompress(untrusted_data, allocator, .{
    .max_output_size = 100 * 1024 * 1024,  // 100 MB limit
});
```

## Format Details

### Frame Format

```
+-----------------------------------------------------+
| Magic Number (4 bytes): 0xFD2FB528                  |
+-----------------------------------------------------+
| Frame Header                                        |
|  - Frame Header Descriptor (1 byte)                 |
|  - Window Descriptor (0-1 bytes)                    |
|  - Dictionary ID (0-4 bytes)                        |
|  - Frame Content Size (0-8 bytes)                   |
+-----------------------------------------------------+
| Data Blocks                                         |
|  - Block Header (3 bytes)                           |
|  - Block Data (variable)                            |
|  - ... more blocks ...                              |
+-----------------------------------------------------+
| Checksum (4 bytes, optional)                        |
+-----------------------------------------------------+
```

### Magic Bytes

```zig
// Zstd magic number (little-endian)
const ZSTD_MAGIC: u32 = 0xFD2FB528;

// Detection
if (data.len >= 4 and
    data[0] == 0x28 and data[1] == 0xB5 and
    data[2] == 0x2F and data[3] == 0xFD)
{
    // It's Zstd
}
```

## Algorithm Details

Zstd uses a combination of techniques:

1. **LZ77 matching** — Find repeated sequences
2. **Finite State Entropy (FSE)** — Advanced entropy coding
3. **Huffman coding** — For literal sequences
4. **Repeat offsets** — Cache recent match offsets

### Why Zstd is Fast

- Optimized for modern CPUs (cache-friendly)
- SIMD acceleration (SSE2, AVX2, NEON)
- Efficient entropy coding
- Tuned for real-world data patterns

## When to Use Zstd

**Best for:**
- General-purpose compression
- Databases and data stores
- Log file compression
- Network protocols
- Any case without specific requirements

**Not ideal for:**
- Maximum speed (use LZ4)
- Web compatibility (use Gzip/Brotli)
- Pure Zig requirement (use LZ4/Snappy)

## Comparison with Alternatives

| Metric | Zstd | LZ4 | Gzip |
|--------|------|-----|------|
| Compress | 12 GB/s | 36 GB/s | 2.4 GB/s |
| Decompress | 11.6 GB/s | 8.1 GB/s | 2.4 GB/s |
| Ratio | 99.9% | 99.5% | 99.2% |
| Dictionary | Yes | No | No |
| Streaming | Yes | Yes | Yes |

## Resources

- [Zstd GitHub](https://github.com/facebook/zstd)
- [RFC 8878 - Zstandard Compression](https://datatracker.ietf.org/doc/html/rfc8878)
- [Zstd Documentation](https://facebook.github.io/zstd/)

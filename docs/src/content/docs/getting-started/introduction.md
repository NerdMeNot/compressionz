---
title: Introduction
description: Learn what compressionz is and why you should use it.
---

**compressionz** is a fast, ergonomic compression library for Zig that provides codec-specific APIs for multiple compression algorithms.

## The Problem

When working with compression in most languages, you face several challenges:

1. **Fragmented APIs** — Each codec has its own interface, options, and error handling
2. **System dependencies** — Libraries like zstd or brotli require system installation
3. **Performance trade-offs** — Choosing between speed, ratio, and memory usage
4. **Missing features** — Many bindings lack streaming, dictionaries, or proper error handling

## The Solution

compressionz solves all of these with:

### Codec-Specific APIs

```zig
// Each codec has its own module with tailored options
const zstd_compressed = try cz.zstd.compress(data, allocator, .{});
const lz4_compressed = try cz.lz4.frame.compress(data, allocator, .{});
const gzip_compressed = try cz.gzip.compress(data, allocator, .{});
const snappy_compressed = try cz.snappy.compress(data, allocator);
const brotli_compressed = try cz.brotli.compress(data, allocator, .{});
```

Each codec exposes only the features it supports — no runtime errors from unsupported options.

### Zero System Dependencies

All C libraries are vendored directly in the repository:

- **zstd 1.5.7** — BSD licensed
- **zlib 1.3.1** — zlib licensed
- **brotli** — MIT licensed

No `brew install`, no `apt-get`, no pkg-config. Just `zig build`.

### Pure Zig Performance

LZ4 and Snappy are implemented in pure Zig with explicit SIMD optimizations:

```zig
// 16-byte vectorized comparison
const v1: @Vector(16, u8) = src[pos..][0..16].*;
const v2: @Vector(16, u8) = src[match_pos..][0..16].*;
const mask = @as(u16, @bitCast(v1 == v2));
```

This achieves **36+ GB/s** compression throughput — competitive with hand-optimized C.

### Complete Feature Set

- **Streaming** — Process large files without loading into memory
- **Dictionaries** — Better ratios for small data with known patterns
- **Zero-copy** — Compress into pre-allocated buffers
- **Auto-detection** — Identify format from magic bytes
- **Archives** — ZIP and TAR support built-in
- **Safety** — Decompression bomb protection with `max_output_size`

## When to Use compressionz

**Use compressionz when you need:**

- Multiple compression algorithms in one project
- Predictable, cross-platform builds
- High performance without sacrificing ergonomics
- Streaming or dictionary compression
- ZIP/TAR archive handling

**Consider alternatives when you need:**

- Only one specific codec (use specialized bindings)
- Async I/O integration (compressionz is synchronous)
- Formats not yet supported (xz, lzma, etc.)

## Codec Overview

| Codec | Best For | Speed | Ratio |
|-------|----------|-------|-------|
| **Zstd** | General purpose | Fast | Excellent |
| **LZ4** | Maximum speed | Fastest | Good |
| **Snappy** | Real-time applications | Very fast | Moderate |
| **Gzip** | HTTP compatibility | Moderate | Good |
| **Brotli** | Static web assets | Slow | Best |

See [Choosing a Codec](/getting-started/choosing-a-codec/) for detailed guidance.

## Next Steps

Ready to get started?

1. [Install compressionz](/getting-started/installation/)
2. [Follow the Quick Start guide](/getting-started/quick-start/)
3. [Choose the right codec for your use case](/getting-started/choosing-a-codec/)

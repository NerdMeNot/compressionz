---
title: Choosing a Codec
description: Find the right compression algorithm for your use case.
---

compressionz supports seven compression codecs. This guide helps you choose the right one.

## Quick Decision Guide

| Scenario | Recommended | Why |
|----------|-------------|-----|
| **General purpose** | `cz.zstd` | Best balance of speed and ratio |
| **Maximum speed** | `cz.lz4.block` | 36+ GB/s, requires size tracking |
| **Real-time / messaging** | `cz.snappy` | Fast, self-describing format |
| **HTTP / web** | `cz.gzip` | Universal browser support |
| **Static assets** | `cz.brotli` | Best ratio for one-time compression |
| **File storage** | `cz.lz4.frame` | Self-describing with checksums |

## Codec Comparison

### Performance Summary (1 MB Data)

| Codec | Compress | Decompress | Ratio | Memory |
|-------|----------|------------|-------|--------|
| **LZ4 Block** | 36.6 GB/s | 8.1 GB/s | 99.5% | ~input |
| **Snappy** | 31.6 GB/s | 9.2 GB/s | 95.3% | ~input |
| **Zstd** | 12.0 GB/s | 11.6 GB/s | 99.9% | ~input |
| **LZ4 Frame** | 4.8 GB/s | 3.8 GB/s | 99.3% | ~input |
| **Gzip** | 2.4 GB/s | 2.4 GB/s | 99.2% | ~3x input |
| **Brotli** | 1.3 GB/s | 1.9 GB/s | 99.9% | ~2x input |

### Feature Matrix

| Codec | Streaming | Dictionary | Checksum | Auto-Detect | Self-Describing |
|-------|-----------|------------|----------|-------------|-----------------|
| `zstd` | Yes | Yes | Yes | Yes | Yes |
| `lz4.frame` | Yes | No | Yes | Yes | Yes |
| `lz4.block` | No | No | No | No | No |
| `snappy` | No | No | No | Yes | Yes |
| `gzip` | Yes | No | Yes | Yes | Yes |
| `brotli` | Yes | No | No | No | No |
| `zlib` | Yes | Yes | Yes | Yes | Yes |

---

## Zstd — Best Overall

**Use Zstd when:** You need excellent compression ratio with high speed.

```zig
const compressed = try cz.zstd.compress(data, allocator, .{});
```

### Strengths
- Exceptional compression ratio (99.9% on repetitive data)
- Very fast decompression (11+ GB/s)
- Fast compression at default level (12 GB/s)
- Supports dictionary compression
- Built-in content checksums

### Weaknesses
- Slightly slower than LZ4/Snappy for compression
- Larger compressed headers than raw formats

### Best For
- General-purpose compression
- Databases and data stores
- Log file compression
- Network protocols
- Anything that doesn't have a specific requirement

### Compression Levels

```zig
// Fastest - 12 GB/s
try cz.zstd.compress(data, allocator, .{ .level = .fast });

// Best ratio - 1.3 GB/s but maximum compression
try cz.zstd.compress(data, allocator, .{ .level = .best });
```

| Level | Compress | Decompress | Notes |
|-------|----------|------------|-------|
| fast | 12.2 GB/s | 11.4 GB/s | Recommended for speed |
| default | 12.0 GB/s | 11.6 GB/s | **Best balance** |
| best | 1.3 GB/s | 12.1 GB/s | Use for archival |

---

## LZ4 — Maximum Speed

LZ4 comes in two variants: **frame** (self-describing) and **block** (raw only).

### LZ4 Frame

**Use LZ4 Frame when:** You need fast, checksummed compression with streaming support.

```zig
const compressed = try cz.lz4.frame.compress(data, allocator, .{});
const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
```

- Self-describing format
- Built-in content checksums
- Streaming support
- ~4.8 GB/s throughput

### LZ4 Block

**Use LZ4 Block when:** You need absolute maximum speed and control both ends.

```zig
const compressed = try cz.lz4.block.compress(data, allocator);

// Must provide original_len for decompression!
const decompressed = try cz.lz4.block.decompressWithSize(compressed, original_len, allocator);
```

- **36+ GB/s** compression
- 8+ GB/s decompression
- No framing overhead
- Requires tracking original size externally

### Best For
- In-memory caching
- IPC / message passing
- Game asset compression
- Real-time data pipelines

---

## Snappy — Real-Time Speed

**Use Snappy when:** You need very fast compression with a self-describing format.

```zig
// Snappy has no options
const compressed = try cz.snappy.compress(data, allocator);
```

### Strengths
- Very fast (31+ GB/s compression)
- Self-describing format
- Simple block format
- Pure Zig implementation with SIMD

### Weaknesses
- Lower compression ratio (95.3%)
- No streaming support
- No dictionary support

### Best For
- Real-time applications
- Message queues
- Caching systems
- Situations where decompression speed > ratio

---

## Gzip — Universal Compatibility

**Use Gzip when:** You need compatibility with existing tools and systems.

```zig
const compressed = try cz.gzip.compress(data, allocator, .{});
```

### Strengths
- Universal support (browsers, servers, CLI tools)
- Good compression ratio
- Built-in CRC32 checksum
- Streaming support

### Weaknesses
- Slower than modern alternatives
- Higher memory for decompression (2-3x)
- No dictionary support

### Best For
- HTTP Content-Encoding
- Cross-platform file exchange
- Compatibility with existing .gz files
- When recipients may use other tools

---

## Brotli — Maximum Compression

**Use Brotli when:** Compression ratio matters more than speed.

```zig
const compressed = try cz.brotli.compress(data, allocator, .{
    .level = .best,
});
```

### Strengths
- Highest compression ratios
- Good decompression speed (1.5-2 GB/s)
- Optimized for text/web content
- Supported by all modern browsers

### Weaknesses
- Slow compression at high levels
- Higher memory usage
- No magic bytes (can't auto-detect)

### Best For
- Static web assets (CSS, JS, HTML)
- CDN content
- One-time compress, many decompress scenarios
- When storage/bandwidth cost matters

### Compression Levels

| Level | Compress | Ratio | Use Case |
|-------|----------|-------|----------|
| fast | 1.3 GB/s | 99.9% | Dynamic content |
| default | 1.3 GB/s | 99.9% | General use |
| best | 86 MB/s | 99.9%+ | Static assets |

---

## Zlib & Deflate — Legacy Formats

### Zlib

**Use Zlib when:** You need deflate with headers and Adler-32 checksum.

```zig
const compressed = try cz.zlib.compress(data, allocator, .{});
```

- Zlib header (2 bytes) + deflate + Adler-32 checksum
- Dictionary compression supported
- Common in PNG images, PDF files

### Deflate (Raw)

**Use Deflate when:** You need raw deflate without wrappers.

```zig
const compressed = try cz.zlib.compressDeflate(data, allocator, .{});
const decompressed = try cz.zlib.decompressDeflate(compressed, allocator, .{});
```

- Raw deflate stream, no headers
- Dictionary compression supported
- Used inside ZIP files, HTTP chunked encoding

---

## Decision Flowchart

```
Need compression?
|
+- Need maximum speed?
|  +- Control both ends? -> LZ4 Block (36 GB/s)
|  +- Need self-describing? -> Snappy (31 GB/s)
|
+- Need best ratio?
|  +- One-time compress? -> Brotli best
|  +- Repeated compress? -> Zstd best
|
+- Need HTTP compatibility?
|  +- Modern browsers only? -> Brotli
|  +- Universal support? -> Gzip
|
+- Need streaming?
|  +- Fast + checksums? -> LZ4 Frame
|  +- Best ratio? -> Zstd
|
+- Not sure?
   +- Zstd default (best overall balance)
```

## Summary Recommendations

1. **Default choice**: Zstd — excellent at everything
2. **Speed critical**: LZ4 Block — 36+ GB/s
3. **Web content**: Brotli (static) or Gzip (dynamic)
4. **Real-time**: Snappy — fast with self-describing format
5. **File archives**: LZ4 Frame — checksums + streaming

See [Benchmarks](/performance/benchmarks/) for detailed performance data.

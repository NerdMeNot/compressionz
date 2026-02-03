# Compressionz Benchmarks

Comprehensive performance benchmarks comparing all compression codecs in the compressionz library.

---

## Quick Decision Guide

Not sure which codec to use? Here's the short answer:

| Scenario | Recommended Codec | Why |
|----------|-------------------|-----|
| **General purpose** | `cz.zstd` default | Best balance of speed (12 GB/s) and ratio (99.9%) |
| **Maximum speed** | `cz.lz4.block` | 36+ GB/s compression, requires tracking size externally |
| **Real-time / streaming** | `cz.snappy` | 31 GB/s with self-describing format |
| **Web assets** | `cz.brotli` best | Highest compression for one-time compress, many decompress |
| **HTTP compatibility** | `cz.gzip` | Universal browser/server support |
| **File archives** | `cz.lz4.frame` | Self-describing with checksums at ~4.8 GB/s |

---

## Benchmark Winners

Based on 1 MB test data with mixed patterns (repetitive text, sequential bytes, varied data):

### Compression Speed

| Rank | Codec | Throughput | Notes |
|------|-------|------------|-------|
| 1 | **LZ4 Block** | 36.6 GB/s | Raw block, no framing |
| 2 | **Snappy** | 31.6 GB/s | Self-describing format |
| 3 | **Zstd** (fast/default) | 12.0 GB/s | Excellent ratio at high speed |
| 4 | LZ4 Frame | 4.8 GB/s | With checksums and framing |
| 5 | Gzip (fast) | 2.4 GB/s | Wide compatibility |
| 6 | Brotli (fast) | 1.3 GB/s | Better for static content |

### Decompression Speed

| Rank | Codec | Throughput | Notes |
|------|-------|------------|-------|
| 1 | **Zstd** (best) | 12.1 GB/s | Fast decompression regardless of level |
| 2 | **Zstd** (default) | 11.6 GB/s | Consistent performance |
| 3 | **Snappy** | 9.2 GB/s | Very fast |
| 4 | LZ4 Block | 8.1 GB/s | Simple format |
| 5 | LZ4 Frame | 3.8 GB/s | Checksum verification overhead |
| 6 | Gzip | 2.9 GB/s | Deflate-based |

### Compression Ratio (Higher = Better)

| Rank | Codec | Ratio | Compressed Size |
|------|-------|-------|-----------------|
| 1 | **Zstd** (any level) | 99.9% | 677-684 bytes |
| 1 | **Brotli** (any level) | 99.9% | 535-616 bytes |
| 3 | **Gzip** (default/best) | 99.6% | 4,382 bytes |
| 4 | LZ4 Block | 99.5% | 4,541 bytes |
| 5 | LZ4 Frame | 99.3% | 7,057 bytes |
| 6 | Snappy | 95.3% | 47,468 bytes |

### Best Overall Balance

**Winner: Zstd (default)**

| Metric | Value |
|--------|-------|
| Compression | 12.0 GB/s |
| Decompression | 11.6 GB/s |
| Ratio | 99.9% |
| Memory | 981 KB |

Zstd achieves near-maximum compression ratios while maintaining compression speeds that rival dedicated speed-focused codecs. It's the clear choice for most applications.

---

## Detailed Results

### Test Environment

> **Note:** These are reference benchmarks. Actual performance will vary based on your hardware, data characteristics, and workload. Run `zig build bench -Doptimize=ReleaseFast` to benchmark on your own system.

| Property | Value |
|----------|-------|
| Build | ReleaseFast optimization |
| Iterations | 20 benchmark runs (3 warmup) |
| Data | Mixed-pattern: 25% repetitive text, 25% sequential, 25% text, 25% varied |

### 1 KB Data

Small data benchmarks are dominated by per-operation overhead. Use dictionary compression for better small-data ratios.

| Codec | Level | Ratio | Size | Compress | Decompress | Comp Mem | Dec Mem |
|-------|-------|-------|------|----------|------------|----------|---------|
| LZ4 Frame | fast | 41.2% | 588 B | 9.2 us | 5.1 us | 1.8 KB | 65.0 KB |
| LZ4 Frame | default | 41.2% | 588 B | 8.9 us | 4.8 us | 1.8 KB | 65.0 KB |
| LZ4 Block | default | 43.9% | 561 B | 3.8 us | 1.7 us | 1.0 KB | 1.0 KB |
| Snappy | default | 42.1% | 579 B | 7.2 us | 0.1 us | 1.7 KB | 1.0 KB |
| Zstd | fast | 43.0% | 570 B | 13.6 us | 0.7 us | 1.6 KB | 1.0 KB |
| Zstd | default | 43.0% | 570 B | 10.4 us | 0.7 us | 1.6 KB | 1.0 KB |
| Zstd | best | 43.0% | 570 B | 177.9 us | 0.9 us | 1.6 KB | 1.0 KB |
| Gzip | fast | 40.0% | 600 B | 20.3 us | 6.7 us | 1.6 KB | 3.3 KB |
| Gzip | default | 40.0% | 600 B | 24.3 us | 5.6 us | 1.6 KB | 3.3 KB |
| Gzip | best | 40.1% | 599 B | 31.6 us | 5.4 us | 1.6 KB | 3.3 KB |
| Brotli | fast | 41.8% | 582 B | 24.1 us | 6.3 us | 1.0 KB | 3.3 KB |
| Brotli | default | 42.0% | 580 B | 26.1 us | 6.1 us | 1.0 KB | 3.2 KB |
| Brotli | best | 44.9% | 551 B | 1.6 ms | 10.0 us | 1.0 KB | 3.1 KB |

**1 KB Winner**: Brotli best achieves highest ratio (44.9%), but Zstd offers best speed/ratio balance.

### 10 KB Data

| Codec | Level | Ratio | Size | Compress | Decompress | Comp Mem | Dec Mem |
|-------|-------|-------|------|----------|------------|----------|---------|
| LZ4 Frame | fast | 93.6% | 641 B | 11.4 us | 6.2 us | 10.7 KB | 73.8 KB |
| LZ4 Frame | default | 93.6% | 641 B | 10.1 us | 6.4 us | 10.7 KB | 73.8 KB |
| LZ4 Block | default | 93.9% | 614 B | 8.9 us | 2.7 us | 10.4 KB | 9.8 KB |
| Snappy | default | 89.8% | 1,018 B | 10.0 us | 2.7 us | 12.4 KB | 9.8 KB |
| Zstd | fast | 94.1% | 595 B | 16.9 us | 3.1 us | 10.4 KB | 9.8 KB |
| Zstd | default | 94.1% | 595 B | 15.5 us | 3.0 us | 10.4 KB | 9.8 KB |
| Zstd | best | 94.1% | 592 B | 60.7 us | 3.6 us | 10.4 KB | 9.8 KB |
| Gzip | fast | 92.9% | 712 B | 26.0 us | 10.4 us | 10.5 KB | 16.7 KB |
| Gzip | default | 93.1% | 695 B | 36.4 us | 12.1 us | 10.5 KB | 16.3 KB |
| Gzip | best | 93.1% | 693 B | 36.6 us | 12.7 us | 10.5 KB | 16.2 KB |
| Brotli | fast | 94.0% | 604 B | 33.1 us | 22.3 us | 10.4 KB | 28.6 KB |
| Brotli | default | 94.1% | 595 B | 40.1 us | 23.1 us | 10.4 KB | 28.4 KB |
| Brotli | best | 94.7% | 529 B | 978.5 us | 29.2 us | 10.3 KB | 26.3 KB |

**10 KB Winner**: Zstd achieves best ratio (94.1%) with fast compression. Brotli best edges slightly higher (94.7%) but at 60x compression time.

### 100 KB Data

| Codec | Level | Ratio | Size | Compress | Decompress | Comp Mem | Dec Mem |
|-------|-------|-------|------|----------|------------|----------|---------|
| LZ4 Frame | fast | 99.0% | 1.0 KB | 25.0 us | 29.7 us | 99.2 KB | 161.7 KB |
| LZ4 Frame | default | 99.0% | 1.0 KB | 23.0 us | 30.1 us | 99.2 KB | 161.7 KB |
| LZ4 Block | default | 99.0% | 968 B | 11.6 us | 11.7 us | 99.0 KB | 97.7 KB |
| Snappy | default | 94.8% | 5.1 KB | 10.0 us | 11.6 us | 119.1 KB | 97.7 KB |
| Zstd | fast | 99.4% | 599 B | 19.7 us | 9.9 us | 98.6 KB | 97.7 KB |
| Zstd | default | 99.4% | 599 B | 19.1 us | 10.5 us | 98.6 KB | 97.7 KB |
| Zstd | best | 99.4% | 596 B | 176.2 us | 10.8 us | 98.6 KB | 97.7 KB |
| Gzip | fast | 98.6% | 1.4 KB | 63.5 us | 66.0 us | 99.1 KB | 267.8 KB |
| Gzip | default | 98.9% | 1.0 KB | 166.3 us | 62.4 us | 98.8 KB | 200.6 KB |
| Gzip | best | 98.9% | 1.0 KB | 311.7 us | 128.8 us | 98.8 KB | 199.9 KB |
| Brotli | fast | 99.4% | 608 B | 60.5 us | 74.5 us | 98.3 KB | 228.0 KB |
| Brotli | default | 99.4% | 598 B | 81.6 us | 76.4 us | 98.3 KB | 224.3 KB |
| Brotli | best | 99.5% | 539 B | 3.9 ms | 89.0 us | 98.2 KB | 202.1 KB |

**100 KB Winner**: Zstd dominates with 99.4% ratio, fastest decompression (9.9 us), and minimal memory.

### 1 MB Data

| Codec | Level | Ratio | Size | Compress | Decompress | Comp Mem | Dec Mem |
|-------|-------|-------|------|----------|------------|----------|---------|
| LZ4 Frame | fast | 99.3% | 6.9 KB | 208.9 us | 270.4 us | 987.8 KB | 1.0 MB |
| LZ4 Frame | default | 99.3% | 6.9 KB | 214.8 us | 263.9 us | 987.8 KB | 1.0 MB |
| LZ4 Block | default | 99.5% | 4.4 KB | 27.3 us | 123.2 us | 984.8 KB | 976.6 KB |
| Snappy | default | 95.3% | 46.4 KB | 31.7 us | 108.3 us | 1.1 MB | 976.6 KB |
| Zstd | fast | 99.9% | 684 B | 82.3 us | 87.5 us | 981.0 KB | 976.6 KB |
| Zstd | default | 99.9% | 684 B | 83.4 us | 86.5 us | 981.0 KB | 976.6 KB |
| Zstd | best | 99.9% | 677 B | 783.4 us | 82.8 us | 981.0 KB | 976.6 KB |
| Gzip | fast | 99.2% | 7.5 KB | 408.9 us | 412.3 us | 984.4 KB | 2.8 MB |
| Gzip | default | 99.6% | 4.3 KB | 1.4 ms | 353.4 us | 981.2 KB | 1.6 MB |
| Gzip | best | 99.6% | 4.3 KB | 1.4 ms | 347.3 us | 981.2 KB | 1.6 MB |
| Brotli | fast | 99.9% | 616 B | 751.1 us | 537.1 us | 977.4 KB | 1.8 MB |
| Brotli | default | 99.9% | 608 B | 767.1 us | 564.9 us | 977.4 KB | 1.8 MB |
| Brotli | best | 99.9% | 535 B | 11.6 ms | 678.1 us | 977.3 KB | 1.6 MB |

**1 MB Winner**: Zstd achieves the highest compression ratio (99.9%) while being significantly faster than competitors at that ratio level.

---

## Throughput Summary (1 MB)

| Codec | Level | Ratio | Compress | Decompress | Peak Memory |
|-------|-------|-------|----------|------------|-------------|
| **LZ4 Block** | default | 99.5% | **36.6 GB/s** | 8.1 GB/s | 984.8 KB |
| **Snappy** | default | 95.3% | **31.6 GB/s** | 9.2 GB/s | 1.1 MB |
| **Zstd** | fast | 99.9% | **12.2 GB/s** | **11.4 GB/s** | 981.0 KB |
| **Zstd** | default | 99.9% | **12.0 GB/s** | **11.6 GB/s** | 981.0 KB |
| Zstd | best | 99.9% | 1.3 GB/s | **12.1 GB/s** | 981.0 KB |
| LZ4 Frame | fast | 99.3% | 4.8 GB/s | 3.7 GB/s | 987.8 KB |
| LZ4 Frame | default | 99.3% | 4.7 GB/s | 3.8 GB/s | 987.8 KB |
| Gzip | fast | 99.2% | 2.4 GB/s | 2.4 GB/s | 984.4 KB |
| Gzip | default | 99.6% | 723 MB/s | 2.8 GB/s | 981.2 KB |
| Gzip | best | 99.6% | 691 MB/s | 2.9 GB/s | 981.2 KB |
| Brotli | fast | 99.9% | 1.3 GB/s | 1.9 GB/s | 977.4 KB |
| Brotli | default | 99.9% | 1.3 GB/s | 1.8 GB/s | 977.4 KB |
| Brotli | best | 99.9% | 86 MB/s | 1.5 GB/s | 977.3 KB |

---

## Codec Deep Dives

### Zstd — Best Overall

```zig
const cz = @import("compressionz");

const compressed = try cz.zstd.compress(data, allocator, .{});
defer allocator.free(compressed);

const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

**Strengths:**
- Exceptional compression ratio (99.9% on test data)
- Extremely fast decompression (11-12 GB/s)
- Fast compression at default level (12 GB/s)
- Supports dictionary compression for small data
- Streaming support

**Weaknesses:**
- Slightly slower than LZ4/Snappy for compression
- C library dependency (vendored)

**Best for:** General-purpose compression, databases, log files, network protocols, file storage.

**Compression levels:**
| Level | Compress | Decompress | Ratio |
|-------|----------|------------|-------|
| fast | 12.2 GB/s | 11.4 GB/s | 99.9% |
| default | 12.0 GB/s | 11.6 GB/s | 99.9% |
| best | 1.3 GB/s | 12.1 GB/s | 99.9% |

### LZ4 Block — Fastest

```zig
const cz = @import("compressionz");

const compressed = try cz.lz4.block.compress(data, allocator);
defer allocator.free(compressed);

// Must provide original size for decompression
const decompressed = try cz.lz4.block.decompressWithSize(compressed, data.len, allocator);
defer allocator.free(decompressed);
```

**Strengths:**
- Fastest compression (36+ GB/s)
- Pure Zig implementation with SIMD
- Minimal memory overhead
- Simple block format

**Weaknesses:**
- Requires tracking uncompressed size externally
- No built-in checksums
- Not self-describing

**Best for:** Internal data structures, in-memory caching, IPC, situations where you control both ends.

### LZ4 Frame — Fast with Safety

```zig
const cz = @import("compressionz");

const compressed = try cz.lz4.frame.compress(data, allocator, .{});
defer allocator.free(compressed);

const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

**Strengths:**
- Self-describing format
- Built-in content checksums
- Streaming support
- Pure Zig implementation

**Weaknesses:**
- Slower than raw LZ4 due to framing overhead
- Lower compression ratio than Zstd

**Best for:** File storage, data exchange, streaming compression where frame format is needed.

### Snappy — Real-Time Speed

```zig
const cz = @import("compressionz");

const compressed = try cz.snappy.compress(data, allocator);
defer allocator.free(compressed);

const decompressed = try cz.snappy.decompress(compressed, allocator);
defer allocator.free(decompressed);
```

**Strengths:**
- Very fast compression (31+ GB/s)
- Fast decompression (9+ GB/s)
- Self-describing format
- Pure Zig implementation with SIMD

**Weaknesses:**
- Lower compression ratio (95.3%)
- No streaming support

**Best for:** Real-time applications, caching systems, message passing, when speed matters more than ratio.

### Gzip — Universal Compatibility

```zig
const cz = @import("compressionz");

const compressed = try cz.gzip.compress(data, allocator, .{});
defer allocator.free(compressed);

const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

**Strengths:**
- Universal support (browsers, servers, tools)
- Good compression ratio (99.2-99.6%)
- Built-in CRC32 checksum
- Streaming support

**Weaknesses:**
- Slower than modern alternatives
- Higher decompression memory (2-3x)

**Best for:** HTTP compression, cross-platform compatibility, archive interchange.

### Brotli — Maximum Compression

```zig
const cz = @import("compressionz");

const compressed = try cz.brotli.compress(data, allocator, .{ .level = .best });
defer allocator.free(compressed);

const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

**Strengths:**
- Highest compression ratios (especially at best level)
- Good decompression speed
- Optimized for web content

**Weaknesses:**
- Slow compression at high levels
- Higher decompression memory
- No magic bytes for detection

**Best for:** Static web assets, CDN content, one-time compress / many decompress scenarios.

**Compression levels:**
| Level | Compress | Decompress | Ratio | Smallest Size |
|-------|----------|------------|-------|---------------|
| fast | 1.3 GB/s | 1.9 GB/s | 99.9% | 616 bytes |
| default | 1.3 GB/s | 1.8 GB/s | 99.9% | 608 bytes |
| best | 86 MB/s | 1.5 GB/s | 99.9% | 535 bytes |

---

## Memory Characteristics

| Codec | Compression | Decompression | Notes |
|-------|-------------|---------------|-------|
| **LZ4 Block** | ~input | ~input | Minimal overhead |
| **Snappy** | ~1.1x input | ~input | Slight compression overhead |
| **Zstd** | ~input | ~input | Most efficient |
| **LZ4 Frame** | ~input | ~1.0x input | Frame buffer overhead |
| **Gzip** | ~input | ~2-3x input | Sliding window buffer |
| **Brotli** | ~input | ~1.6-1.8x input | Dictionary buffer |

For memory-constrained environments, prefer Zstd, LZ4 Block, or Snappy.

---

## Choosing a Compression Level

All codecs that support levels use the same `Level` enum: `fastest`, `fast`, `default`, `better`, `best`.

| Level | Use Case |
|-------|----------|
| `fastest` | Maximum throughput, acceptable ratio |
| `fast` | High throughput with good ratio |
| `default` | **Recommended** — balanced performance |
| `better` | Better ratio, moderate speed impact |
| `best` | Maximum compression, significant speed cost |

**Recommendation:** Use `default` unless you have specific requirements. The difference between `fast` and `default` is often negligible, while `best` can be 10-100x slower.

---

## Metrics Explained

| Metric | Description |
|--------|-------------|
| **Ratio %** | Percentage of data reduced. 99% means compressed to 1% of original size. |
| **Compress** | Compression throughput in GB/s or MB/s |
| **Decompress** | Decompression throughput in GB/s or MB/s |
| **Peak Memory** | Maximum memory allocated during operation |
| **Comp Mem / Dec Mem** | Memory used for compression / decompression |

### How Ratio is Calculated

```
Ratio = (1 - compressed_size / original_size) x 100%
```

A 99.9% ratio means 1 MB compresses to ~1 KB (0.1% of original).

---

## Running Benchmarks

```bash
# Run with optimizations (recommended for accurate results)
zig build bench -Doptimize=ReleaseFast

# Run in debug mode (slower, but useful for development)
zig build bench
```

### Benchmark Configuration

Edit `benchmarks/main.zig` to customize:

```zig
const WARMUP_ITERS = 3;   // Warmup iterations (not counted)
const BENCH_ITERS = 20;   // Measured iterations

const DATA_SIZES = [_]usize{
    1_000,      // 1 KB
    10_000,     // 10 KB
    100_000,    // 100 KB
    1_000_000,  // 1 MB
};
```

---

## Caveats and Notes

### Data Characteristics Matter

These benchmarks use mixed-pattern test data. Your results will vary based on:

- **Highly compressible data** (logs, JSON): Higher ratios, faster compression
- **Already compressed data** (JPEG, video): Low ratios, may expand
- **Random data**: Near 0% ratio, maximum CPU time wasted

### Measurement Notes

- Wall-clock time is measured using `std.time.Timer`
- CPU time is measured via `getrusage()` system call
- Memory is measured via custom counting allocator
- Results are averaged over 20 iterations after 3 warmup runs

### LZ4 Block Special Case

LZ4 block format requires the original size for decompression:

```zig
const cz = @import("compressionz");

// Compression works normally
const compressed = try cz.lz4.block.compress(data, allocator);
defer allocator.free(compressed);

// Decompression requires original size
const decompressed = try cz.lz4.block.decompressWithSize(compressed, data.len, allocator);
defer allocator.free(decompressed);
```

Store the original size alongside compressed data when using LZ4 block.

### Dictionary Compression

For small data with known patterns, dictionary compression can dramatically improve ratios:

```zig
const cz = @import("compressionz");

const dictionary = "common patterns in your data...";

const compressed = try cz.zstd.compressWithDict(data, dictionary, allocator, .{});
defer allocator.free(compressed);

const decompressed = try cz.zstd.decompressWithDict(compressed, dictionary, allocator, .{});
defer allocator.free(decompressed);
```

Supported by: `cz.zstd`, `cz.zlib`

---

## Summary Table

| Codec | Compress | Decompress | Ratio | Streaming | Dictionary | Self-Describing |
|-------|----------|------------|-------|-----------|------------|-----------------|
| **Zstd** | 12 GB/s | 11.6 GB/s | 99.9% | Yes | Yes | Yes |
| **LZ4 Block** | 36.6 GB/s | 8.1 GB/s | 99.5% | No | No | No |
| **LZ4 Frame** | 4.8 GB/s | 3.8 GB/s | 99.3% | Yes | No | Yes |
| **Snappy** | 31.6 GB/s | 9.2 GB/s | 95.3% | No | No | Yes |
| **Gzip** | 2.4 GB/s | 2.4 GB/s | 99.2% | Yes | No | Yes |
| **Brotli** | 1.3 GB/s | 1.9 GB/s | 99.9% | Yes | No | No |

---

## Version Information

- **compressionz**: Current development version
- **Zstd**: 1.5.7 (vendored)
- **zlib**: 1.3.1 (vendored)
- **Brotli**: Latest (vendored)
- **LZ4**: Pure Zig implementation
- **Snappy**: Pure Zig implementation

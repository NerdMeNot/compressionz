---
title: Benchmarks
description: Comprehensive performance benchmarks for all codecs.
---

This page presents detailed benchmark results for all compressionz codecs.

## Test Environment

| Property | Value |
|----------|-------|
| Platform | macOS (Darwin) on Apple Silicon (aarch64) |
| Build | ReleaseFast optimization |
| Iterations | 20 benchmark runs (3 warmup) |
| Data | Mixed-pattern: repetitive text, sequential bytes, varied data |

## Quick Summary (1 MB Data)

| Codec | Compress | Decompress | Ratio | Recommendation |
|-------|----------|------------|-------|----------------|
| **LZ4 Block** | 36.6 GB/s | 8.1 GB/s | 99.5% | Maximum speed |
| **Snappy** | 31.6 GB/s | 9.2 GB/s | 95.3% | Real-time |
| **Zstd** | 12.0 GB/s | 11.6 GB/s | 99.9% | **Best overall** |
| LZ4 Frame | 4.8 GB/s | 3.8 GB/s | 99.3% | File storage |
| Gzip | 2.4 GB/s | 2.4 GB/s | 99.2% | Compatibility |
| Brotli | 1.3 GB/s | 1.9 GB/s | 99.9% | Static assets |

## Detailed Results by Data Size

### 1 KB Data

| Codec | Level | Ratio | Size | Compress | Decompress |
|-------|-------|-------|------|----------|------------|
| LZ4 Frame | fast | 41.2% | 588 B | 9.2 µs | 5.1 µs |
| LZ4 Frame | default | 41.2% | 588 B | 8.9 µs | 4.8 µs |
| LZ4 Block | default | 43.9% | 561 B | 3.8 µs | 1.7 µs |
| Snappy | default | 42.1% | 579 B | 7.2 µs | 0.1 µs |
| Zstd | fast | 43.0% | 570 B | 13.6 µs | 0.7 µs |
| Zstd | default | 43.0% | 570 B | 10.4 µs | 0.7 µs |
| Zstd | best | 43.0% | 570 B | 177.9 µs | 0.9 µs |
| Gzip | fast | 40.0% | 600 B | 20.3 µs | 6.7 µs |
| Gzip | default | 40.0% | 600 B | 24.3 µs | 5.6 µs |
| Gzip | best | 40.1% | 599 B | 31.6 µs | 5.4 µs |
| Brotli | fast | 41.8% | 582 B | 24.1 µs | 6.3 µs |
| Brotli | default | 42.0% | 580 B | 26.1 µs | 6.1 µs |
| Brotli | best | 44.9% | 551 B | 1.6 ms | 10.0 µs |

**1 KB Winner:** Brotli best achieves highest ratio (44.9%), but Zstd offers best speed/ratio balance.

### 10 KB Data

| Codec | Level | Ratio | Size | Compress | Decompress |
|-------|-------|-------|------|----------|------------|
| LZ4 Frame | fast | 93.6% | 641 B | 11.4 µs | 6.2 µs |
| LZ4 Frame | default | 93.6% | 641 B | 10.1 µs | 6.4 µs |
| LZ4 Block | default | 93.9% | 614 B | 8.9 µs | 2.7 µs |
| Snappy | default | 89.8% | 1,018 B | 10.0 µs | 2.7 µs |
| Zstd | fast | 94.1% | 595 B | 16.9 µs | 3.1 µs |
| Zstd | default | 94.1% | 595 B | 15.5 µs | 3.0 µs |
| Zstd | best | 94.1% | 592 B | 60.7 µs | 3.6 µs |
| Gzip | fast | 92.9% | 712 B | 26.0 µs | 10.4 µs |
| Gzip | default | 93.1% | 695 B | 36.4 µs | 12.1 µs |
| Gzip | best | 93.1% | 693 B | 36.6 µs | 12.7 µs |
| Brotli | fast | 94.0% | 604 B | 33.1 µs | 22.3 µs |
| Brotli | default | 94.1% | 595 B | 40.1 µs | 23.1 µs |
| Brotli | best | 94.7% | 529 B | 978.5 µs | 29.2 µs |

**10 KB Winner:** Zstd achieves best ratio (94.1%) with fast compression.

### 100 KB Data

| Codec | Level | Ratio | Size | Compress | Decompress |
|-------|-------|-------|------|----------|------------|
| LZ4 Frame | fast | 99.0% | 1.0 KB | 25.0 µs | 29.7 µs |
| LZ4 Frame | default | 99.0% | 1.0 KB | 23.0 µs | 30.1 µs |
| LZ4 Block | default | 99.0% | 968 B | 11.6 µs | 11.7 µs |
| Snappy | default | 94.8% | 5.1 KB | 10.0 µs | 11.6 µs |
| Zstd | fast | 99.4% | 599 B | 19.7 µs | 9.9 µs |
| Zstd | default | 99.4% | 599 B | 19.1 µs | 10.5 µs |
| Zstd | best | 99.4% | 596 B | 176.2 µs | 10.8 µs |
| Gzip | fast | 98.6% | 1.4 KB | 63.5 µs | 66.0 µs |
| Gzip | default | 98.9% | 1.0 KB | 166.3 µs | 62.4 µs |
| Gzip | best | 98.9% | 1.0 KB | 311.7 µs | 128.8 µs |
| Brotli | fast | 99.4% | 608 B | 60.5 µs | 74.5 µs |
| Brotli | default | 99.4% | 598 B | 81.6 µs | 76.4 µs |
| Brotli | best | 99.5% | 539 B | 3.9 ms | 89.0 µs |

**100 KB Winner:** Zstd dominates with 99.4% ratio and fastest decompression.

### 1 MB Data

| Codec | Level | Ratio | Size | Compress | Decompress |
|-------|-------|-------|------|----------|------------|
| LZ4 Frame | fast | 99.3% | 6.9 KB | 208.9 µs | 270.4 µs |
| LZ4 Frame | default | 99.3% | 6.9 KB | 214.8 µs | 263.9 µs |
| LZ4 Block | default | 99.5% | 4.4 KB | 27.3 µs | 123.2 µs |
| Snappy | default | 95.3% | 46.4 KB | 31.7 µs | 108.3 µs |
| Zstd | fast | 99.9% | 684 B | 82.3 µs | 87.5 µs |
| Zstd | default | 99.9% | 684 B | 83.4 µs | 86.5 µs |
| Zstd | best | 99.9% | 677 B | 783.4 µs | 82.8 µs |
| Gzip | fast | 99.2% | 7.5 KB | 408.9 µs | 412.3 µs |
| Gzip | default | 99.6% | 4.3 KB | 1.4 ms | 353.4 µs |
| Gzip | best | 99.6% | 4.3 KB | 1.4 ms | 347.3 µs |
| Brotli | fast | 99.9% | 616 B | 751.1 µs | 537.1 µs |
| Brotli | default | 99.9% | 608 B | 767.1 µs | 564.9 µs |
| Brotli | best | 99.9% | 535 B | 11.6 ms | 678.1 µs |

**1 MB Winner:** Zstd achieves 99.9% ratio at 12 GB/s — unbeatable balance.

## Throughput Charts

### Compression Speed (1 MB)

```
LZ4 Block  ████████████████████████████████████████ 36.6 GB/s
Snappy     ██████████████████████████████████ 31.6 GB/s
Zstd       █████████████ 12.0 GB/s
LZ4 Frame  █████ 4.8 GB/s
Gzip       ███ 2.4 GB/s
Brotli     █ 1.3 GB/s
```

### Decompression Speed (1 MB)

```
Zstd       █████████████ 11.6 GB/s
Snappy     ██████████ 9.2 GB/s
LZ4 Block  █████████ 8.1 GB/s
LZ4 Frame  ████ 3.8 GB/s
Gzip       ███ 2.4 GB/s
Brotli     ██ 1.9 GB/s
```

### Compression Ratio (1 MB)

```
Zstd       ██████████████████████████████████████████████ 99.9%
Brotli     ██████████████████████████████████████████████ 99.9%
Gzip       █████████████████████████████████████████████ 99.6%
LZ4 Block  █████████████████████████████████████████████ 99.5%
LZ4 Frame  ████████████████████████████████████████████ 99.3%
Snappy     ███████████████████████████████████████ 95.3%
```

## Category Winners

### Fastest Compression

**LZ4 Block — 36.6 GB/s**

```zig
const compressed = try cz.lz4.block.compress(data, allocator);
// Requires original size for decompression
```

### Fastest Decompression

**Zstd (best level) — 12.1 GB/s**

```zig
const compressed = try cz.zstd.compress(data, allocator, .{
    .level = .best,
});
// Slow to compress, fast to decompress
```

### Best Compression Ratio

**Brotli (best level) — 99.9%+**

```zig
const compressed = try cz.brotli.compress(data, allocator, .{
    .level = .best,
});
// 535 bytes from 1 MB (test data)
```

### Best Overall Balance

**Zstd (default) — 12 GB/s compress, 11.6 GB/s decompress, 99.9% ratio**

```zig
const compressed = try cz.zstd.compress(data, allocator, .{});
```

## Memory Usage

| Codec | Compression | Decompression |
|-------|-------------|---------------|
| LZ4 Block | 984.8 KB | 976.6 KB |
| LZ4 Frame | 987.8 KB | 1.0 MB |
| Snappy | 1.1 MB | 976.6 KB |
| Zstd | 981.0 KB | 976.6 KB |
| Gzip | 984.4 KB | 2.8 MB |
| Brotli | 977.4 KB | 1.8 MB |

**Most Memory-Efficient:** Zstd and LZ4 Block use ~input size only.

## Running Benchmarks

```bash
# Run with optimizations (required for accurate results)
zig build bench -Doptimize=ReleaseFast

# Output includes:
# - Per-codec results at each data size
# - Throughput in MB/s and GB/s
# - Memory usage
# - CPU time
```

## Methodology

### Test Data

Mixed-pattern data designed for realistic compression:

```
25% — Repetitive text ("The quick brown fox...")
25% — Sequential bytes with variations
25% — Repetitive text (repeated)
25% — Varied pseudorandom data
```

### Measurement

- **Wall time:** `std.time.Timer`
- **CPU time:** `getrusage()` system call
- **Memory:** Custom counting allocator
- **Iterations:** 20 measured runs after 3 warmup

### Reproducibility

Results may vary based on:

- CPU architecture and generation
- Memory speed and cache sizes
- Operating system
- Data characteristics

Run benchmarks on your target hardware for accurate numbers.

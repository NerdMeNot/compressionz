---
title: Codecs Overview
description: Understanding compression algorithms supported by compressionz.
---

compressionz supports seven compression codecs, each with different characteristics. This page provides a high-level overview.

## Codec Summary

| Codec | Type | Speed | Ratio | Best For |
|-------|------|-------|-------|----------|
| [Zstd](/codecs/zstd/) | Dictionary | Very Fast | Excellent | General purpose |
| [LZ4](/codecs/lz4/) | LZ77 | Fastest | Good | Speed-critical |
| [Snappy](/codecs/snappy/) | LZ77 | Very Fast | Moderate | Real-time |
| [Gzip](/codecs/gzip/) | Deflate | Moderate | Good | Compatibility |
| [Brotli](/codecs/brotli/) | Dictionary | Slow | Best | Web assets |
| [Zlib](/codecs/zlib/) | Deflate | Moderate | Good | PNG, legacy |

## Compression Algorithm Families

### LZ77-Based

**How it works:** Find repeated sequences, replace with (offset, length) pairs.

**Codecs:** LZ4, Snappy

**Characteristics:**
- Very fast compression and decompression
- Moderate compression ratios
- Simple implementation
- Low memory usage

### Deflate-Based

**How it works:** LZ77 + Huffman coding for better ratios.

**Codecs:** Gzip, Zlib, Deflate

**Characteristics:**
- Good compression ratios
- Moderate speed
- Universal compatibility
- Established standard

### Dictionary-Based

**How it works:** Pre-computed probability tables and advanced entropy coding.

**Codecs:** Zstd, Brotli

**Characteristics:**
- Excellent compression ratios
- Asymmetric (compression slower than decompression)
- Higher memory usage
- Modern algorithms

## Performance Comparison

### Throughput (1 MB Data)

```
Compression Speed (GB/s)
+------------------------------------------------------+
| LZ4 Block #################################### 36.6  |
| Snappy    ############################### 31.6       |
| Zstd      ############ 12.0                          |
| LZ4 Frame ##### 4.8                                  |
| Gzip      ## 2.4                                     |
| Brotli    # 1.3                                      |
+------------------------------------------------------+

Decompression Speed (GB/s)
+------------------------------------------------------+
| Zstd      ############ 11.6                          |
| Snappy    ######### 9.2                              |
| LZ4 Block ######## 8.1                               |
| LZ4 Frame #### 3.8                                   |
| Gzip      ## 2.4                                     |
| Brotli    ## 1.9                                     |
+------------------------------------------------------+
```

### Compression Ratio

On mixed-pattern 1 MB data:

| Codec | Compressed Size | Ratio |
|-------|-----------------|-------|
| Brotli (best) | 535 bytes | 99.9% |
| Zstd | 684 bytes | 99.9% |
| Gzip | 4,382 bytes | 99.6% |
| LZ4 Block | 4,541 bytes | 99.5% |
| LZ4 Frame | 7,057 bytes | 99.3% |
| Snappy | 47,468 bytes | 95.3% |

## Feature Matrix

| Feature | Zstd | LZ4 Frame | LZ4 Block | Snappy | Gzip | Brotli | Zlib |
|---------|------|-----------|-----------|--------|------|--------|------|
| Streaming | Yes | Yes | No | No | Yes | Yes | Yes |
| Dictionary | Yes | No | No | No | No | No | Yes |
| Checksum | Yes | Yes | No | No | Yes | No | Yes |
| Auto-detect | Yes | Yes | No | Yes | Yes | No | Yes |
| Zero-copy | No | Yes | Yes | Yes | No | No | No |
| Pure Zig | No | Yes | Yes | Yes | No | No | No |

## Implementation Details

| Codec | Source | Version | License |
|-------|--------|---------|---------|
| Zstd | Vendored C | 1.5.7 | BSD |
| Gzip/Zlib | Vendored C (zlib) | 1.3.1 | zlib |
| Brotli | Vendored C | Latest | MIT |
| LZ4 | Pure Zig | - | Apache 2.0 |
| Snappy | Pure Zig | - | Apache 2.0 |

## Choosing a Codec

### Quick Decision

- **Default choice:** Zstd
- **Maximum speed:** LZ4 Block
- **Web compatibility:** Gzip or Brotli
- **Real-time messaging:** Snappy

### Decision Tree

```
+- Need maximum speed?
|  +- Yes -> LZ4 Block (if you track size) or Snappy
|  +- No -+
|         |
+- Need web compatibility?
|  +- Static assets -> Brotli
|  +- Dynamic content -> Gzip
|  +- No -+
|         |
+- Need streaming?
|  +- Fast + checksum -> LZ4 Frame
|  +- Best ratio -> Zstd
|  +- No -+
|         |
+- Default -> Zstd (best overall)
```

See [Choosing a Codec](/getting-started/choosing-a-codec/) for detailed guidance.

## Codec Deep Dives

Learn more about each codec:

- [Zstandard (Zstd)](/codecs/zstd/) — Best overall balance
- [LZ4](/codecs/lz4/) — Maximum speed
- [Snappy](/codecs/snappy/) — Real-time applications
- [Gzip](/codecs/gzip/) — Universal compatibility
- [Brotli](/codecs/brotli/) — Maximum compression
- [Zlib & Deflate](/codecs/zlib/) — Legacy formats

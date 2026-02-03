---
title: Options Reference
description: Complete reference for compression and decompression options.
---

This page documents all configuration options available in compressionz. Each codec has its own options struct tailored to its supported features.

## Compression Levels

All codecs that support compression levels use the same enum:

```zig
pub const Level = enum {
    fastest,  // Maximum speed, lower ratio
    fast,     // Good speed, good ratio
    default,  // Balanced (recommended)
    better,   // Better ratio, slower
    best,     // Maximum ratio, slowest
};
```

### Usage

```zig
const fast = try cz.zstd.compress(data, allocator, .{
    .level = .fast,
});

const best = try cz.zstd.compress(data, allocator, .{
    .level = .best,
});
```

### Performance by Level (Zstd)

| Level | Compress | Decompress | Ratio |
|-------|----------|------------|-------|
| `fastest` | 12+ GB/s | 11+ GB/s | 99.8% |
| `fast` | 12 GB/s | 11+ GB/s | 99.9% |
| `default` | 12 GB/s | 11+ GB/s | 99.9% |
| `better` | 5 GB/s | 11+ GB/s | 99.9% |
| `best` | 1.3 GB/s | 12 GB/s | 99.9% |

---

## Zstd Options

### CompressOptions

```zig
pub const CompressOptions = struct {
    level: Level = .default,
};
```

### DecompressOptions

```zig
pub const DecompressOptions = struct {
    max_output_size: ?usize = null,
};
```

### Dictionary Usage

```zig
// Compress with dictionary
const compressed = try cz.zstd.compressWithDict(data, dictionary, allocator, .{
    .level = .default,
});

// Decompress with dictionary
const decompressed = try cz.zstd.decompressWithDict(compressed, dictionary, allocator, .{
    .max_output_size = 100 * 1024 * 1024,
});
```

---

## LZ4 Frame Options

### CompressOptions

```zig
pub const CompressOptions = struct {
    /// Compression level
    level: Level = .default,

    /// Include XXH32 checksum of content
    content_checksum: bool = true,

    /// Include XXH32 checksum per block
    block_checksum: bool = false,

    /// Include original size in header
    content_size: ?usize = null,

    /// Maximum block size
    block_size: BlockSize = .max64KB,

    /// Blocks don't reference previous blocks
    independent_blocks: bool = false,
};

pub const BlockSize = enum {
    max64KB,
    max256KB,
    max1MB,
    max4MB,
};
```

**content_checksum**: When enabled (default), a XXH32 checksum of the original content is appended. This detects corruption but adds slight overhead.

**content_size**: When provided, the original size is stored in the frame header. This allows the decompressor to allocate the exact buffer size needed.

### DecompressOptions

```zig
pub const DecompressOptions = struct {
    max_output_size: ?usize = null,
};
```

---

## LZ4 Block Options

LZ4 block format has no compression options:

```zig
const compressed = try cz.lz4.block.compress(data, allocator);
```

For decompression, you **must** provide the original size:

```zig
const decompressed = try cz.lz4.block.decompressWithSize(compressed, original_len, allocator);
```

---

## Snappy Options

Snappy has no options for compression or decompression:

```zig
const compressed = try cz.snappy.compress(data, allocator);
const decompressed = try cz.snappy.decompress(compressed, allocator);
```

For size-limited decompression:

```zig
const decompressed = try cz.snappy.decompressWithLimit(compressed, allocator, max_size);
```

---

## Gzip Options

### CompressOptions

```zig
pub const CompressOptions = struct {
    level: Level = .default,
};
```

### DecompressOptions

```zig
pub const DecompressOptions = struct {
    max_output_size: ?usize = null,
};
```

---

## Zlib Options

### CompressOptions

```zig
pub const CompressOptions = struct {
    level: Level = .default,
};
```

### DecompressOptions

```zig
pub const DecompressOptions = struct {
    max_output_size: ?usize = null,
};
```

### Dictionary Usage

```zig
// Compress with dictionary
const compressed = try cz.zlib.compressWithDict(data, dictionary, allocator, .{});

// Decompress with dictionary
const decompressed = try cz.zlib.decompressWithDict(compressed, dictionary, allocator, .{});
```

### Raw Deflate

For raw deflate without zlib wrapper:

```zig
const compressed = try cz.zlib.compressDeflate(data, allocator, .{});
const decompressed = try cz.zlib.decompressDeflate(compressed, allocator, .{});
```

---

## Brotli Options

### CompressOptions

```zig
pub const CompressOptions = struct {
    level: Level = .default,
};
```

**Note**: Brotli's `best` level is significantly slower than other levels (86 MB/s vs 1.3 GB/s). Only use for static content.

### DecompressOptions

```zig
pub const DecompressOptions = struct {
    max_output_size: ?usize = null,
};
```

---

## Default Values Summary

| Codec | Default Level | Default Checksum |
|-------|---------------|------------------|
| Zstd | `.default` | Yes (built-in) |
| LZ4 Frame | `.default` | Yes (content) |
| LZ4 Block | N/A | No |
| Snappy | N/A | No |
| Gzip | `.default` | Yes (CRC32) |
| Zlib | `.default` | Yes (Adler-32) |
| Brotli | `.default` | No |

---

## Streaming Options

Streaming compressors use the same options as one-shot compression:

```zig
// Gzip streaming with options
var comp = try cz.gzip.Compressor(@TypeOf(writer)).init(allocator, writer, .{
    .level = .best,
});

// LZ4 frame streaming with options
var comp = try cz.lz4.frame.Compressor(@TypeOf(writer)).init(allocator, writer, .{
    .level = .fast,
    .content_checksum = true,
});

// Zstd streaming with options
var comp = try cz.zstd.Compressor(@TypeOf(writer)).init(allocator, writer, .{
    .level = .default,
});
```

---

## Feature Support by Codec

| Feature | Zstd | LZ4 Frame | LZ4 Block | Snappy | Gzip | Zlib | Brotli |
|---------|------|-----------|-----------|--------|------|------|--------|
| Levels | Yes | Yes | No | No | Yes | Yes | Yes |
| Checksum | Built-in | Optional | No | No | CRC32 | Adler-32 | No |
| Dictionary | Yes | No | No | No | No | Yes | No |
| Size in header | Auto | Optional | No | Yes | Mod 2^32 | No | No |
| Max output size | Yes | Yes | No | Yes | Yes | Yes | Yes |

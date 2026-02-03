---
title: Compression API
description: Complete reference for compression functions.
---

This page documents all compression-related functions in compressionz. Each codec has its own module with tailored APIs.

## Codec-Specific Compression

### Zstd

```zig
const cz = @import("compressionz");

// Basic compression
const compressed = try cz.zstd.compress(data, allocator, .{});
defer allocator.free(compressed);

// With options
const compressed = try cz.zstd.compress(data, allocator, .{
    .level = .best,
});

// With dictionary
const compressed = try cz.zstd.compressWithDict(data, dict, allocator, .{});
```

#### CompressOptions

```zig
pub const CompressOptions = struct {
    /// Compression level
    level: Level = .default,
};
```

### LZ4 Frame

```zig
const cz = @import("compressionz");

// Basic compression
const compressed = try cz.lz4.frame.compress(data, allocator, .{});
defer allocator.free(compressed);

// With options
const compressed = try cz.lz4.frame.compress(data, allocator, .{
    .level = .fast,
    .content_checksum = true,
    .block_checksum = false,
    .content_size = data.len,
    .block_size = .max64KB,
});
```

#### CompressOptions

```zig
pub const CompressOptions = struct {
    level: Level = .default,
    content_checksum: bool = true,
    block_checksum: bool = false,
    content_size: ?usize = null,
    block_size: BlockSize = .max64KB,
    independent_blocks: bool = false,
};
```

### LZ4 Block

```zig
const cz = @import("compressionz");

// No options - raw block format
const compressed = try cz.lz4.block.compress(data, allocator);
defer allocator.free(compressed);
```

LZ4 block format has no options and requires you to track the original size for decompression.

### Snappy

```zig
const cz = @import("compressionz");

// No options - simple API
const compressed = try cz.snappy.compress(data, allocator);
defer allocator.free(compressed);
```

Snappy has no compression options.

### Gzip

```zig
const cz = @import("compressionz");

// Basic compression
const compressed = try cz.gzip.compress(data, allocator, .{});
defer allocator.free(compressed);

// With level
const compressed = try cz.gzip.compress(data, allocator, .{
    .level = .best,
});
```

#### CompressOptions

```zig
pub const CompressOptions = struct {
    level: Level = .default,
};
```

### Zlib

```zig
const cz = @import("compressionz");

// Zlib format (with header/trailer)
const compressed = try cz.zlib.compress(data, allocator, .{});
defer allocator.free(compressed);

// Raw Deflate (no header/trailer)
const deflate = try cz.zlib.compressDeflate(data, allocator, .{});
defer allocator.free(deflate);

// With dictionary
const compressed = try cz.zlib.compressWithDict(data, dict, allocator, .{});
```

#### CompressOptions

```zig
pub const CompressOptions = struct {
    level: Level = .default,
};
```

### Brotli

```zig
const cz = @import("compressionz");

// Basic compression
const compressed = try cz.brotli.compress(data, allocator, .{});
defer allocator.free(compressed);

// With level
const compressed = try cz.brotli.compress(data, allocator, .{
    .level = .best,
});
```

#### CompressOptions

```zig
pub const CompressOptions = struct {
    level: Level = .best,
};
```

---

## Compression Levels

All codecs that support levels use the same enum:

```zig
pub const Level = enum {
    fastest,  // Maximum speed, lower ratio
    fast,     // Good speed, good ratio
    default,  // Balanced (recommended)
    better,   // Better ratio, slower
    best,     // Maximum ratio, slowest
};
```

### Level Comparison (Zstd, 1 MB data)

| Level | Compress | Decompress | Ratio |
|-------|----------|------------|-------|
| `fastest` | 12+ GB/s | 11+ GB/s | 99.8% |
| `fast` | 12 GB/s | 11+ GB/s | 99.9% |
| `default` | 12 GB/s | 11+ GB/s | 99.9% |
| `better` | 5 GB/s | 11+ GB/s | 99.9% |
| `best` | 1.3 GB/s | 12 GB/s | 99.9% |

### Recommendations

- Use `default` for most cases
- Use `fast` for real-time applications
- Use `best` only for archival or static content

---

## Zero-Copy Compression

Some codecs support compressing into pre-allocated buffers:

### LZ4 Block

```zig
var buffer: [65536]u8 = undefined;
const compressed = try cz.lz4.block.compressInto(data, &buffer);
```

### LZ4 Frame

```zig
var buffer: [65536]u8 = undefined;
const compressed = try cz.lz4.frame.compressInto(data, &buffer, .{});
```

### Snappy

```zig
var buffer: [65536]u8 = undefined;
const compressed = try cz.snappy.compressInto(data, &buffer);
```

### Calculating Buffer Size

```zig
// LZ4
const max_size = cz.lz4.block.maxCompressedSize(data.len);
const max_frame = cz.lz4.frame.maxCompressedSize(data.len);

// Snappy
const max_snappy = cz.snappy.maxCompressedSize(data.len);
```

---

## Streaming Compression

For large data, use streaming APIs:

### Gzip

```zig
var comp = try cz.gzip.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();

try comp.writer().writeAll(data);
try comp.finish();  // MUST call to finalize
```

### Zstd

```zig
var comp = try cz.zstd.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();

try comp.writer().writeAll(data);
try comp.finish();
```

### LZ4 Frame

```zig
var comp = try cz.lz4.frame.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();

try comp.writer().writeAll(data);
try comp.finish();
```

### Brotli

```zig
var comp = try cz.brotli.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();

try comp.writer().writeAll(data);
try comp.finish();
```

### Zlib

```zig
// Zlib format
var comp = try cz.zlib.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();

try comp.writer().writeAll(data);
try comp.finish();

// Raw Deflate
var comp = try cz.zlib.DeflateCompressor(@TypeOf(writer)).init(allocator, writer, .{});
```

---

## Dictionary Compression

Dictionaries improve compression for small data with known patterns.

### Zstd with Dictionary

```zig
const dictionary = @embedFile("my_dictionary.bin");

// Compress
const compressed = try cz.zstd.compressWithDict(data, dictionary, allocator, .{});
defer allocator.free(compressed);

// Decompress (must use same dictionary)
const decompressed = try cz.zstd.decompressWithDict(compressed, dictionary, allocator, .{});
defer allocator.free(decompressed);
```

### Zlib with Dictionary

```zig
const dictionary = "common patterns...";

const compressed = try cz.zlib.compressWithDict(data, dictionary, allocator, .{});
const decompressed = try cz.zlib.decompressWithDict(compressed, dictionary, allocator, .{});
```

---

## Error Handling

All compression functions return the same error set:

```zig
pub const Error = error{
    OutOfMemory,
    InvalidData,
    OutputTooSmall,
    UnsupportedFeature,
};
```

Example:

```zig
const compressed = cz.zstd.compress(data, allocator, .{}) catch |err| switch (err) {
    error.OutOfMemory => {
        std.debug.print("Failed to allocate memory\n", .{});
        return err;
    },
    else => return err,
};
```

---

## Feature Support Matrix

| Codec | One-shot | Streaming | Zero-copy | Dictionary |
|-------|----------|-----------|-----------|------------|
| `zstd` | Yes | Yes | No | Yes |
| `lz4.frame` | Yes | Yes | Yes | No |
| `lz4.block` | Yes | No | Yes | No |
| `snappy` | Yes | No | Yes | No |
| `gzip` | Yes | Yes | No | No |
| `zlib` | Yes | Yes | No | Yes |
| `brotli` | Yes | Yes | No | No |

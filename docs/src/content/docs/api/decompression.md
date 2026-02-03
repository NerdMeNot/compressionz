---
title: Decompression API
description: Complete reference for decompression functions.
---

This page documents all decompression-related functions in compressionz. Each codec has its own module with tailored APIs.

## Codec-Specific Decompression

### Zstd

```zig
const cz = @import("compressionz");

// Basic decompression
const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);

// With size limit (security)
const decompressed = try cz.zstd.decompress(compressed, allocator, .{
    .max_output_size = 100 * 1024 * 1024,  // 100 MB limit
});

// With dictionary
const decompressed = try cz.zstd.decompressWithDict(compressed, dictionary, allocator, .{});
```

#### DecompressOptions

```zig
pub const DecompressOptions = struct {
    /// Maximum output size (decompression bomb protection)
    max_output_size: ?usize = null,
};
```

### LZ4 Frame

```zig
const cz = @import("compressionz");

// Basic decompression
const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);

// With size limit
const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{
    .max_output_size = 100 * 1024 * 1024,
});
```

### LZ4 Block

LZ4 block format **requires** the original size for decompression:

```zig
const cz = @import("compressionz");

// Compression
const compressed = try cz.lz4.block.compress(data, allocator);
const original_len = data.len;  // Save this!
defer allocator.free(compressed);

// Decompression - REQUIRES original size
const decompressed = try cz.lz4.block.decompressWithSize(compressed, original_len, allocator);
defer allocator.free(decompressed);
```

### Snappy

```zig
const cz = @import("compressionz");

// No options - simple API
const decompressed = try cz.snappy.decompress(compressed, allocator);
defer allocator.free(decompressed);

// With size limit
const decompressed = try cz.snappy.decompressWithLimit(compressed, allocator, max_size);
```

### Gzip

```zig
const cz = @import("compressionz");

// Basic decompression
const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);

// With size limit
const decompressed = try cz.gzip.decompress(compressed, allocator, .{
    .max_output_size = 100 * 1024 * 1024,
});
```

### Zlib

```zig
const cz = @import("compressionz");

// Zlib format
const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);

// Raw Deflate
const decompressed = try cz.zlib.decompressDeflate(compressed, allocator, .{});

// With dictionary
const decompressed = try cz.zlib.decompressWithDict(compressed, dictionary, allocator, .{});
```

### Brotli

```zig
const cz = @import("compressionz");

// Basic decompression
const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);

// With size limit
const decompressed = try cz.brotli.decompress(compressed, allocator, .{
    .max_output_size = 100 * 1024 * 1024,
});
```

---

## Decompression Bomb Protection

Malicious compressed data can expand to enormous sizes (e.g., a 1 KB "zip bomb" expanding to 1 TB). Use `max_output_size` to protect against this:

```zig
const safe = cz.gzip.decompress(untrusted_data, allocator, .{
    .max_output_size = 100 * 1024 * 1024,  // 100 MB limit
}) catch |err| switch (err) {
    error.OutputTooLarge => {
        // Data would exceed limit
        return error.SuspiciousInput;
    },
    else => return err,
};
```

### Recommended Limits

| Context | Recommended Limit |
|---------|-------------------|
| User uploads | 10-100 MB |
| API requests | 1-10 MB |
| Config files | 1 MB |
| Internal data | Based on expected size |

---

## Zero-Copy Decompression

Some codecs support decompressing into pre-allocated buffers:

### LZ4 Block

```zig
var buffer: [1024 * 1024]u8 = undefined;  // 1 MB buffer
const decompressed = try cz.lz4.block.decompressInto(compressed, &buffer);
```

### LZ4 Frame

```zig
var buffer: [1024 * 1024]u8 = undefined;
const decompressed = try cz.lz4.frame.decompressInto(compressed, &buffer);
```

### Snappy

```zig
var buffer: [1024 * 1024]u8 = undefined;
const decompressed = try cz.snappy.decompressInto(compressed, &buffer);
```

---

## Streaming Decompression

For large data, use streaming APIs:

### Gzip

```zig
var decomp = try cz.gzip.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();

const data = try decomp.reader().readAllAlloc(allocator, max_size);
```

### Zstd

```zig
var decomp = try cz.zstd.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();

const data = try decomp.reader().readAllAlloc(allocator, max_size);
```

### LZ4 Frame

```zig
var decomp = try cz.lz4.frame.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();

const data = try decomp.reader().readAllAlloc(allocator, max_size);
```

### Brotli

```zig
var decomp = try cz.brotli.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();

const data = try decomp.reader().readAllAlloc(allocator, max_size);
```

### Zlib

```zig
// Zlib format
var decomp = try cz.zlib.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();

// Raw Deflate
var decomp = try cz.zlib.DeflateDecompressor(@TypeOf(reader)).init(allocator, reader);
```

---

## Auto-Detection

Automatically detect and decompress:

```zig
const cz = @import("compressionz");

pub fn decompressAuto(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const format = cz.detect(data);
    switch (format) {
        .zstd => return cz.zstd.decompress(data, allocator, .{}),
        .gzip => return cz.gzip.decompress(data, allocator, .{}),
        .lz4 => return cz.lz4.frame.decompress(data, allocator, .{}),
        .zlib => return cz.zlib.decompress(data, allocator, .{}),
        .snappy => return cz.snappy.decompress(data, allocator),
        .unknown => return error.UnknownFormat,
    }
}
```

See [Codec Detection](/advanced/detection/) for details.

---

## Error Handling

Common decompression errors:

```zig
const result = cz.zstd.decompress(data, allocator, .{}) catch |err| switch (err) {
    error.InvalidData => {
        // Corrupted or not actually compressed with this codec
    },
    error.ChecksumMismatch => {
        // Data integrity check failed
    },
    error.OutputTooLarge => {
        // Exceeds max_output_size limit
    },
    error.UnexpectedEof => {
        // Compressed data truncated
    },
    error.OutOfMemory => {
        // Allocation failed
    },
    else => return err,
};
```

See [Error Handling](/api/errors/) for complete error reference.

---

## Feature Support Matrix

| Codec | One-shot | Streaming | Zero-copy | Dictionary | Requires Size |
|-------|----------|-----------|-----------|------------|---------------|
| `zstd` | Yes | Yes | No | Yes | No |
| `lz4.frame` | Yes | Yes | Yes | No | No |
| `lz4.block` | Yes | No | Yes | No | **Yes** |
| `snappy` | Yes | No | Yes | No | No |
| `gzip` | Yes | Yes | No | No | No |
| `zlib` | Yes | Yes | No | Yes | No |
| `brotli` | Yes | Yes | No | No | No |

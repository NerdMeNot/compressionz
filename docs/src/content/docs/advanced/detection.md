---
title: Codec Detection
description: Automatically detect compression formats from magic bytes.
---

compressionz can automatically detect compression formats by examining the first few bytes of data. This enables handling unknown compressed data without prior knowledge of the format.

## Basic Detection

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

## cz.detect()

```zig
pub fn detect(data: []const u8) Format
```

Returns the detected format.

### Format Enum

```zig
pub const Format = enum {
    zstd,
    gzip,
    lz4,
    zlib,
    snappy,
    unknown,
};
```

### Detection Support

| Format | Detectable | Magic Bytes |
|--------|------------|-------------|
| LZ4 Frame | Yes | `0x04 0x22 0x4D 0x18` |
| Zstd | Yes | `0x28 0xB5 0x2F 0xFD` |
| Gzip | Yes | `0x1F 0x8B` |
| Zlib | Yes | CMF/FLG check |
| Snappy | Yes | `sNaPpY` |
| LZ4 Block | No | No magic |
| Brotli | No | No magic |
| Deflate | No | No magic |

## Magic Bytes Reference

### LZ4 Frame

```
Bytes 0-3: 0x04 0x22 0x4D 0x18 (little-endian 0x184D2204)
```

```zig
if (data.len >= 4 and
    data[0] == 0x04 and data[1] == 0x22 and
    data[2] == 0x4D and data[3] == 0x18)
{
    // LZ4 Frame
}
```

### Zstd

```
Bytes 0-3: 0x28 0xB5 0x2F 0xFD (little-endian 0xFD2FB528)
```

```zig
if (data.len >= 4 and
    data[0] == 0x28 and data[1] == 0xB5 and
    data[2] == 0x2F and data[3] == 0xFD)
{
    // Zstd
}
```

### Gzip

```
Bytes 0-1: 0x1F 0x8B
Byte 2: Compression method (0x08 = deflate)
```

```zig
if (data.len >= 2 and data[0] == 0x1F and data[1] == 0x8B) {
    // Gzip
}
```

### Zlib

Zlib uses a checksum-based detection:

```
Byte 0 (CMF): Compression method (low 4 bits = 8 for deflate)
Byte 1 (FLG): Flags
Check: (CMF * 256 + FLG) % 31 == 0
```

```zig
if (data.len >= 2) {
    const cmf = data[0];
    const flg = data[1];
    if ((cmf & 0x0F) == 8 and
        (@as(u16, cmf) * 256 + flg) % 31 == 0)
    {
        // Zlib
    }
}
```

### Snappy (Framed)

```
Bytes 0-5: "sNaPpY" (stream identifier)
```

```zig
if (data.len >= 6 and std.mem.eql(u8, data[0..6], "sNaPpY")) {
    // Snappy framed format
}
```

## Use Cases

### Generic Decompressor

```zig
const cz = @import("compressionz");
const std = @import("std");

pub fn decompress(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const format = cz.detect(data);
    switch (format) {
        .zstd => return cz.zstd.decompress(data, allocator, .{}),
        .gzip => return cz.gzip.decompress(data, allocator, .{}),
        .lz4 => return cz.lz4.frame.decompress(data, allocator, .{}),
        .zlib => return cz.zlib.decompress(data, allocator, .{}),
        .snappy => return cz.snappy.decompress(data, allocator),
        .unknown => {
            // Might be uncompressed or undetectable format
            return error.UnknownFormat;
        },
    }
}
```

### File Handler

```zig
pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024);
    errdefer allocator.free(data);

    // Try to decompress if compressed
    const format = cz.detect(data);
    if (format != .unknown) {
        const decompressed = switch (format) {
            .zstd => try cz.zstd.decompress(data, allocator, .{}),
            .gzip => try cz.gzip.decompress(data, allocator, .{}),
            .lz4 => try cz.lz4.frame.decompress(data, allocator, .{}),
            .zlib => try cz.zlib.decompress(data, allocator, .{}),
            .snappy => try cz.snappy.decompress(data, allocator),
            .unknown => unreachable,
        };
        allocator.free(data);
        return decompressed;
    }

    // Return as-is if not compressed
    return data;
}
```

### Multi-Format API

```zig
const cz = @import("compressionz");

pub const ContentEncoding = enum {
    none,
    gzip,
    zstd,
    br,  // Brotli

    pub fn fromHeader(header: ?[]const u8) ContentEncoding {
        const value = header orelse return .none;
        if (std.mem.indexOf(u8, value, "zstd") != null) return .zstd;
        if (std.mem.indexOf(u8, value, "br") != null) return .br;
        if (std.mem.indexOf(u8, value, "gzip") != null) return .gzip;
        return .none;
    }
};

pub fn decodeResponse(encoding: ContentEncoding, body: []const u8, allocator: std.mem.Allocator) ![]u8 {
    switch (encoding) {
        .gzip => return cz.gzip.decompress(body, allocator, .{}),
        .zstd => return cz.zstd.decompress(body, allocator, .{}),
        .br => return cz.brotli.decompress(body, allocator, .{}),
        .none => {
            // Auto-detect as fallback
            const format = cz.detect(body);
            switch (format) {
                .zstd => return cz.zstd.decompress(body, allocator, .{}),
                .gzip => return cz.gzip.decompress(body, allocator, .{}),
                .lz4 => return cz.lz4.frame.decompress(body, allocator, .{}),
                .zlib => return cz.zlib.decompress(body, allocator, .{}),
                .snappy => return cz.snappy.decompress(body, allocator),
                .unknown => return allocator.dupe(u8, body),
            }
        },
    }
}
```

## Handling Undetectable Formats

For formats without magic bytes, use context or file extensions:

### By Extension

```zig
pub fn formatFromExtension(path: []const u8) ?cz.Format {
    const ext = std.fs.path.extension(path);

    if (std.mem.eql(u8, ext, ".gz")) return .gzip;
    if (std.mem.eql(u8, ext, ".zst")) return .zstd;
    if (std.mem.eql(u8, ext, ".lz4")) return .lz4;
    if (std.mem.eql(u8, ext, ".snappy")) return .snappy;
    if (std.mem.eql(u8, ext, ".zz")) return .zlib;

    return null;
}

// Brotli and Deflate need extension since they have no magic
pub fn isBrotliByExtension(path: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.extension(path), ".br");
}
```

### By Content-Type

```zig
pub fn codecFromContentType(content_type: []const u8) enum { gzip, zstd, brotli, none } {
    if (std.mem.indexOf(u8, content_type, "gzip") != null) return .gzip;
    if (std.mem.indexOf(u8, content_type, "zstd") != null) return .zstd;
    if (std.mem.indexOf(u8, content_type, "br") != null) return .brotli;
    return .none;
}
```

## Error Handling

```zig
const result = blk: {
    const format = cz.detect(data);
    if (format == .unknown) {
        // Unknown format - might be:
        // 1. Uncompressed data
        // 2. Brotli or Deflate (no magic)
        // 3. Corrupted data

        // Try common undetectable formats
        if (tryBrotli(data, allocator)) |d| break :blk d;
        if (tryDeflate(data, allocator)) |d| break :blk d;

        return error.UnknownFormat;
    }

    break :blk switch (format) {
        .zstd => try cz.zstd.decompress(data, allocator, .{}),
        .gzip => try cz.gzip.decompress(data, allocator, .{}),
        .lz4 => try cz.lz4.frame.decompress(data, allocator, .{}),
        .zlib => try cz.zlib.decompress(data, allocator, .{}),
        .snappy => try cz.snappy.decompress(data, allocator),
        .unknown => unreachable,
    };
};

fn tryBrotli(data: []const u8, allocator: std.mem.Allocator) ?[]u8 {
    return cz.brotli.decompress(data, allocator, .{}) catch null;
}

fn tryDeflate(data: []const u8, allocator: std.mem.Allocator) ?[]u8 {
    return cz.zlib.decompressDeflate(data, allocator, .{}) catch null;
}
```

## Performance Note

Detection is O(1) — it only examines the first few bytes:

```zig
// Detection is essentially free
const format = cz.detect(gigabyte_of_data);  // Instant
```

Always safe to call on any data, regardless of size.

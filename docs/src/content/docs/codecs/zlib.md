---
title: Zlib & Deflate
description: Deep dive into Zlib and Deflate compression codecs.
---

Zlib and Deflate are closely related formats based on the DEFLATE algorithm. They're used extensively in PNG images, ZIP files, HTTP, and many other contexts.

## Format Comparison

| Format | Description | Checksum | Auto-detect |
|--------|-------------|----------|-------------|
| **Deflate** | Raw DEFLATE stream | None | No |
| **Zlib** | DEFLATE + zlib header/trailer | Adler-32 | Yes |
| **Gzip** | DEFLATE + gzip header/trailer | CRC32 | Yes |

All three use the same compression algorithm but different wrappers.

### Performance

| Format | Compress | Decompress | Ratio |
|--------|----------|------------|-------|
| Deflate | 2.4 GB/s | 2.4 GB/s | 99.2% |
| Zlib | 2.4 GB/s | 2.4 GB/s | 99.2% |

## When to Use Which

| Use Case | Format |
|----------|--------|
| PNG images | Zlib |
| ZIP files | Deflate (raw) |
| HTTP Content-Encoding | Gzip |
| Custom protocol | Deflate (minimal overhead) |
| Data integrity needed | Zlib (Adler-32) |
| General file compression | [Gzip](/codecs/gzip/) |

## Zlib

Zlib wraps DEFLATE with a small header and Adler-32 checksum.

### Basic Usage

```zig
const cz = @import("compressionz");

// Compress
const compressed = try cz.zlib.compress(data, allocator, .{});
defer allocator.free(compressed);

// Decompress
const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

### With Options

```zig
// Compression level
const best = try cz.zlib.compress(data, allocator, .{
    .level = .best,
});
```

### With Dictionary

```zig
const dictionary = "common patterns in your data...";

// Compress with dictionary
const compressed = try cz.zlib.compressWithDict(data, dictionary, allocator, .{});
defer allocator.free(compressed);

// Decompress with same dictionary
const decompressed = try cz.zlib.decompressWithDict(compressed, dictionary, allocator, .{});
defer allocator.free(decompressed);
```

### Format Structure

```
+-----------------------------------------------------+
| Zlib Header (2 bytes)                               |
|  - CMF: compression method and flags                |
|  - FLG: flags (check bits, preset dict, level)      |
|  - [Dictionary ID] (4 bytes, if FDICT set)          |
+-----------------------------------------------------+
| Compressed Data (DEFLATE)                           |
+-----------------------------------------------------+
| Adler-32 Checksum (4 bytes)                         |
+-----------------------------------------------------+
```

### Magic Bytes

```zig
// Zlib detection (CMF * 256 + FLG must be divisible by 31)
fn isZlib(data: []const u8) bool {
    if (data.len < 2) return false;
    const cmf = data[0];
    const flg = data[1];
    return (cmf & 0x0F) == 8 and  // DEFLATE method
           (@as(u16, cmf) * 256 + flg) % 31 == 0;
}
```

## Deflate (Raw)

Raw DEFLATE stream without any wrapper.

### Basic Usage

```zig
const cz = @import("compressionz");

// Compress
const compressed = try cz.zlib.compressDeflate(data, allocator, .{});
defer allocator.free(compressed);

// Decompress
const decompressed = try cz.zlib.decompressDeflate(compressed, allocator, .{});
defer allocator.free(decompressed);
```

### Format Structure

```
+-----------------------------------------------------+
| DEFLATE Blocks                                      |
|                                                     |
| Block Header (3 bits)                               |
|  - BFINAL: 1 if last block                          |
|  - BTYPE: block type (00=stored, 01=fixed, 10=dyn)  |
|                                                     |
| Block Data                                          |
|  - Huffman-coded literals and length/distance pairs |
|                                                     |
| ... more blocks ...                                 |
|                                                     |
| Final block (BFINAL=1)                              |
+-----------------------------------------------------+
```

## Dictionary Compression

Zlib and Deflate support dictionary compression for small data with known patterns.

### How It Works

The dictionary provides a "seed" of common patterns that the compressor can reference:

```zig
// Without dictionary: compressor builds patterns from scratch
// With dictionary: compressor starts with known patterns

const json_dict =
    \\{"id":,"name":,"email":,"created_at":,"updated_at":
    \\,"status":"active","status":"inactive","status":"pending"
    \\,"type":"user","type":"admin","type":"guest"
;

// Small JSON objects compress much better with dictionary
const compressed = try cz.zlib.compressWithDict(json_data, json_dict, allocator, .{});
```

### Dictionary Benefits

| Data Size | Without Dict | With Dict | Improvement |
|-----------|--------------|-----------|-------------|
| 100 bytes | 95 bytes | 45 bytes | 53% smaller |
| 500 bytes | 380 bytes | 210 bytes | 45% smaller |
| 1 KB | 720 bytes | 520 bytes | 28% smaller |
| 10 KB | 6.5 KB | 5.8 KB | 11% smaller |

Dictionary compression is most effective for small data with predictable patterns.

## Streaming

Both formats support streaming:

```zig
const cz = @import("compressionz");
const std = @import("std");

// Streaming compression (Zlib)
pub fn compressStream(allocator: std.mem.Allocator, input: anytype, output: anytype) !void {
    var comp = try cz.zlib.Compressor(@TypeOf(output)).init(allocator, output, .{});
    defer comp.deinit();

    var buf: [65536]u8 = undefined;
    while (true) {
        const n = try input.read(&buf);
        if (n == 0) break;
        try comp.writer().writeAll(buf[0..n]);
    }
    try comp.finish();
}

// Streaming decompression (Zlib)
pub fn decompressStream(allocator: std.mem.Allocator, input: anytype) ![]u8 {
    var decomp = try cz.zlib.Decompressor(@TypeOf(input)).init(allocator, input);
    defer decomp.deinit();
    return decomp.reader().readAllAlloc(allocator, 1024 * 1024 * 1024);
}

// Raw Deflate streaming
pub fn compressDeflateStream(allocator: std.mem.Allocator, output: anytype) !cz.zlib.DeflateCompressor(@TypeOf(output)) {
    return cz.zlib.DeflateCompressor(@TypeOf(output)).init(allocator, output, .{});
}
```

## Algorithm Details

### DEFLATE Algorithm

DEFLATE combines two compression techniques:

1. **LZ77** — Replace repeated sequences with (length, distance) pairs
2. **Huffman Coding** — Use shorter codes for more frequent symbols

```
Input:  "ABRACADABRA"

LZ77 output:
  A B R A C A D [match: length=4, distance=7] A
  (The "ABRA" at the end matches "ABRA" from 7 positions back)

Huffman coding:
  Assign short bit sequences to common symbols
  A=0, B=10, R=110, C=1110, D=11110, etc.
```

### Block Types

| Type | Name | Use Case |
|------|------|----------|
| 00 | Stored | Incompressible data (passed through) |
| 01 | Fixed | Pre-defined Huffman codes |
| 10 | Dynamic | Custom Huffman codes per block |

## Use Cases

### PNG Images

PNG uses Zlib internally:

```zig
// PNG file structure (simplified)
// IHDR chunk (image header)
// IDAT chunk (zlib-compressed image data)  <-- Zlib here
// IEND chunk (end marker)
```

### ZIP Files

ZIP uses raw Deflate:

```zig
// ZIP local file header
// Deflate-compressed file data  <-- Raw Deflate here
// Data descriptor (optional)
```

### Custom Protocols

For minimal overhead, use raw Deflate:

```zig
fn sendCompressed(socket: *Socket, data: []const u8, allocator: Allocator) !void {
    // 4-byte size prefix + deflate data (no zlib overhead)
    const compressed = try cz.zlib.compressDeflate(data, allocator, .{});
    defer allocator.free(compressed);

    var header: [4]u8 = undefined;
    std.mem.writeInt(u32, &header, @intCast(compressed.len), .little);

    try socket.writeAll(&header);
    try socket.writeAll(compressed);
}
```

## Comparison

| Aspect | Deflate | Zlib | Gzip |
|--------|---------|------|------|
| Overhead | 0 bytes | 6 bytes | 18+ bytes |
| Checksum | None | Adler-32 | CRC32 |
| Dictionary | Yes | Yes | No |
| Auto-detect | No | Yes | Yes |
| Use case | Embedding | Libraries | Files |

## Resources

- [RFC 1950 - ZLIB Format](https://datatracker.ietf.org/doc/html/rfc1950)
- [RFC 1951 - DEFLATE](https://datatracker.ietf.org/doc/html/rfc1951)
- [zlib Home Page](https://zlib.net/)
- [Mark Adler's zlib FAQ](https://zlib.net/zlib_faq.html)

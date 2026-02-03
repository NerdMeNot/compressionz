---
title: Gzip
description: Deep dive into the Gzip compression codec.
---

Gzip is the most widely supported compression format, used everywhere from HTTP to file archives. It provides good compression with universal compatibility.

## At a Glance

| Property | Value |
|----------|-------|
| **Standard** | RFC 1952 |
| **First Release** | 1992 |
| **Implementation** | Vendored zlib 1.3.1 |
| **License** | zlib |

### Performance

| Level | Compress | Decompress | Ratio |
|-------|----------|------------|-------|
| fast | 2.4 GB/s | 2.4 GB/s | 99.2% |
| default | 723 MB/s | 2.8 GB/s | 99.6% |
| best | 691 MB/s | 2.9 GB/s | 99.6% |

### Features

- Universal compatibility
- Streaming support
- CRC32 checksum
- Auto-detection (magic bytes)
- Multiple compression levels
- No dictionary support

## Basic Usage

```zig
const cz = @import("compressionz");

// Compress
const compressed = try cz.gzip.compress(data, allocator, .{});
defer allocator.free(compressed);

// Decompress
const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

## Compression Levels

```zig
// Fast compression (2.4 GB/s)
const fast = try cz.gzip.compress(data, allocator, .{
    .level = .fast,
});

// Default (balanced)
const default = try cz.gzip.compress(data, allocator, .{
    .level = .default,
});

// Best compression
const best = try cz.gzip.compress(data, allocator, .{
    .level = .best,
});
```

### Level Comparison

| Level | Speed | Ratio | Use Case |
|-------|-------|-------|----------|
| `fastest` | Fastest | Lower | Real-time HTTP |
| `fast` | Fast | Good | Dynamic content |
| `default` | Moderate | Better | **General use** |
| `better` | Slower | Better | Pre-compression |
| `best` | Slowest | Best | Static files |

## Streaming

Gzip excels at streaming large files:

### Streaming Compression

```zig
const cz = @import("compressionz");
const std = @import("std");

pub fn compressFile(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) !void {
    const input = try std.fs.cwd().openFile(input_path, .{});
    defer input.close();

    const output = try std.fs.cwd().createFile(output_path, .{});
    defer output.close();

    var comp = try cz.gzip.Compressor(@TypeOf(output.writer())).init(allocator, output.writer(), .{
        .level = .default,
    });
    defer comp.deinit();

    var buf: [65536]u8 = undefined;
    while (true) {
        const n = try input.read(&buf);
        if (n == 0) break;
        try comp.writer().writeAll(buf[0..n]);
    }

    try comp.finish();
}
```

### Streaming Decompression

```zig
pub fn decompressFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var decomp = try cz.gzip.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
    defer decomp.deinit();

    return decomp.reader().readAllAlloc(allocator, 1024 * 1024 * 1024);
}
```

## Decompression Safety

Protect against decompression bombs:

```zig
const safe = try cz.gzip.decompress(untrusted_data, allocator, .{
    .max_output_size = 100 * 1024 * 1024,  // 100 MB limit
});
```

## Format Details

### Gzip Structure

```
+-----------------------------------------------------+
| Header (10+ bytes)                                  |
|  - Magic: 0x1f 0x8b                                 |
|  - Compression method: 0x08 (deflate)               |
|  - Flags (1 byte)                                   |
|  - Modification time (4 bytes)                      |
|  - Extra flags (1 byte)                             |
|  - OS (1 byte)                                      |
|  - [Extra field] (if FEXTRA)                        |
|  - [Original filename] (if FNAME)                   |
|  - [Comment] (if FCOMMENT)                          |
|  - [CRC16] (if FHCRC)                               |
+-----------------------------------------------------+
| Compressed Data (deflate)                           |
+-----------------------------------------------------+
| Trailer (8 bytes)                                   |
|  - CRC32 of uncompressed data (4 bytes)             |
|  - Original size mod 2^32 (4 bytes)                 |
+-----------------------------------------------------+
```

### Magic Bytes

```zig
// Gzip magic number
const GZIP_MAGIC: [2]u8 = .{ 0x1f, 0x8b };

// Detection
if (data.len >= 2 and data[0] == 0x1f and data[1] == 0x8b) {
    // It's Gzip
}
```

## Algorithm Details

Gzip uses **DEFLATE** compression:

1. **LZ77** — Find repeated sequences, encode as (length, distance) pairs
2. **Huffman coding** — Variable-length codes for symbols
3. **Dynamic trees** — Optimal Huffman trees per block

### Why Gzip is Universal

- 30+ years of support
- Built into HTTP (Content-Encoding)
- Native OS support (Linux, macOS, Windows)
- Every programming language has a library
- Standard for `.gz` files

## Use Cases

### HTTP Compression

Gzip is the standard for HTTP content encoding:

```zig
pub fn handleRequest(allocator: Allocator, request: *Request, response: *Response) !void {
    const accept_encoding = request.headers.get("Accept-Encoding") orelse "";

    if (std.mem.indexOf(u8, accept_encoding, "gzip") != null) {
        const body = getResponseBody();
        const compressed = try cz.gzip.compress(body, allocator, .{});
        defer allocator.free(compressed);

        response.headers.set("Content-Encoding", "gzip");
        try response.send(compressed);
    } else {
        try response.send(getResponseBody());
    }
}
```

### File Compression

```zig
pub fn compressLogs(allocator: Allocator, log_dir: []const u8) !void {
    var dir = try std.fs.cwd().openDir(log_dir, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".log")) {
            const input_path = try std.fs.path.join(allocator, &.{ log_dir, entry.name });
            defer allocator.free(input_path);

            const output_path = try std.fmt.allocPrint(allocator, "{s}.gz", .{input_path});
            defer allocator.free(output_path);

            try compressFile(allocator, input_path, output_path);
        }
    }
}
```

## Gzip vs Alternatives

| Metric | Gzip | Zstd | Brotli |
|--------|------|------|--------|
| Compress | 2.4 GB/s | **12 GB/s** | 1.3 GB/s |
| Decompress | 2.4 GB/s | **11.6 GB/s** | 1.9 GB/s |
| Ratio | 99.2% | **99.9%** | **99.9%** |
| HTTP Support | **Universal** | Growing | Good |
| Browser Support | **100%** | Some | **~95%** |

### When to Use Gzip

**Use Gzip when:**
- Maximum compatibility needed
- HTTP Content-Encoding for all browsers
- Interoperating with Unix tools
- Working with `.gz` files

**Consider alternatives when:**
- Speed matters (use Zstd or LZ4)
- Static web assets (use Brotli)
- Best compression needed (use Zstd/Brotli)

## Memory Considerations

Gzip decompression requires a sliding window buffer:

| Context | Compression Memory | Decompression Memory |
|---------|-------------------|---------------------|
| Gzip | ~256 KB | ~32 KB |
| Per-stream | ~256 KB | ~32 KB |

For memory-constrained environments, be aware of the per-stream overhead.

## Error Handling

```zig
const result = cz.gzip.decompress(data, allocator, .{}) catch |err| switch (err) {
    error.InvalidData => {
        // Not valid gzip data, or corrupted
    },
    error.ChecksumMismatch => {
        // CRC32 verification failed
    },
    error.UnexpectedEof => {
        // Truncated gzip data
    },
    else => return err,
};
```

## Resources

- [RFC 1952 - GZIP File Format](https://datatracker.ietf.org/doc/html/rfc1952)
- [RFC 1951 - DEFLATE](https://datatracker.ietf.org/doc/html/rfc1951)
- [zlib Home Page](https://zlib.net/)

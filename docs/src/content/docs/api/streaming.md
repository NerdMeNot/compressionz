---
title: Streaming API
description: Process large data with Reader/Writer interfaces.
---

The streaming API allows processing data in chunks without loading everything into memory. This is essential for large files or when integrating with I/O systems.

## Streaming Interfaces

compressionz provides streaming wrappers that implement Zig's standard `Reader` and `Writer` interfaces:

- **Compressor** — Wraps a writer, compresses data written to it
- **Decompressor** — Wraps a reader, decompresses data read from it

### Supported Codecs

| Codec | Streaming Support |
|-------|-------------------|
| `gzip` | Yes |
| `zlib` | Yes |
| `zstd` | Yes |
| `brotli` | Yes |
| `lz4.frame` | Yes |
| `lz4.block` | No |
| `snappy` | No |

---

## Streaming Decompression

### Gzip

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn decompressFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // Open compressed file
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // Create decompressor
    var decomp = try cz.gzip.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
    defer decomp.deinit();

    // Read all decompressed data
    return decomp.reader().readAllAlloc(allocator, 100 * 1024 * 1024);
}
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
defer decomp.deinit();
```

### Example: Process in Chunks

```zig
pub fn processCompressedStream(allocator: std.mem.Allocator, source: anytype) !void {
    var decomp = try cz.zstd.Decompressor(@TypeOf(source)).init(allocator, source);
    defer decomp.deinit();

    var buffer: [4096]u8 = undefined;
    const reader = decomp.reader();

    while (true) {
        const n = try reader.read(&buffer);
        if (n == 0) break;

        // Process chunk
        processChunk(buffer[0..n]);
    }
}
```

---

## Streaming Compression

### Gzip

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn compressToFile(
    allocator: std.mem.Allocator,
    data: []const u8,
    output_path: []const u8,
) !void {
    // Create output file
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    // Create compressor
    var comp = try cz.gzip.Compressor(@TypeOf(file.writer())).init(allocator, file.writer(), .{});
    defer comp.deinit();

    // Write data (automatically compressed)
    try comp.writer().writeAll(data);

    // IMPORTANT: Must call finish() to flush remaining data
    try comp.finish();
}
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

### Example: Stream Large File

```zig
pub fn compressLargeFile(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8,
) !void {
    const input = try std.fs.cwd().openFile(input_path, .{});
    defer input.close();

    const output = try std.fs.cwd().createFile(output_path, .{});
    defer output.close();

    var comp = try cz.zstd.Compressor(@TypeOf(output.writer())).init(allocator, output.writer(), .{
        .level = .default,
    });
    defer comp.deinit();

    // Stream in chunks
    var buffer: [65536]u8 = undefined;
    while (true) {
        const n = try input.read(&buffer);
        if (n == 0) break;
        try comp.writer().writeAll(buffer[0..n]);
    }

    try comp.finish();
}
```

---

## Important: Always Call finish()

When using streaming compression, you **must** call `finish()` before closing the output:

```zig
var comp = try cz.gzip.Compressor(@TypeOf(file.writer())).init(allocator, file.writer(), .{});
defer comp.deinit();

try comp.writer().writeAll(data);
try comp.finish();  // Required! Flushes internal buffers
```

Without `finish()`, the compressed output may be incomplete or corrupt.

---

## Streaming with Options

### Compression Level

```zig
var comp = try cz.zstd.Compressor(@TypeOf(writer)).init(allocator, writer, .{
    .level = .best,  // Maximum compression
});
```

### LZ4 Frame Options

```zig
var comp = try cz.lz4.frame.Compressor(@TypeOf(writer)).init(allocator, writer, .{
    .level = .fast,
    .content_checksum = true,
    .block_checksum = false,
});
```

---

## Memory Considerations

Streaming uses internal buffers. Memory usage depends on the codec:

| Codec | Compression Buffer | Decompression Buffer |
|-------|-------------------|---------------------|
| Gzip | ~256 KB | ~32 KB |
| Zstd | ~128 KB | ~128 KB |
| Brotli | ~1 MB | ~256 KB |
| LZ4 | ~64 KB | ~64 KB |

For memory-constrained environments, prefer Gzip or LZ4.

---

## Piping Streams

Decompress and recompress in one pass:

```zig
pub fn recompress(
    allocator: std.mem.Allocator,
    input: anytype,
    output: anytype,
) !void {
    var decomp = try cz.gzip.Decompressor(@TypeOf(input)).init(allocator, input);
    defer decomp.deinit();

    var comp = try cz.zstd.Compressor(@TypeOf(output)).init(allocator, output, .{});
    defer comp.deinit();

    var buffer: [65536]u8 = undefined;
    const reader = decomp.reader();

    while (true) {
        const n = try reader.read(&buffer);
        if (n == 0) break;
        try comp.writer().writeAll(buffer[0..n]);
    }

    try comp.finish();
}
```

---

## Error Handling

Streaming operations can fail at any point:

```zig
var decomp = try cz.gzip.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();

const data = decomp.reader().readAllAlloc(allocator, max_size) catch |err| switch (err) {
    error.InvalidData => {
        // Stream is corrupted
    },
    error.ChecksumMismatch => {
        // Data integrity check failed
    },
    error.StreamTooLong => {
        // Exceeded max_size
    },
    else => return err,
};
```

---

## Complete Example

A command-line tool that compresses or decompresses files:

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4) {
        std.debug.print("Usage: {s} <compress|decompress> <input> <output>\n", .{args[0]});
        return;
    }

    const mode = args[1];
    const input_path = args[2];
    const output_path = args[3];

    const input = try std.fs.cwd().openFile(input_path, .{});
    defer input.close();

    const output = try std.fs.cwd().createFile(output_path, .{});
    defer output.close();

    if (std.mem.eql(u8, mode, "compress")) {
        var comp = try cz.gzip.Compressor(@TypeOf(output.writer())).init(allocator, output.writer(), .{});
        defer comp.deinit();

        var buf: [65536]u8 = undefined;
        while (true) {
            const n = try input.read(&buf);
            if (n == 0) break;
            try comp.writer().writeAll(buf[0..n]);
        }
        try comp.finish();
    } else {
        var decomp = try cz.gzip.Decompressor(@TypeOf(input.reader())).init(allocator, input.reader());
        defer decomp.deinit();

        var buf: [65536]u8 = undefined;
        while (true) {
            const n = try decomp.reader().read(&buf);
            if (n == 0) break;
            try output.writeAll(buf[0..n]);
        }
    }

    std.debug.print("Done!\n", .{});
}
```

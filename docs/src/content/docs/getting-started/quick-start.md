---
title: Quick Start
description: Learn compressionz basics in 5 minutes.
---

This guide covers the essential compressionz APIs with practical examples.

## Basic Compression & Decompression

The simplest usage with Zstd:

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "Hello, compressionz! This text will be compressed.";

    // Compress with Zstd
    const compressed = try cz.zstd.compress(original, allocator, .{});
    defer allocator.free(compressed);

    // Decompress
    const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    std.debug.print("Original: {d} bytes\n", .{original.len});
    std.debug.print("Compressed: {d} bytes\n", .{compressed.len});
    std.debug.print("Match: {}\n", .{std.mem.eql(u8, original, decompressed)});
}
```

## Using Different Codecs

Each codec has its own module with tailored options:

```zig
// Zstd - Fast, excellent ratio (recommended for most cases)
const zstd = try cz.zstd.compress(data, allocator, .{});

// LZ4 Frame - Self-describing with checksums
const lz4 = try cz.lz4.frame.compress(data, allocator, .{});

// LZ4 Block - Maximum speed, requires tracking original size
const lz4_block = try cz.lz4.block.compress(data, allocator);

// Snappy - Self-describing, real-time (no options)
const snappy = try cz.snappy.compress(data, allocator);

// Gzip - Universal compatibility
const gzip = try cz.gzip.compress(data, allocator, .{});

// Brotli - Best compression ratio
const brotli = try cz.brotli.compress(data, allocator, .{});
```

## Compression Levels

Control the speed/ratio trade-off:

```zig
// Fastest compression, lower ratio
const fast = try cz.zstd.compress(data, allocator, .{
    .level = .fast,
});

// Best compression, slower
const best = try cz.zstd.compress(data, allocator, .{
    .level = .best,
});

// Available levels: .fastest, .fast, .default, .better, .best
```

## Decompression Safety

Protect against decompression bombs (malicious data that expands massively):

```zig
const decompressed = try cz.zstd.decompress(compressed, allocator, .{
    .max_output_size = 100 * 1024 * 1024,  // 100 MB limit
});
```

If the decompressed size exceeds the limit, returns `error.OutputTooLarge`.

## Auto-Detecting Format

Automatically detect the compression format from magic bytes:

```zig
fn decompressUnknown(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
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

## Streaming Compression

Process large files without loading everything into memory:

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn compressFile(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) !void {
    // Open files
    const input = try std.fs.cwd().openFile(input_path, .{});
    defer input.close();

    const output = try std.fs.cwd().createFile(output_path, .{});
    defer output.close();

    // Create streaming compressor
    var compressor = try cz.gzip.Compressor(@TypeOf(output.writer())).init(allocator, output.writer(), .{});
    defer compressor.deinit();

    // Stream data through compressor
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try input.read(&buf);
        if (n == 0) break;
        try compressor.writer().writeAll(buf[0..n]);
    }

    // Finalize
    try compressor.finish();
}
```

## Streaming Decompression

```zig
pub fn decompressFile(allocator: std.mem.Allocator, input_path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();

    var decompressor = try cz.gzip.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
    defer decompressor.deinit();

    return decompressor.reader().readAllAlloc(allocator, 100 * 1024 * 1024);
}
```

## Working with Archives

Extract files from a ZIP archive:

```zig
const cz = @import("compressionz");

pub fn extractZip(allocator: std.mem.Allocator, zip_path: []const u8) !void {
    const file = try std.fs.cwd().openFile(zip_path, .{});
    defer file.close();

    var reader = try cz.archive.zip.Reader.init(allocator, file);
    defer reader.deinit();

    while (try reader.next()) |entry| {
        std.debug.print("{s}: {d} bytes\n", .{ entry.name, entry.uncompressed_size });

        if (!entry.is_directory) {
            const data = try entry.readAll(allocator);
            defer allocator.free(data);
            // Process file data...
        }
    }
}
```

Create a TAR archive:

```zig
pub fn createTar(allocator: std.mem.Allocator, output_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    var writer = cz.archive.tar.Writer(@TypeOf(file.writer())).init(file.writer());

    try writer.addFile("hello.txt", "Hello, World!");
    try writer.addFile("data.json", "{\"key\": \"value\"}");
    try writer.finish();
}
```

## Error Handling

compressionz uses a unified error type:

```zig
const result = cz.zstd.decompress(data, allocator, .{}) catch |err| switch (err) {
    error.InvalidData => {
        std.debug.print("Corrupted or invalid data\n", .{});
        return err;
    },
    error.ChecksumMismatch => {
        std.debug.print("Data integrity check failed\n", .{});
        return err;
    },
    error.OutputTooLarge => {
        std.debug.print("Decompressed size exceeds limit\n", .{});
        return err;
    },
    error.OutOfMemory => {
        std.debug.print("Allocation failed\n", .{});
        return err;
    },
    else => return err,
};
```

## Complete Example

Here's a complete program that compresses data with multiple codecs and reports results:

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read input file
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <file>\n", .{args[0]});
        return;
    }

    const data = try std.fs.cwd().readFileAlloc(allocator, args[1], 100 * 1024 * 1024);
    defer allocator.free(data);

    std.debug.print("Original size: {d} bytes\n\n", .{data.len});
    std.debug.print("{s:<12} {s:>12} {s:>10}\n", .{ "Codec", "Size", "Ratio" });
    std.debug.print("{s}\n", .{"-" ** 36});

    // Test each codec
    const zstd_result = try cz.zstd.compress(data, allocator, .{});
    defer allocator.free(zstd_result);
    printResult("Zstd", data.len, zstd_result.len);

    const lz4_result = try cz.lz4.frame.compress(data, allocator, .{});
    defer allocator.free(lz4_result);
    printResult("LZ4", data.len, lz4_result.len);

    const snappy_result = try cz.snappy.compress(data, allocator);
    defer allocator.free(snappy_result);
    printResult("Snappy", data.len, snappy_result.len);

    const gzip_result = try cz.gzip.compress(data, allocator, .{});
    defer allocator.free(gzip_result);
    printResult("Gzip", data.len, gzip_result.len);

    const brotli_result = try cz.brotli.compress(data, allocator, .{});
    defer allocator.free(brotli_result);
    printResult("Brotli", data.len, brotli_result.len);
}

fn printResult(name: []const u8, original: usize, compressed: usize) void {
    const ratio = 100.0 * (1.0 - @as(f64, @floatFromInt(compressed)) /
                                  @as(f64, @floatFromInt(original)));
    std.debug.print("{s:<12} {d:>12} {d:>9.1}%\n", .{ name, compressed, ratio });
}
```

## Next Steps

You now know the basics! Continue with:

- [Choosing a Codec](/getting-started/choosing-a-codec/) — Detailed codec comparison
- [API Reference](/api/compression/) — Complete API documentation
- [Benchmarks](/performance/benchmarks/) — Performance data
- [Advanced Features](/advanced/dictionary/) — Dictionary compression, archives, and more

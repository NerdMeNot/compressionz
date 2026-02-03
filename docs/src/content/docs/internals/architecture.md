---
title: Architecture
description: Internal architecture of compressionz.
---

This page describes the internal architecture of compressionz for contributors and those interested in implementation details.

## High-Level Structure

```
compressionz/
├── src/
│   ├── root.zig           # Public API entry point (re-exports codec modules)
│   ├── format.zig         # Format detection utilities
│   ├── level.zig          # Compression levels
│   ├── error.zig          # Error types
│   │
│   ├── lz4/               # Pure Zig LZ4
│   │   ├── lz4.zig        # Module entry (re-exports frame/block)
│   │   ├── block.zig      # LZ4 block compression
│   │   └── frame.zig      # LZ4 frame format
│   │
│   ├── snappy/            # Pure Zig Snappy
│   │   └── snappy.zig     # Snappy compression
│   │
│   ├── zstd.zig           # Zstd C bindings
│   ├── gzip.zig           # Gzip C bindings
│   ├── zlib_codec.zig     # Zlib/Deflate C bindings
│   ├── brotli.zig         # Brotli C bindings
│   │
│   └── archive/           # Archive formats
│       ├── archive.zig    # Archive entry point
│       ├── zip.zig        # ZIP reader/writer
│       └── tar.zig        # TAR reader/writer
│
├── vendor/                # Vendored C libraries
│   ├── zstd/
│   ├── zlib/
│   └── brotli/
│
└── benchmarks/            # Benchmark suite
```

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      User Application                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Codec-Specific API (root.zig)                │
│  cz.zstd.compress() / cz.lz4.frame.decompress() / etc.      │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  Pure Zig     │    │  C Bindings   │    │   Archive     │
│  LZ4, Snappy  │    │  Zstd, Gzip,  │    │   ZIP, TAR    │
│               │    │  Brotli, Zlib │    │               │
└───────────────┘    └───────────────┘    └───────────────┘
                              │
                              ▼
                    ┌───────────────┐
                    │ Vendored C    │
                    │ Libraries     │
                    └───────────────┘
```

## Codec-Specific API Design

### The Problem

Each compression library has its own API:

```c
// zstd
ZSTD_compress(dst, dstSize, src, srcSize, level);

// zlib
deflateInit(&stream, level);
deflate(&stream, Z_FINISH);

// brotli
BrotliEncoderCompress(quality, window, mode, input_size, input, &output_size, output);
```

### The Solution

compressionz provides codec-specific modules with consistent patterns:

```zig
const cz = @import("compressionz");

// Each codec module has its own interface with codec-specific options
const compressed = try cz.zstd.compress(input, allocator, .{ .level = .best });
const compressed = try cz.lz4.frame.compress(input, allocator, .{});
const compressed = try cz.snappy.compress(input, allocator);  // no options
const compressed = try cz.gzip.compress(input, allocator, .{ .level = .default });
const compressed = try cz.brotli.compress(input, allocator, .{ .level = .best });

// Format detection for auto-decompression
const format = cz.detect(data);
switch (format) {
    .zstd => try cz.zstd.decompress(data, allocator, .{}),
    .gzip => try cz.gzip.decompress(data, allocator, .{}),
    // ...
}
```

## Pure Zig Implementations

### LZ4 Architecture

```zig
// lz4/lz4.zig
pub const block = @import("block.zig");
pub const frame = @import("frame.zig");

// lz4/block.zig
pub fn compress(input: []const u8, allocator: Allocator) ![]u8 {
    // 1. Build hash table for match finding
    // 2. Scan input for matches
    // 3. Encode literals and match references
    // 4. Return compressed output
}

// lz4/frame.zig
pub fn compress(input: []const u8, allocator: Allocator, options: Options) ![]u8 {
    // 1. Write frame header (magic, flags, content size)
    // 2. Compress data blocks using block.compress()
    // 3. Write frame footer (checksum)
}
```

### Snappy Architecture

```zig
// snappy/snappy.zig
pub fn compress(input: []const u8, allocator: Allocator) ![]u8 {
    // 1. Write uncompressed length (varint)
    // 2. Build hash table
    // 3. Find matches and emit literals/copies
    // 4. Return compressed output
}
```

## C Bindings Architecture

### Pattern

All C bindings follow the same pattern:

```zig
// 1. Import C symbols
const c = @cImport({
    @cInclude("zstd.h");
});

// 2. Wrap with Zig-friendly API
pub fn compress(input: []const u8, allocator: Allocator, level: Level) ![]u8 {
    // Allocate output buffer
    const bound = c.ZSTD_compressBound(input.len);
    const output = try allocator.alloc(u8, bound);
    errdefer allocator.free(output);

    // Call C function
    const result = c.ZSTD_compress(
        output.ptr,
        output.len,
        input.ptr,
        input.len,
        level.toZstdLevel(),
    );

    // Handle errors
    if (c.ZSTD_isError(result) != 0) {
        allocator.free(output);
        return error.InvalidData;
    }

    // Shrink to actual size
    return allocator.realloc(output, result);
}
```

### Memory Management

C libraries are given Zig allocator callbacks:

```zig
fn zigAlloc(opaque: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque {
    const allocator = @as(*Allocator, @ptrCast(@alignCast(opaque)));
    const slice = allocator.alloc(u8, size) catch return null;
    return slice.ptr;
}

fn zigFree(opaque: ?*anyopaque, ptr: ?*anyopaque) callconv(.C) void {
    const allocator = @as(*Allocator, @ptrCast(@alignCast(opaque)));
    if (ptr) |p| {
        allocator.free(@ptrCast(p));
    }
}
```

## Streaming Architecture

Each codec provides its own streaming types:

```zig
// gzip.zig
pub fn Compressor(comptime WriterType: type) type {
    return struct {
        // Internal state
        allocator: std.mem.Allocator,
        inner_writer: WriterType,
        z_stream: *c.z_stream,

        pub fn init(allocator: Allocator, writer: WriterType, options: Options) !@This() {
            // Initialize compression state
        }

        pub fn deinit(self: *@This()) void {
            // Clean up
        }

        pub fn writer(self: *@This()) std.io.GenericWriter(*@This(), Error, write) {
            return .{ .context = self };
        }

        pub fn finish(self: *@This()) !void {
            // Finalize compression stream
        }

        fn write(self: *@This(), bytes: []const u8) !usize {
            // Compress and write to underlying writer
        }
    };
}

// Usage
var comp = try cz.gzip.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();
try comp.writer().writeAll(data);
try comp.finish();
```

## Error Handling

### Unified Error Type

```zig
// error.zig
pub const Error = error{
    InvalidData,
    ChecksumMismatch,
    OutputTooSmall,
    OutputTooLarge,
    UnexpectedEof,
    UnsupportedFeature,
    OutOfMemory,
    DictionaryMismatch,
    InvalidParameter,
};
```

### Error Mapping

Each implementation maps its errors:

```zig
// zstd.zig
fn mapZstdError(code: usize) Error {
    const err = c.ZSTD_getErrorCode(code);
    return switch (err) {
        c.ZSTD_error_memory_allocation => error.OutOfMemory,
        c.ZSTD_error_corruption_detected => error.InvalidData,
        c.ZSTD_error_checksum_wrong => error.ChecksumMismatch,
        c.ZSTD_error_dictionary_wrong => error.DictionaryMismatch,
        else => error.InvalidData,
    };
}
```

## Build System

### Vendored Libraries

```zig
// build.zig
pub fn build(b: *std.Build) void {
    const lib = b.addStaticLibrary(.{
        .name = "compressionz",
        // ...
    });

    // Add vendored zstd
    lib.addCSourceFiles(&zstd_sources, &zstd_flags);
    lib.addIncludePath(.{ .path = "vendor/zstd/lib" });

    // Add vendored zlib
    lib.addCSourceFiles(&zlib_sources, &zlib_flags);
    lib.addIncludePath(.{ .path = "vendor/zlib" });

    // Add vendored brotli
    lib.addCSourceFiles(&brotli_sources, &brotli_flags);
    lib.addIncludePath(.{ .path = "vendor/brotli/include" });
}
```

### Cross-Platform

Works on all Zig-supported targets:
- No system library dependencies
- C code compiled with Zig's C compiler
- Platform-specific SIMD handled by vendored libraries

## Testing Architecture

```zig
// root.zig
test {
    _ = @import("format.zig");
    _ = @import("lz4/lz4.zig");
    _ = @import("snappy/snappy.zig");
    _ = @import("zstd.zig");
    _ = @import("gzip.zig");
    _ = @import("brotli.zig");
    _ = @import("archive/archive.zig");
}

// Individual tests in each file
test "compress and decompress zstd" {
    const cz = @import("compressionz");
    const input = "test data";
    const compressed = try cz.zstd.compress(input, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    const decompressed = try cz.zstd.decompress(compressed, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);
}
```

## Future Architecture Considerations

### Potential Additions

1. **More pure Zig codecs** — Zstd decoder in pure Zig
2. **Async I/O** — Integration with Zig's async
3. **More archive formats** — 7z, rar (read-only)
4. **Wasm support** — Browser-compatible builds

### Design Principles

1. **Codec-specific APIs** — Each codec exposes only features it supports
2. **Zero dependencies** — Everything vendored
3. **Memory safety** — Zig's safety + careful C bindings
4. **Predictable performance** — No hidden allocations

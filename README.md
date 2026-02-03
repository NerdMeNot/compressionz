<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/logo-light.png">
    <img alt="compressionz" src="assets/logo-light.png" height="80">
  </picture>
</p>

<p align="center">
  A fast, ergonomic compression library for Zig with codec-specific APIs.
</p>

**36 GB/s** compression with LZ4 | **12 GB/s** with Zstd | **Zero dependencies** | Pure Zig + vendored C

---

## Why compressionz?

- **Codec-specific APIs** — Each codec exposes only the features it supports. No leaky abstractions.
- **Blazing fast** — Pure Zig LZ4 and Snappy with SIMD optimizations. 36+ GB/s compression throughput.
- **Zero system dependencies** — All C libraries vendored. No `brew install`, no `apt-get`. Just `zig build`.
- **Production ready** — Streaming, dictionaries, checksums, decompression bomb protection.
- **Archive support** — Read and write ZIP and TAR archives with simple APIs.

---

## Quick Start

```zig
const cz = @import("compressionz");

// Compress with Zstd
const compressed = try cz.zstd.compress(data, allocator, .{});
defer allocator.free(compressed);

// Decompress
const original = try cz.zstd.decompress(compressed, allocator, .{});
defer allocator.free(original);
```

Each codec has its own module with a tailored API. Use `cz.lz4`, `cz.gzip`, `cz.snappy`, `cz.brotli`, or `cz.zlib`.

---

## Installation

### build.zig.zon

```zig
.dependencies = .{
    .compressionz = .{
        .url = "https://github.com/NerdMeNot/compressionz/archive/refs/tags/v1.0.0-zig0.15.2.tar.gz",
        .hash = "...", // Run zig build to get the hash
    },
},
```

Or for local development:

```zig
.dependencies = .{
    .compressionz = .{
        .path = "../compressionz",
    },
},
```

### build.zig

```zig
const compressionz = b.dependency("compressionz", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("compressionz", compressionz.module("compressionz"));
```

---

## Codec Comparison

| Codec | Compress | Decompress | Ratio | Best For |
|-------|----------|------------|-------|----------|
| **LZ4 Block** | 36.6 GB/s | 8.1 GB/s | 99.5% | Maximum speed, internal use |
| **Snappy** | 31.6 GB/s | 9.2 GB/s | 95.3% | Real-time, message passing |
| **Zstd** | 12.0 GB/s | 11.6 GB/s | 99.9% | General purpose (recommended) |
| **LZ4 Frame** | 4.8 GB/s | 3.8 GB/s | 99.3% | File storage with checksums |
| **Gzip** | 2.4 GB/s | 2.4 GB/s | 99.2% | HTTP, cross-platform |
| **Brotli** | 1.3 GB/s | 1.9 GB/s | 99.9% | Static web assets |

**Recommendation:** Use **Zstd** unless you have specific requirements. It offers the best balance of speed and compression.

See [BENCHMARKS.md](BENCHMARKS.md) for detailed performance analysis.

---

## Codec Modules

| Module | One-shot | Streaming | Dictionary | Notes |
|--------|----------|-----------|------------|-------|
| `cz.lz4.frame` | Yes | Yes | No | Recommended LZ4 format with checksums |
| `cz.lz4.block` | Yes | No | No | Raw blocks, requires known size |
| `cz.snappy` | Yes | No | No | Speed-focused, no options |
| `cz.zstd` | Yes | Yes | Yes | Best ratio/speed balance |
| `cz.gzip` | Yes | Yes | No | Web/Unix standard |
| `cz.zlib` | Yes | Yes | Yes | Library interchange |
| `cz.brotli` | Yes | Yes | No | High compression ratio |

---

## API Reference

### Zstd

```zig
const cz = @import("compressionz");

// One-shot compression
const compressed = try cz.zstd.compress(data, allocator, .{ .level = .best });
defer allocator.free(compressed);

const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);

// With dictionary
const compressed = try cz.zstd.compressWithDict(data, dictionary, allocator, .{});
const decompressed = try cz.zstd.decompressWithDict(compressed, dictionary, allocator, .{});

// Streaming compression
var comp = try cz.zstd.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();
try comp.writer().writeAll(data);
try comp.finish();

// Streaming decompression
var decomp = try cz.zstd.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();
const result = try decomp.reader().readAllAlloc(allocator, max_size);
```

### LZ4

```zig
const cz = @import("compressionz");

// LZ4 Frame (recommended - includes checksums and size)
const compressed = try cz.lz4.frame.compress(data, allocator, .{ .level = .fast });
defer allocator.free(compressed);

const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);

// LZ4 Frame streaming
var comp = try cz.lz4.frame.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();
try comp.writer().writeAll(data);
try comp.finish();

// LZ4 Block (raw, requires known size for decompression)
const block_compressed = try cz.lz4.block.compress(data, allocator);
defer allocator.free(block_compressed);

const block_decompressed = try cz.lz4.block.decompressWithSize(block_compressed, data.len, allocator);
defer allocator.free(block_decompressed);
```

### Gzip

```zig
const cz = @import("compressionz");

// One-shot
const compressed = try cz.gzip.compress(data, allocator, .{ .level = .default });
defer allocator.free(compressed);

const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);

// Streaming compression
var comp = try cz.gzip.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();
try comp.writer().writeAll(data);
try comp.finish();

// Streaming decompression
var decomp = try cz.gzip.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();
const result = try decomp.reader().readAllAlloc(allocator, max_size);
```

### Zlib / Deflate

```zig
const cz = @import("compressionz");

// Zlib format
const compressed = try cz.zlib.compress(data, allocator, .{});
const decompressed = try cz.zlib.decompress(compressed, allocator, .{});

// Raw Deflate (no header/trailer)
const deflated = try cz.zlib.compressDeflate(data, allocator, .{});
const inflated = try cz.zlib.decompressDeflate(deflated, allocator, .{});

// With dictionary
const compressed = try cz.zlib.compressWithDict(data, dictionary, allocator, .{});
const decompressed = try cz.zlib.decompressWithDict(compressed, dictionary, allocator, .{});

// Streaming
var comp = try cz.zlib.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
var decomp = try cz.zlib.Decompressor(@TypeOf(reader)).init(allocator, reader);

// Deflate streaming
var deflate_comp = try cz.zlib.DeflateCompressor(@TypeOf(writer)).init(allocator, writer, .{});
var deflate_decomp = try cz.zlib.DeflateDecompressor(@TypeOf(reader)).init(allocator, reader);
```

### Brotli

```zig
const cz = @import("compressionz");

// One-shot
const compressed = try cz.brotli.compress(data, allocator, .{ .level = .best });
defer allocator.free(compressed);

const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);

// Streaming
var comp = try cz.brotli.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();
try comp.writer().writeAll(data);
try comp.finish();

var decomp = try cz.brotli.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();
const result = try decomp.reader().readAllAlloc(allocator, max_size);
```

### Snappy

```zig
const cz = @import("compressionz");

// One-shot only (no streaming, no options)
const compressed = try cz.snappy.compress(data, allocator);
defer allocator.free(compressed);

const decompressed = try cz.snappy.decompress(compressed, allocator);
defer allocator.free(decompressed);
```

### Compression Levels

All codecs that support levels use the same `Level` enum:

| Level | Speed | Ratio | Use Case |
|-------|-------|-------|----------|
| `.fastest` | Fastest | Lowest | CPU-bound, ratio doesn't matter |
| `.fast` | Fast | Good | Real-time compression |
| `.default` | Balanced | Good | **Recommended for most uses** |
| `.better` | Slower | Better | Storage, archival |
| `.best` | Slowest | Best | Static content, one-time compression |

---

## Format Detection

Automatically detect compression format from magic bytes:

```zig
const cz = @import("compressionz");

const format = cz.detect(data);
switch (format) {
    .gzip => {
        const decompressed = try cz.gzip.decompress(data, allocator, .{});
        defer allocator.free(decompressed);
    },
    .zstd => {
        const decompressed = try cz.zstd.decompress(data, allocator, .{});
        defer allocator.free(decompressed);
    },
    .lz4 => {
        const decompressed = try cz.lz4.frame.decompress(data, allocator, .{});
        defer allocator.free(decompressed);
    },
    .unknown => {
        // Cannot auto-detect format
    },
    // ... other formats
}
```

**Auto-detection supported:** `.lz4`, `.zstd`, `.gzip`, `.zlib`, `.snappy`, `.brotli`

---

## Decompression Bomb Protection

Protect against malicious compressed data that expands to huge sizes:

```zig
const cz = @import("compressionz");

// Limit decompressed output size
const result = cz.zstd.decompress(compressed, allocator, .{
    .max_output_size = 100 * 1024 * 1024,  // 100 MB limit
}) catch |err| switch (err) {
    error.OutputTooLarge => {
        // Data would exceed limit
    },
    else => return err,
};
```

All codecs support `max_output_size` in their decompress options.

---

## Archive Support

Read and write ZIP and TAR archives:

### ZIP

```zig
const cz = @import("compressionz");

// Read ZIP file
var file = try std.fs.cwd().openFile("archive.zip", .{});
defer file.close();

var reader = try cz.archive.zip.Reader.init(allocator, file);
defer reader.deinit();

while (try reader.next()) |entry| {
    if (!entry.is_directory) {
        const data = try entry.readAll(allocator);
        defer allocator.free(data);
        std.debug.print("{s}: {} bytes\n", .{ entry.name, data.len });
    }
}

// Write ZIP file
var out = try std.fs.cwd().createFile("output.zip", .{});
defer out.close();

var writer = cz.archive.zip.Writer(@TypeOf(out)).init(allocator, out);
try writer.addFile("hello.txt", "Hello, World!", .{});
try writer.addDirectory("subdir/", .{});
try writer.finish();
```

### TAR

```zig
const cz = @import("compressionz");

// Read TAR
var reader = try cz.archive.tar.Reader(@TypeOf(file)).init(file);
while (try reader.next()) |entry| {
    const data = try entry.readAll(allocator);
    defer allocator.free(data);
}

// Write TAR
var writer = cz.archive.tar.Writer(@TypeOf(out)).init(&out);
try writer.addFile("hello.txt", "Hello!");
try writer.addDirectory("subdir");
try writer.finish();
```

---

## Error Handling

All operations return a unified error type:

```zig
const cz = @import("compressionz");

const result = cz.zstd.decompress(data, allocator, .{}) catch |err| switch (err) {
    error.InvalidData => {
        // Corrupted or invalid compressed data
    },
    error.ChecksumMismatch => {
        // Data integrity check failed
    },
    error.OutputTooLarge => {
        // Exceeds max_output_size (decompression bomb protection)
    },
    error.OutputTooSmall => {
        // Buffer too small for in-place operations
    },
    error.UnexpectedEof => {
        // Input data truncated
    },
    error.UnsupportedFeature => {
        // Feature not supported by this codec
    },
    error.OutOfMemory => {
        // Allocation failed
    },
    else => return err,
};
```

---

## Implementation Details

| Codec | Source | SIMD | Notes |
|-------|--------|------|-------|
| LZ4 | Pure Zig | Yes | 16-byte vectorized match finding |
| Snappy | Pure Zig | Yes | 16-byte vectorized match finding |
| Zstd | Vendored zstd 1.5.7 | Yes | SSE2/AVX2/NEON support |
| Gzip/Zlib | Vendored zlib 1.3.1 | Partial | — |
| Brotli | Vendored brotli | Partial | — |

### SIMD Optimizations

The pure Zig codecs use explicit SIMD via `@Vector`:

```zig
// 16-byte vectorized comparison for match extension
const v1: @Vector(16, u8) = src[pos..][0..16].*;
const v2: @Vector(16, u8) = src[match_pos..][0..16].*;
const eq = v1 == v2;
const mask = @as(u16, @bitCast(eq));
```

This enables competitive performance with hand-optimized C implementations.

---

## Building

```bash
# Build library
zig build

# Run tests
zig build test

# Run benchmarks
zig build bench -Doptimize=ReleaseFast
```

---

## Performance Tips

1. **Use Zstd for general purpose** — Best balance of speed and ratio
2. **Use LZ4 Block for maximum speed** — 36+ GB/s, but requires tracking size
3. **Use dictionary compression for small data** — Dramatically improves ratios for zstd/zlib
4. **Use streaming for large files** — Avoids loading entire file into memory
5. **Use `.default` level** — The difference between levels is often minimal
6. **Use `max_output_size`** — Protects against decompression bombs

---

## Comparison with Alternatives

| Feature | compressionz | std.compress | zstd-c |
|---------|-------------|--------------|--------|
| Codec-specific APIs | Yes | Partial | Yes |
| LZ4 | Yes (Pure Zig) | No | No |
| Snappy | Yes (Pure Zig) | No | No |
| Zstd | Yes | No | Yes |
| Gzip | Yes | Yes | No |
| Brotli | Yes | No | No |
| Streaming | Yes | Yes | Yes |
| Dictionary | Yes (zstd, zlib) | No | Yes |
| Zero dependencies | Yes | Yes | No |
| Archives (ZIP/TAR) | Yes | No | No |

---

## License

Apache 2.0 — See [LICENSE](LICENSE)

This project includes vendored third-party libraries that retain their original licenses:

| Library | License | Copyright |
|---------|---------|-----------|
| zstd | BSD-3-Clause | Meta Platforms, Inc. |
| zlib | zlib | Jean-loup Gailly, Mark Adler |
| brotli | MIT | Google Inc. |

All vendored licenses are permissive and compatible with Apache 2.0. See [NOTICE](NOTICE) for full attribution.

---

## Contributing

Contributions are welcome! Please:

1. Run `zig build test` before submitting
2. Add tests for new functionality
3. Update documentation as needed
4. Run benchmarks if performance-related

---

## Acknowledgments

- [LZ4](https://github.com/lz4/lz4) — Original LZ4 algorithm by Yann Collet
- [Snappy](https://github.com/google/snappy) — Original Snappy algorithm by Google
- [Zstandard](https://github.com/facebook/zstd) — Zstd library by Facebook
- [zlib](https://zlib.net/) — zlib library by Jean-loup Gailly and Mark Adler
- [Brotli](https://github.com/google/brotli) — Brotli library by Google

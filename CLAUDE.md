# CLAUDE.md

This file provides guidance for AI assistants working with the compressionz codebase.

## Commit Preferences

- Do NOT add Co-Authored-By lines to commits
- Keep commit messages concise and descriptive

## Project Overview

Compressionz is a fast, ergonomic compression library for Zig with codec-specific APIs. Each codec module exposes only the features it supports, providing type-safe, discoverable interfaces. It includes both pure Zig implementations (LZ4, Snappy) and C FFI wrappers (Zstd, Gzip, Zlib, Brotli) using vendored libraries, plus archive format support (ZIP, TAR).

## Build Commands

```bash
zig build              # Build static library
zig build test         # Run all tests
zig build test --summary all  # Run tests with summary
zig build bench        # Run benchmarks
zig build check        # Semantic analysis (for IDE)
```

Minimum Zig version: 0.15.0

## Project Structure

```
src/
├── root.zig           # Public API entry point (re-exports)
├── format.zig         # Format detection utilities
├── level.zig          # Compression level presets
├── error.zig          # Unified error type
├── lz4/
│   ├── lz4.zig        # LZ4 module root (re-exports frame/block)
│   ├── block.zig      # Raw block compression (pure Zig, no streaming)
│   └── frame.zig      # LZ4 frame format (pure Zig, with streaming)
├── snappy/
│   └── snappy.zig     # Snappy compression (pure Zig, no streaming)
├── gzip.zig           # Gzip format with streaming (uses zlib)
├── zlib_codec.zig     # Zlib/Deflate formats with streaming (uses zlib)
├── zstd.zig           # Zstd with streaming and dictionary (uses libzstd)
├── brotli.zig         # Brotli with streaming (uses libbrotli)
└── archive/
    ├── archive.zig    # Archive module root
    ├── zip.zig        # ZIP format (with deflate)
    └── tar.zig        # TAR format (ustar)

vendor/                # Vendored C libraries
├── zlib/
├── zstd/
└── brotli/

benchmarks/            # Benchmark suite
```

## Codec-Specific API

Each codec has its own module with functions tailored to its capabilities.

### One-shot Compression
```zig
const cz = @import("compressionz");

// Zstd (supports dictionary)
const compressed = try cz.zstd.compress(input, allocator, .{ .level = .best });
const decompressed = try cz.zstd.decompress(compressed, allocator, .{});

// With dictionary
const compressed = try cz.zstd.compressWithDict(input, dict, allocator, .{});
const decompressed = try cz.zstd.decompressWithDict(compressed, dict, allocator, .{});

// LZ4 frame format (recommended)
const compressed = try cz.lz4.frame.compress(input, allocator, .{});
const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});

// LZ4 block format (requires known size)
const compressed = try cz.lz4.block.compress(input, allocator);
const decompressed = try cz.lz4.block.decompressWithSize(compressed, original_len, allocator);

// Snappy (no streaming, no options)
const compressed = try cz.snappy.compress(input, allocator);
const decompressed = try cz.snappy.decompress(compressed, allocator);

// Gzip
const compressed = try cz.gzip.compress(input, allocator, .{ .level = .default });
const decompressed = try cz.gzip.decompress(compressed, allocator, .{});

// Zlib (supports dictionary)
const compressed = try cz.zlib.compress(input, allocator, .{});
const decompressed = try cz.zlib.decompress(compressed, allocator, .{});

// Raw Deflate
const compressed = try cz.zlib.compressDeflate(input, allocator, .{});
const decompressed = try cz.zlib.decompressDeflate(compressed, allocator, .{});

// Brotli
const compressed = try cz.brotli.compress(input, allocator, .{ .level = .best });
const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
```

### Streaming Compression
```zig
const cz = @import("compressionz");

// Streaming compression (gzip example, same pattern for zstd, brotli, lz4.frame, zlib)
var comp = try cz.gzip.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
defer comp.deinit();
try comp.writer().writeAll(data);
try comp.finish();  // MUST call to finalize

// Streaming decompression
var decomp = try cz.gzip.Decompressor(@TypeOf(reader)).init(allocator, reader);
defer decomp.deinit();
const data = try decomp.reader().readAllAlloc(allocator, max_size);

// Zlib streaming (also has DeflateCompressor/DeflateDecompressor for raw deflate)
var comp = try cz.zlib.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
var decomp = try cz.zlib.Decompressor(@TypeOf(reader)).init(allocator, reader);
```

### Format Detection
```zig
const cz = @import("compressionz");

const format = cz.detect(data);
switch (format) {
    .gzip => {
        const decompressed = try cz.gzip.decompress(data, allocator, .{});
    },
    .zstd => {
        const decompressed = try cz.zstd.decompress(data, allocator, .{});
    },
    .lz4 => {
        const decompressed = try cz.lz4.frame.decompress(data, allocator, .{});
    },
    .unknown => {
        // Cannot auto-detect format
    },
    // ...
}
```

### Archive Reading/Writing
```zig
// ZIP reading
var reader = try cz.archive.zip.Reader.init(allocator, file);
defer reader.deinit();
while (try reader.next()) |entry| {
    const data = try entry.readAll(allocator);
    defer allocator.free(data);
}

// TAR writing
var writer = cz.archive.tar.Writer(*@TypeOf(stream)).init(&stream);
try writer.addFile("hello.txt", "Hello!");
try writer.addDirectory("subdir");
try writer.finish();
```

## Codec Feature Matrix

| Module | One-shot | Streaming | In-place | Dictionary | Notes |
|--------|----------|-----------|----------|------------|-------|
| `lz4.frame` | Yes | Yes | Yes | No | Recommended LZ4 format |
| `lz4.block` | Yes | No | Yes | No | Raw blocks, requires size |
| `snappy` | Yes | No | Yes | No | Speed-focused |
| `zstd` | Yes | Yes | No | Yes | Best ratio/speed |
| `gzip` | Yes | Yes | No | No | Web/Unix standard |
| `zlib` | Yes | Yes | No | Yes | Library interchange |
| `brotli` | Yes | Yes | No | No | High compression |

## Archive Formats

| Format | Reading | Writing | Compression |
|--------|---------|---------|-------------|
| ZIP | Yes | Yes | Store or Deflate |
| TAR | Yes | Yes | None (combine with gzip/zstd) |

## Zig 0.15 Patterns

Key patterns used in this codebase for Zig 0.15 compatibility:

### ArrayListUnmanaged
```zig
// Initialization
central_dir: std.ArrayListUnmanaged(Entry),
.central_dir = .{},

// Usage (pass allocator to methods)
try self.central_dir.append(self.allocator, item);
self.central_dir.deinit(self.allocator);
```

### GenericReader/GenericWriter
```zig
// Return type for streaming wrappers
pub fn reader(self: *Self) std.io.GenericReader(*Self, Error, read) {
    return .{ .context = self };
}
```

### Heap-allocated C State
C library states (z_stream, etc.) must be heap-allocated to avoid pointer invalidation:
```zig
z_stream: *c.z_stream,  // Pointer to heap-allocated state

pub fn init(allocator: Allocator) !Self {
    const z = try allocator.create(c.z_stream);
    // ...
}
```

## Adding a New Codec

1. Create implementation file in `src/` with:
   - `CompressOptions` / `DecompressOptions` structs
   - `compress()` / `decompress()` functions
   - `Compressor(WriterType)` / `Decompressor(ReaderType)` types (if streaming supported)
   - `maxCompressedSize()` helper
2. Add magic bytes to `src/format.zig` `detect()` if applicable
3. Re-export from `src/root.zig`
4. If C library: add build rules in `build.zig`, vendor sources
5. Add tests inline at bottom of implementation file

## Error Handling

Use error types and helpers from `src/error.zig`:

### Error Types
- `InvalidData` - Corrupted or malformed input
- `ChecksumMismatch` - Integrity check failed
- `OutputTooSmall` - Buffer insufficient for decompressInto
- `OutputTooLarge` - Exceeds max_output_size limit
- `UnexpectedEof` - Truncated input
- `UnsupportedFeature` - Feature not implemented

### Helper Functions
```zig
// Shrink allocation to actual size, handling resize failure gracefully
pub fn shrinkAllocation(allocator, buffer, actual_size) Error![]u8
```

## Archive Entry Lifetime

**TAR**: Entry pointers from `next()` are **invalidated** when `next()` is called again.
Copy any data you need before advancing.

**ZIP**: Entries are stored in an array and remain valid until `deinit()` is called.

## Testing

Tests are inline in source files:
- `src/root.zig` - API integration tests
- `src/format.zig` - Magic byte detection tests
- `src/archive/zip.zig` - ZIP round-trip tests
- `src/archive/tar.zig` - TAR round-trip tests
- Individual codec files - Codec-specific tests including streaming

## Notes

- All vendored C code compiles with the Zig build system (no cmake/make)
- Archive types are generic over source/dest for flexibility with files/buffers
- Each codec module is self-contained with its own streaming types

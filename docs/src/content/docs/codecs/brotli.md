---
title: Brotli
description: Deep dive into the Brotli compression codec.
---

Brotli is a modern compression algorithm developed by Google, optimized for web content. It achieves the best compression ratios among compressionz codecs.

## At a Glance

| Property | Value |
|----------|-------|
| **Developer** | Google |
| **First Release** | 2015 |
| **Implementation** | Vendored libbrotli |
| **License** | MIT |

### Performance

| Level | Compress | Decompress | Ratio |
|-------|----------|------------|-------|
| fast | 1.3 GB/s | 1.9 GB/s | 99.9% |
| default | 1.3 GB/s | 1.8 GB/s | 99.9% |
| best | 86 MB/s | 1.5 GB/s | 99.9%+ |

### Features

- Excellent compression ratios
- Streaming support
- Supported by modern browsers
- Multiple compression levels
- No magic bytes (can't auto-detect)
- No dictionary support (in this API)
- No built-in checksum

## Basic Usage

```zig
const cz = @import("compressionz");

// Compress
const compressed = try cz.brotli.compress(data, allocator, .{});
defer allocator.free(compressed);

// Decompress
const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
defer allocator.free(decompressed);
```

## Compression Levels

Brotli's levels have a significant impact on both speed and ratio:

```zig
// Fast - suitable for dynamic content
const fast = try cz.brotli.compress(data, allocator, .{
    .level = .fast,
});

// Default - balanced
const default = try cz.brotli.compress(data, allocator, .{
    .level = .default,
});

// Best - maximum compression for static assets
const best = try cz.brotli.compress(data, allocator, .{
    .level = .best,
});
```

### Level Comparison

| Level | Compress | Decompress | Ratio | Use Case |
|-------|----------|------------|-------|----------|
| `fast` | 1.3 GB/s | 1.9 GB/s | 99.9% | Dynamic content |
| `default` | 1.3 GB/s | 1.8 GB/s | 99.9% | General use |
| `best` | 86 MB/s | 1.5 GB/s | 99.9%+ | **Static assets** |

**Key insight:** `best` level is ~15x slower than `fast`, but produces the smallest files. Use `best` only for one-time compression (static files).

## Streaming

Brotli supports streaming for large files:

### Streaming Compression

```zig
const cz = @import("compressionz");
const std = @import("std");

pub fn compressToBrotli(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) !void {
    const input = try std.fs.cwd().openFile(input_path, .{});
    defer input.close();

    const output = try std.fs.cwd().createFile(output_path, .{});
    defer output.close();

    var comp = try cz.brotli.Compressor(@TypeOf(output.writer())).init(allocator, output.writer(), .{
        .level = .best,  // Worth the time for static files
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
pub fn decompressBrotli(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var decomp = try cz.brotli.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
    defer decomp.deinit();

    return decomp.reader().readAllAlloc(allocator, 1024 * 1024 * 1024);
}
```

## Why Brotli for Web?

Brotli was specifically designed for web content:

### 1. Built-in Static Dictionary

Brotli includes a 120 KB static dictionary with common web content:
- HTML tags (`<div>`, `<span>`, `<script>`)
- CSS properties (`background-color`, `font-family`)
- JavaScript keywords (`function`, `return`, `undefined`)
- Common words and phrases

This dramatically improves compression for typical web content.

### 2. Browser Support

| Browser | Support |
|---------|---------|
| Chrome | Since v49 |
| Firefox | Since v44 |
| Safari | Since v11 |
| Edge | Since v15 |
| IE | No |

~95% of browsers support Brotli.

### 3. HTTP Integration

```http
Accept-Encoding: gzip, deflate, br
Content-Encoding: br
```

## Web Asset Compression

Ideal workflow for static web assets:

```zig
const std = @import("std");
const cz = @import("compressionz");

pub fn precompressAssets(allocator: std.mem.Allocator, assets_dir: []const u8) !void {
    var dir = try std.fs.cwd().openDir(assets_dir, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;

        // Skip already compressed
        if (std.mem.endsWith(u8, entry.name, ".br")) continue;
        if (std.mem.endsWith(u8, entry.name, ".gz")) continue;

        const ext = std.fs.path.extension(entry.name);
        const should_compress = std.mem.eql(u8, ext, ".html") or
                                std.mem.eql(u8, ext, ".css") or
                                std.mem.eql(u8, ext, ".js") or
                                std.mem.eql(u8, ext, ".json") or
                                std.mem.eql(u8, ext, ".svg");

        if (should_compress) {
            const input_path = try std.fs.path.join(allocator, &.{ assets_dir, entry.name });
            defer allocator.free(input_path);

            const data = try std.fs.cwd().readFileAlloc(allocator, input_path, 10 * 1024 * 1024);
            defer allocator.free(data);

            // Compress with best level (one-time cost)
            const compressed = try cz.brotli.compress(data, allocator, .{
                .level = .best,
            });
            defer allocator.free(compressed);

            const output_path = try std.fmt.allocPrint(allocator, "{s}.br", .{input_path});
            defer allocator.free(output_path);

            try std.fs.cwd().writeFile(.{ .sub_path = output_path, .data = compressed });

            std.debug.print("{s}: {d} -> {d} bytes ({d:.1}%)\n", .{
                entry.name,
                data.len,
                compressed.len,
                @as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(data.len)) * 100,
            });
        }
    }
}
```

## Format Details

### No Magic Bytes

Unlike most formats, Brotli has no magic number:

```zig
// Cannot auto-detect Brotli
const format = cz.detect(data);  // Returns .unknown for Brotli

// Must know it's Brotli beforehand
const decompressed = try cz.brotli.decompress(data, allocator, .{});
```

**Workaround:** Use file extensions (`.br`) or content metadata to identify Brotli data.

## Algorithm Details

Brotli combines multiple techniques:

1. **LZ77 matching** — Find repeated sequences
2. **2nd-order context modeling** — Predict based on previous bytes
3. **Static dictionary** — 120 KB of common web strings
4. **Asymmetric numeral systems (ANS)** — Efficient entropy coding

### Why Brotli Compresses Better

- Larger window size (up to 16 MB vs Gzip's 32 KB)
- Better context modeling
- Optimized for text/web content
- Built-in dictionary for common patterns

## Brotli vs Gzip

| Metric | Brotli (best) | Gzip (best) |
|--------|---------------|-------------|
| Compress | 86 MB/s | 691 MB/s |
| Decompress | 1.5 GB/s | 2.9 GB/s |
| Ratio | **99.9%+** | 99.6% |
| Browser | ~95% | **100%** |
| Web-optimized | **Yes** | No |

### Typical Size Savings (Web Assets)

| Content Type | Gzip | Brotli | Savings |
|--------------|------|--------|---------|
| HTML | 20% | 17% | 15% smaller |
| CSS | 15% | 12% | 20% smaller |
| JavaScript | 22% | 18% | 18% smaller |
| JSON | 10% | 8% | 20% smaller |

## When to Use Brotli

**Best for:**
- Static web assets (CSS, JS, HTML)
- CDN content
- Pre-compressed files
- When bandwidth > CPU cost

**Not ideal for:**
- Dynamic content (use Gzip)
- Real-time compression (use LZ4/Snappy)
- General purpose (use Zstd)
- Legacy browser support (use Gzip)

## Memory Considerations

Brotli uses more memory than simpler algorithms:

| Operation | Memory |
|-----------|--------|
| Compression | ~1 MB |
| Decompression | ~256 KB |

Consider this for memory-constrained environments.

## Resources

- [RFC 7932 - Brotli Format](https://datatracker.ietf.org/doc/html/rfc7932)
- [Brotli GitHub](https://github.com/google/brotli)
- [Brotli at Google](https://opensource.google/projects/brotli)

---
title: Zero-Copy API
description: Compress and decompress into pre-allocated buffers.
---

The zero-copy API allows compression and decompression into pre-allocated buffers, avoiding allocations in hot paths.

## Standard vs Zero-Copy

Standard compression allocates memory for the output:

```zig
// Allocates new memory
const compressed = try cz.lz4.frame.compress(data, allocator, .{});
defer allocator.free(compressed);
```

Zero-copy uses your buffer:

```zig
// Uses pre-allocated buffer
var buffer: [65536]u8 = undefined;
const compressed = try cz.lz4.frame.compressInto(data, &buffer, .{});
// No allocation, no free needed
```

## When to Use Zero-Copy

**Use zero-copy when:**

- Processing many small items in a loop
- Working in memory-constrained environments
- Latency-sensitive code paths
- Embedded or real-time systems

**Use standard API when:**

- Output size is unpredictable
- Simplicity is more important than performance
- Working with large data (may need to reallocate anyway)

---

## Supported Codecs

| Codec | Zero-Copy Support |
|-------|-------------------|
| `lz4.frame` | Yes |
| `lz4.block` | Yes |
| `snappy` | Yes |
| `zstd` | No |
| `gzip` | No |
| `brotli` | No |

---

## LZ4 Block

```zig
const cz = @import("compressionz");

var compress_buf: [65536]u8 = undefined;
var decompress_buf: [65536]u8 = undefined;

// Compress into buffer
const compressed = try cz.lz4.block.compressInto(data, &compress_buf);

// Decompress into buffer
const decompressed = try cz.lz4.block.decompressInto(compressed, &decompress_buf);
```

## LZ4 Frame

```zig
const cz = @import("compressionz");

var compress_buf: [65536]u8 = undefined;
var decompress_buf: [65536]u8 = undefined;

// Compress into buffer with options
const compressed = try cz.lz4.frame.compressInto(data, &compress_buf, .{
    .level = .fast,
    .content_checksum = true,
});

// Decompress into buffer
const decompressed = try cz.lz4.frame.decompressInto(compressed, &decompress_buf);
```

## Snappy

```zig
const cz = @import("compressionz");

var compress_buf: [65536]u8 = undefined;
var decompress_buf: [65536]u8 = undefined;

// Compress into buffer
const compressed = try cz.snappy.compressInto(data, &compress_buf);

// Decompress into buffer
const decompressed = try cz.snappy.decompressInto(compressed, &decompress_buf);
```

---

## Calculating Buffer Size

### For Compression

Use `maxCompressedSize` to calculate the worst-case size:

```zig
// LZ4 Block
const max_lz4_block = cz.lz4.block.maxCompressedSize(data.len);

// LZ4 Frame
const max_lz4_frame = cz.lz4.frame.maxCompressedSize(data.len);

// Snappy
const max_snappy = cz.snappy.maxCompressedSize(data.len);
```

Example:

```zig
const max_size = cz.lz4.block.maxCompressedSize(data.len);
const buffer = try allocator.alloc(u8, max_size);
defer allocator.free(buffer);

const compressed = try cz.lz4.block.compressInto(data, buffer);
// compressed.len will be <= max_size
```

### For Decompression

If you know the original size:

```zig
var buffer: [known_original_size]u8 = undefined;
const decompressed = try cz.lz4.frame.decompressInto(compressed, &buffer);
```

If the size is encoded in the compressed data (LZ4 frame):

```zig
// LZ4 frame includes content size in header (if it was included during compression)
const content_size = cz.lz4.frame.getContentSize(compressed) orelse {
    // Size not in header, use estimate or error
    return error.SizeUnknown;
};

const buffer = try allocator.alloc(u8, content_size);
defer allocator.free(buffer);

const decompressed = try cz.lz4.frame.decompressInto(compressed, buffer);
```

---

## Reusing Buffers

Zero-copy shines when processing multiple items:

```zig
const cz = @import("compressionz");

pub fn processItems(items: []const []const u8) !void {
    // Allocate buffers once
    var compress_buf: [65536]u8 = undefined;
    var decompress_buf: [65536]u8 = undefined;

    for (items) |item| {
        // Compress into buffer (no allocation)
        const compressed = try cz.lz4.block.compressInto(item, &compress_buf);

        // Send compressed data somewhere...
        try sendData(compressed);
    }
}
```

Compare with standard API:

```zig
pub fn processItemsStandard(allocator: Allocator, items: []const []const u8) !void {
    for (items) |item| {
        // Allocates for each item
        const compressed = try cz.lz4.block.compress(item, allocator);
        defer allocator.free(compressed);  // Free for each item

        try sendData(compressed);
    }
}
```

---

## Error Handling

### OutputTooSmall

```zig
const result = cz.lz4.block.compressInto(large_data, &small_buffer) catch |err| {
    if (err == error.OutputTooSmall) {
        // Buffer too small, need to allocate larger
        const size = cz.lz4.block.maxCompressedSize(large_data.len);
        const bigger = try allocator.alloc(u8, size);
        return cz.lz4.block.compressInto(large_data, bigger);
    }
    return err;
};
```

---

## Performance Comparison

Benchmark: Compressing 1000 x 1 KB items

| Method | Time | Allocations |
|--------|------|-------------|
| Standard API | 15 ms | 2000 |
| Zero-Copy | 12 ms | 0 |

The performance gain comes from avoiding allocator overhead, not from the compression itself.

---

## Best Practices

1. **Pre-size buffers** — Use `maxCompressedSize` or known sizes
2. **Reuse buffers** — Don't reallocate between operations
3. **Handle errors** — Always check for `OutputTooSmall`
4. **Fall back gracefully** — Use standard API for unsupported codecs

```zig
pub fn compressWithFallback(
    data: []const u8,
    buffer: []u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    // Try zero-copy first
    return cz.lz4.block.compressInto(data, buffer) catch |err| {
        if (err == error.OutputTooSmall) {
            // Fall back to allocating version
            return cz.lz4.block.compress(data, allocator);
        }
        return err;
    };
}
```

---

## Complete Example

```zig
const std = @import("std");
const cz = @import("compressionz");

pub const MessageProcessor = struct {
    compress_buf: []u8,
    decompress_buf: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, max_message_size: usize) !MessageProcessor {
        const compress_size = cz.lz4.block.maxCompressedSize(max_message_size);
        return .{
            .compress_buf = try allocator.alloc(u8, compress_size),
            .decompress_buf = try allocator.alloc(u8, max_message_size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MessageProcessor) void {
        self.allocator.free(self.compress_buf);
        self.allocator.free(self.decompress_buf);
    }

    pub fn compress(self: *MessageProcessor, data: []const u8) ![]u8 {
        return cz.lz4.block.compressInto(data, self.compress_buf);
    }

    pub fn decompress(self: *MessageProcessor, compressed: []const u8, original_size: usize) ![]u8 {
        return cz.lz4.block.decompressIntoWithSize(compressed, self.decompress_buf, original_size);
    }
};
```

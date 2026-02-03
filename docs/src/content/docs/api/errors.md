---
title: Error Handling
description: Complete reference for compressionz errors.
---

compressionz uses a unified error type across all operations for consistent error handling.

## Error Type

```zig
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

---

## Error Descriptions

### InvalidData

The input data is corrupted, malformed, or not compressed with the specified codec.

**Common causes:**

- Data was modified after compression
- Wrong codec used for decompression
- Truncated compressed data
- Random/uncompressed data passed to decompress

**Example:**

```zig
const result = cz.zstd.decompress(random_data, allocator, .{}) catch |err| {
    if (err == error.InvalidData) {
        std.debug.print("Data is not valid Zstd compressed data\n", .{});
        return;
    }
    return err;
};
```

**Solutions:**

1. Verify you're using the correct codec
2. Check data wasn't corrupted in transit/storage
3. Use auto-detection: `cz.detect(data)`

---

### ChecksumMismatch

Built-in checksum verification failed. Data integrity compromised.

**Common causes:**

- Data corruption during storage or transmission
- Partial/incomplete data
- Hardware errors (disk, memory)

**Example:**

```zig
const result = cz.lz4.frame.decompress(data, allocator, .{}) catch |err| {
    if (err == error.ChecksumMismatch) {
        std.debug.print("Data corrupted! Checksum verification failed.\n", .{});
        // Request retransmission, restore from backup, etc.
        return error.DataCorruption;
    }
    return err;
};
```

**Solutions:**

1. Re-fetch or restore data from source
2. Check storage/network for errors
3. Use checksums at application level too

**Note:** Only occurs for codecs with checksums: LZ4 frame, Gzip, Zlib, Zstd

---

### OutputTooSmall

Buffer provided to `compressInto` or `decompressInto` is too small.

**Common causes:**

- Pre-allocated buffer undersized
- Incorrect size calculation

**Example:**

```zig
var small_buffer: [100]u8 = undefined;

const result = cz.lz4.block.compressInto(large_data, &small_buffer) catch |err| {
    if (err == error.OutputTooSmall) {
        // Allocate larger buffer
        const size = cz.lz4.block.maxCompressedSize(large_data.len);
        const buffer = try allocator.alloc(u8, size);
        return cz.lz4.block.compressInto(large_data, buffer);
    }
    return err;
};
```

**Solutions:**

1. Use `maxCompressedSize()` for compression buffers
2. Use known original size for decompression buffers
3. Fall back to allocating API

---

### OutputTooLarge

Decompressed size exceeds `max_output_size` limit.

**Common causes:**

- Decompression bomb (malicious data)
- Unexpectedly large legitimate data
- Limit set too low

**Example:**

```zig
const result = cz.gzip.decompress(untrusted_data, allocator, .{
    .max_output_size = 10 * 1024 * 1024,  // 10 MB limit
}) catch |err| {
    if (err == error.OutputTooLarge) {
        std.debug.print("Decompressed size exceeds 10 MB limit\n", .{});
        return error.SuspiciousInput;
    }
    return err;
};
```

**Solutions:**

1. Increase limit if data is trusted
2. Reject untrusted data that exceeds limits
3. Stream process large data instead

---

### UnexpectedEof

Compressed data ended unexpectedly. Input is truncated.

**Common causes:**

- Incomplete download/transfer
- File truncated
- Stream closed prematurely

**Example:**

```zig
const result = cz.zstd.decompress(data, allocator, .{}) catch |err| {
    if (err == error.UnexpectedEof) {
        std.debug.print("Compressed data is incomplete\n", .{});
        return error.IncompleteData;
    }
    return err;
};
```

**Solutions:**

1. Verify complete data transfer
2. Check file size matches expected
3. Re-download/re-fetch data

---

### UnsupportedFeature

Requested feature not available for this codec.

**Common causes:**

- Zero-copy with codec that doesn't support it
- Dictionary with codec that doesn't support it

**Example:**

```zig
// Snappy doesn't support options
// This is a compile-time error with the new API, not runtime
```

With the codec-specific API, most unsupported feature errors become compile-time errors since each codec only exposes its supported features.

---

### OutOfMemory

Memory allocation failed.

**Common causes:**

- System out of memory
- Decompressed size too large for available memory
- Allocator limits reached

**Example:**

```zig
const result = cz.zstd.decompress(data, allocator, .{}) catch |err| {
    if (err == error.OutOfMemory) {
        std.debug.print("Insufficient memory for decompression\n", .{});
        // Try streaming API or smaller chunks
        return error.ResourceExhausted;
    }
    return err;
};
```

**Solutions:**

1. Use streaming API for large data
2. Process in smaller chunks
3. Set `max_output_size` to limit memory use
4. Free other memory before retry

---

### DictionaryMismatch

Dictionary used for decompression doesn't match compression dictionary.

**Common causes:**

- Wrong dictionary provided
- Dictionary version mismatch
- Dictionary corrupted

**Example:**

```zig
const result = cz.zstd.decompressWithDict(data, wrong_dictionary, allocator, .{}) catch |err| {
    if (err == error.DictionaryMismatch) {
        std.debug.print("Dictionary doesn't match compressed data\n", .{});
        return error.ConfigurationError;
    }
    return err;
};
```

**Solutions:**

1. Verify correct dictionary is used
2. Version dictionaries and store version with data
3. Include dictionary ID in metadata

---

### InvalidParameter

Invalid parameter value provided.

**Common causes:**

- Missing required parameter (e.g., original size for LZ4 block)
- Invalid option combination

**Example:**

```zig
// LZ4 block requires original size for decompression
// Using decompressWithSize is required:
const result = try cz.lz4.block.decompressWithSize(compressed, original_size, allocator);
```

---

## Comprehensive Error Handling

Pattern for handling all errors:

```zig
const cz = @import("compressionz");

pub fn safeDecompress(
    data: []const u8,
    allocator: std.mem.Allocator,
    max_size: usize,
) ![]u8 {
    // Auto-detect format
    const format = cz.detect(data);

    return switch (format) {
        .zstd => cz.zstd.decompress(data, allocator, .{ .max_output_size = max_size }),
        .gzip => cz.gzip.decompress(data, allocator, .{ .max_output_size = max_size }),
        .lz4 => cz.lz4.frame.decompress(data, allocator, .{ .max_output_size = max_size }),
        .zlib => cz.zlib.decompress(data, allocator, .{ .max_output_size = max_size }),
        .snappy => cz.snappy.decompressWithLimit(data, allocator, max_size),
        .unknown => error.InvalidData,
    } catch |err| switch (err) {
        error.InvalidData => {
            log.err("Invalid or corrupted compressed data", .{});
            return error.DataCorruption;
        },
        error.ChecksumMismatch => {
            log.err("Checksum verification failed", .{});
            return error.DataCorruption;
        },
        error.OutputTooLarge => {
            log.warn("Decompressed size exceeds {d} byte limit", .{max_size});
            return error.DataTooLarge;
        },
        error.UnexpectedEof => {
            log.err("Compressed data truncated", .{});
            return error.IncompleteData;
        },
        error.OutOfMemory => {
            log.err("Out of memory during decompression", .{});
            return error.OutOfMemory;
        },
        else => {
            log.err("Unexpected decompression error: {}", .{err});
            return err;
        },
    };
}
```

---

## Error Recovery Strategies

| Error | Recovery Strategy |
|-------|-------------------|
| `InvalidData` | Try auto-detection, re-fetch data |
| `ChecksumMismatch` | Re-fetch from source, restore from backup |
| `OutputTooSmall` | Use larger buffer or allocating API |
| `OutputTooLarge` | Increase limit or reject |
| `UnexpectedEof` | Re-fetch complete data |
| `UnsupportedFeature` | Use different API or codec |
| `OutOfMemory` | Stream process, reduce limits |
| `DictionaryMismatch` | Use correct dictionary |
| `InvalidParameter` | Fix parameters |

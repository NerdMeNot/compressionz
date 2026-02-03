---
title: Testing
description: How to test compression in your applications.
---

This guide covers testing strategies for applications using compressionz.

## Running Library Tests

Run the full compressionz test suite:

```bash
# Run all tests
zig build test

# Run tests with optimizations (faster)
zig build test -Doptimize=ReleaseFast

# Run specific test file
zig test src/lz4/block.zig
```

## Round-Trip Testing

The most important test for compression: data survives the round trip.

```zig
const std = @import("std");
const cz = @import("compressionz");
const testing = std.testing;

test "round trip preserves data" {
    const original = "Hello, compressionz!";

    const compressed = try cz.zstd.compress(original, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    const decompressed = try cz.zstd.decompress(compressed, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}
```

## Testing All Codecs

Verify your data works with every codec:

```zig
test "all codecs round trip" {
    const test_data = "Test data for compression round trip verification";

    // Zstd
    {
        const compressed = try cz.zstd.compress(test_data, testing.allocator, .{});
        defer testing.allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, testing.allocator, .{});
        defer testing.allocator.free(decompressed);
        try testing.expectEqualStrings(test_data, decompressed);
    }

    // LZ4 Frame
    {
        const compressed = try cz.lz4.frame.compress(test_data, testing.allocator, .{});
        defer testing.allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, testing.allocator, .{});
        defer testing.allocator.free(decompressed);
        try testing.expectEqualStrings(test_data, decompressed);
    }

    // Snappy
    {
        const compressed = try cz.snappy.compress(test_data, testing.allocator);
        defer testing.allocator.free(compressed);
        const decompressed = try cz.snappy.decompress(compressed, testing.allocator);
        defer testing.allocator.free(decompressed);
        try testing.expectEqualStrings(test_data, decompressed);
    }

    // Gzip
    {
        const compressed = try cz.gzip.compress(test_data, testing.allocator, .{});
        defer testing.allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, testing.allocator, .{});
        defer testing.allocator.free(decompressed);
        try testing.expectEqualStrings(test_data, decompressed);
    }

    // Brotli
    {
        const compressed = try cz.brotli.compress(test_data, testing.allocator, .{});
        defer testing.allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, testing.allocator, .{});
        defer testing.allocator.free(decompressed);
        try testing.expectEqualStrings(test_data, decompressed);
    }
}
```

## Edge Case Testing

### Empty Data

```zig
test "handles empty input" {
    const empty: []const u8 = "";

    const compressed = try cz.zstd.compress(empty, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    const decompressed = try cz.zstd.decompress(compressed, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqual(@as(usize, 0), decompressed.len);
}
```

### Single Byte

```zig
test "handles single byte" {
    const single = "x";

    const compressed = try cz.lz4.frame.compress(single, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    const decompressed = try cz.lz4.frame.decompress(compressed, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqualStrings(single, decompressed);
}
```

### Large Data

```zig
test "handles large data" {
    // 10 MB of test data
    const size = 10 * 1024 * 1024;
    const data = try testing.allocator.alloc(u8, size);
    defer testing.allocator.free(data);

    // Fill with pattern
    for (data, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }

    const compressed = try cz.zstd.compress(data, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    const decompressed = try cz.zstd.decompress(compressed, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqualSlices(u8, data, decompressed);
}
```

### Binary Data

```zig
test "handles binary data with nulls" {
    const binary = &[_]u8{ 0x00, 0xFF, 0x00, 0xAB, 0x00, 0xCD };

    const compressed = try cz.snappy.compress(binary, testing.allocator);
    defer testing.allocator.free(compressed);

    const decompressed = try cz.snappy.decompress(compressed, testing.allocator);
    defer testing.allocator.free(decompressed);

    try testing.expectEqualSlices(u8, binary, decompressed);
}
```

### Highly Compressible Data

```zig
test "compresses repetitive data well" {
    // 1 MB of repeated 'a'
    const data = try testing.allocator.alloc(u8, 1024 * 1024);
    defer testing.allocator.free(data);
    @memset(data, 'a');

    const compressed = try cz.zstd.compress(data, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    // Should compress very well
    try testing.expect(compressed.len < data.len / 100);

    const decompressed = try cz.zstd.decompress(compressed, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqualSlices(u8, data, decompressed);
}
```

### Incompressible Data

```zig
test "handles random data" {
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();

    const data = try testing.allocator.alloc(u8, 10000);
    defer testing.allocator.free(data);
    random.bytes(data);

    const compressed = try cz.lz4.frame.compress(data, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    // Random data may expand slightly
    try testing.expect(compressed.len <= data.len + 1000);

    const decompressed = try cz.lz4.frame.decompress(compressed, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqualSlices(u8, data, decompressed);
}
```

## Error Handling Tests

### Corrupted Data

```zig
test "detects corrupted data" {
    const original = "Valid data to compress";

    const compressed = try cz.zstd.compress(original, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    // Corrupt the compressed data
    var corrupted = try testing.allocator.dupe(u8, compressed);
    defer testing.allocator.free(corrupted);
    corrupted[compressed.len / 2] ^= 0xFF;

    // Should fail to decompress
    const result = cz.zstd.decompress(corrupted, testing.allocator, .{});
    try testing.expectError(error.InvalidData, result);
}
```

### Invalid Magic Bytes

```zig
test "rejects invalid format" {
    const garbage = &[_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04 };

    const result = cz.zstd.decompress(garbage, testing.allocator, .{});
    try testing.expectError(error.InvalidData, result);
}
```

### Truncated Data

```zig
test "detects truncated data" {
    const original = "Some data to compress for truncation test";

    const compressed = try cz.gzip.compress(original, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    // Truncate to half
    const truncated = compressed[0 .. compressed.len / 2];

    const result = cz.gzip.decompress(truncated, testing.allocator, .{});
    try testing.expectError(error.UnexpectedEof, result);
}
```

## Streaming Tests

```zig
test "streaming compression works" {
    const data = "Test data for streaming";

    // Streaming compression to buffer
    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    var comp = try cz.gzip.Compressor(@TypeOf(output.writer())).init(testing.allocator, output.writer(), .{});
    defer comp.deinit();

    try comp.writer().writeAll(data);
    try comp.finish();

    // Decompress and verify
    const decompressed = try cz.gzip.decompress(output.items, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqualStrings(data, decompressed);
}
```

## Codec Detection Tests

```zig
test "detects codec from compressed data" {
    const data = "Data for codec detection test";

    // Test Zstd detection
    {
        const compressed = try cz.zstd.compress(data, testing.allocator, .{});
        defer testing.allocator.free(compressed);

        const format = cz.detect(compressed);
        try testing.expectEqual(cz.Format.zstd, format);
    }

    // Test Gzip detection
    {
        const compressed = try cz.gzip.compress(data, testing.allocator, .{});
        defer testing.allocator.free(compressed);

        const format = cz.detect(compressed);
        try testing.expectEqual(cz.Format.gzip, format);
    }

    // Test LZ4 detection
    {
        const compressed = try cz.lz4.frame.compress(data, testing.allocator, .{});
        defer testing.allocator.free(compressed);

        const format = cz.detect(compressed);
        try testing.expectEqual(cz.Format.lz4, format);
    }
}
```

## Dictionary Tests

```zig
test "dictionary improves small data compression" {
    const dictionary =
        \\{"type":"event","timestamp":0,"user":"","action":""}
    ;

    const sample =
        \\{"type":"event","timestamp":1234,"user":"alice","action":"login"}
    ;

    // Without dictionary
    const without = try cz.zstd.compress(sample, testing.allocator, .{});
    defer testing.allocator.free(without);

    // With dictionary
    const with = try cz.zstd.compressWithDict(sample, dictionary, testing.allocator, .{});
    defer testing.allocator.free(with);

    // Dictionary should help
    try testing.expect(with.len <= without.len);

    // Verify decompression
    const decompressed = try cz.zstd.decompressWithDict(with, dictionary, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqualStrings(sample, decompressed);
}
```

## Memory Leak Testing

Use Zig's testing allocator to detect leaks:

```zig
test "no memory leaks" {
    // testing.allocator automatically detects leaks
    const data = "Test for memory leaks";

    const compressed = try cz.zstd.compress(data, testing.allocator, .{});
    defer testing.allocator.free(compressed);

    const decompressed = try cz.zstd.decompress(compressed, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    // If we forget to free, the test will fail with:
    // "memory leak detected"
}
```

## CI Integration

Example GitHub Actions workflow:

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.0

      - name: Run tests
        run: zig build test

      - name: Run tests (optimized)
        run: zig build test -Doptimize=ReleaseFast
```

## Summary

- **Always test round trips** — data in equals data out
- **Test edge cases** — empty, single byte, large, binary
- **Test error handling** — corrupted, truncated, invalid data
- **Use testing.allocator** — catches memory leaks automatically
- **Test all codecs** — verify your data works everywhere

---
title: Pure Zig Codecs
description: Implementation details for LZ4 and Snappy pure Zig codecs.
---

compressionz includes pure Zig implementations of LZ4 and Snappy, with no C dependencies. This page details their implementation.

## Why Pure Zig?

Benefits:
- **No C compiler needed** for these codecs
- **Full control** over memory and safety
- **Zig optimizations** apply directly
- **Easier to understand** and modify
- **Cross-compilation** just works

Trade-offs:
- Implementation effort
- Must match format specifications exactly

## LZ4 Implementation

### Algorithm Overview

LZ4 is a byte-oriented LZ77 variant:

```
1. Build hash table from 4-byte sequences
2. For each position:
   a. Hash current 4 bytes
   b. Look up potential match
   c. If match found, emit copy
   d. If no match, emit literal
3. Encode using LZ4's token format
```

### Hash Table

```zig
const HASH_LOG = 14;
const HASH_SIZE = 1 << HASH_LOG;

pub fn compress(input: []const u8, allocator: Allocator) ![]u8 {
    var hash_table: [HASH_SIZE]u32 = undefined;
    @memset(&hash_table, 0);

    // Hash function for 4 bytes
    fn hash(v: u32) u32 {
        return (v *% 2654435761) >> (32 - HASH_LOG);
    }

    // ...
}
```

### Token Encoding

LZ4 uses a simple token format:

```
┌─────────────────┬────────────────────┬──────────────────┐
│ Token (1 byte)  │ Literals           │ Match info       │
│ LLLL MMMM       │ (literal_len bytes)│ (offset + ext)   │
├─────────────────┼────────────────────┼──────────────────┤
│ L = literal len │ Literal bytes      │ 2-byte offset    │
│ M = match len-4 │ (0-15, extended)   │ + extended length│
└─────────────────┴────────────────────┴──────────────────┘
```

```zig
fn emitSequence(
    writer: anytype,
    literal: []const u8,
    match_offset: u16,
    match_length: usize,
) !void {
    // Encode token
    var token: u8 = 0;

    // Literal length in high nibble
    const lit_len = literal.len;
    if (lit_len < 15) {
        token |= @intCast(lit_len << 4);
    } else {
        token |= 0xF0;
    }

    // Match length in low nibble
    const ml = match_length - 4;  // Min match is 4
    if (ml < 15) {
        token |= @intCast(ml);
    } else {
        token |= 0x0F;
    }

    try writer.writeByte(token);

    // Extended literal length
    if (lit_len >= 15) {
        var remaining = lit_len - 15;
        while (remaining >= 255) : (remaining -= 255) {
            try writer.writeByte(255);
        }
        try writer.writeByte(@intCast(remaining));
    }

    // Literals
    try writer.writeAll(literal);

    // Match offset (little-endian)
    try writer.writeInt(u16, match_offset, .little);

    // Extended match length
    if (ml >= 15) {
        var remaining = ml - 15;
        while (remaining >= 255) : (remaining -= 255) {
            try writer.writeByte(255);
        }
        try writer.writeByte(@intCast(remaining));
    }
}
```

### Frame Format

LZ4 frame wraps blocks with headers:

```zig
pub fn compressFrame(input: []const u8, allocator: Allocator, options: Options) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    // Magic number
    try output.appendSlice(&[_]u8{ 0x04, 0x22, 0x4D, 0x18 });

    // Frame descriptor
    var flg: u8 = 0x64;  // Version 01, Block Independence, Content checksum
    if (options.content_size != null) flg |= 0x08;
    try output.append(flg);

    var bd: u8 = 0x70;  // 4MB max block size
    try output.append(bd);

    // Content size (optional)
    if (options.content_size) |size| {
        try output.writer().writeInt(u64, size, .little);
    }

    // Header checksum
    const header_check = xxhash32(output.items[4..]) >> 8;
    try output.append(@truncate(header_check));

    // Compress blocks
    // ...

    // End mark
    try output.appendSlice(&[_]u8{ 0, 0, 0, 0 });

    // Content checksum (optional)
    if (options.content_checksum) {
        const checksum = xxhash32(input);
        try output.writer().writeInt(u32, checksum, .little);
    }

    return output.toOwnedSlice();
}
```

## Snappy Implementation

### Algorithm Overview

Snappy is similar to LZ4 but with different encoding:

```
1. Write uncompressed length as varint
2. Build hash table from 4-byte sequences
3. Emit literals and copies
4. Uses different tag format than LZ4
```

### Varint Encoding

Snappy uses varints for sizes:

```zig
fn writeVarint(writer: anytype, value: usize) !void {
    var v = value;
    while (v >= 128) {
        try writer.writeByte(@intCast((v & 0x7F) | 0x80));
        v >>= 7;
    }
    try writer.writeByte(@intCast(v));
}

fn readVarint(reader: anytype) !usize {
    var result: usize = 0;
    var shift: u6 = 0;

    while (true) {
        const b = try reader.readByte();
        result |= @as(usize, b & 0x7F) << shift;
        if (b & 0x80 == 0) break;
        shift += 7;
    }

    return result;
}
```

### Tag Encoding

Snappy has four tag types:

```zig
const TagType = enum(u2) {
    literal = 0b00,
    copy_1 = 0b01,  // 1-byte offset
    copy_2 = 0b10,  // 2-byte offset
    copy_4 = 0b11,  // 4-byte offset
};

fn emitLiteral(writer: anytype, data: []const u8) !void {
    const len = data.len - 1;  // Length - 1

    if (len < 60) {
        // Short literal: length in tag
        try writer.writeByte(@intCast(len << 2 | @intFromEnum(TagType.literal)));
    } else if (len < 256) {
        // 1-byte extended length
        try writer.writeByte(60 << 2 | @intFromEnum(TagType.literal));
        try writer.writeByte(@intCast(len));
    } else {
        // 2-byte extended length
        try writer.writeByte(61 << 2 | @intFromEnum(TagType.literal));
        try writer.writeInt(u16, @intCast(len), .little);
    }

    try writer.writeAll(data);
}

fn emitCopy(writer: anytype, offset: usize, length: usize) !void {
    const len = length - 4;  // Min match is 4

    if (len < 8 and offset < 2048) {
        // Copy with 1-byte offset (11 bits total)
        const tag: u16 = @intCast(
            @intFromEnum(TagType.copy_1) |
            ((len) << 2) |
            ((offset & 0x700) >> 3) |
            ((offset & 0xFF) << 8)
        );
        try writer.writeInt(u16, tag, .little);
    } else if (offset < 65536) {
        // Copy with 2-byte offset
        try writer.writeByte(@intCast(@intFromEnum(TagType.copy_2) | (len << 2)));
        try writer.writeInt(u16, @intCast(offset), .little);
    } else {
        // Copy with 4-byte offset
        try writer.writeByte(@intCast(@intFromEnum(TagType.copy_4) | (len << 2)));
        try writer.writeInt(u32, @intCast(offset), .little);
    }
}
```

### Framing Format

Snappy has a stream format for files:

```zig
const STREAM_IDENTIFIER = [_]u8{ 0xff, 0x06, 0x00, 0x00 } ++ "sNaPpY";

fn compressStream(input: []const u8, writer: anytype) !void {
    // Stream identifier
    try writer.writeAll(&STREAM_IDENTIFIER);

    // Compress in chunks
    var offset: usize = 0;
    while (offset < input.len) {
        const chunk_size = @min(65536, input.len - offset);
        const chunk = input[offset..][0..chunk_size];

        // Compress chunk
        const compressed = try compressBlock(chunk);

        // Write compressed chunk
        try writer.writeByte(0x00);  // Compressed data chunk
        try writer.writeInt(u24, compressed.len + 4, .little);

        // CRC32C masked
        const crc = crc32c(chunk);
        const masked = ((crc >> 15) | (crc << 17)) +% 0xa282ead8;
        try writer.writeInt(u32, masked, .little);

        try writer.writeAll(compressed);

        offset += chunk_size;
    }
}
```

## Performance Techniques

### Branch Prediction

Help the CPU predict branches:

```zig
// Common case: no match
if (candidate == 0) {
    // emit literal (likely path)
    @setCold(false);
} else {
    // check for match (less likely)
}
```

### Memory Access Patterns

Access memory sequentially when possible:

```zig
// Good: Sequential access
for (input) |byte| {
    process(byte);
}

// Bad: Random access
for (indices) |i| {
    process(input[i]);
}
```

### Inlining

Force inlining for hot functions:

```zig
inline fn hash(v: u32) u32 {
    return (v *% 2654435761) >> (32 - HASH_LOG);
}
```

## Testing

### Round-Trip Tests

```zig
test "lz4 round trip" {
    const cz = @import("compressionz");

    const cases = [_][]const u8{
        "",
        "a",
        "hello",
        "aaaaaaaaaaaaaaaaaaaaaaaa",
        @embedFile("testdata/mixed.bin"),
    };

    for (cases) |input| {
        const compressed = try cz.lz4.block.compress(input, testing.allocator);
        defer testing.allocator.free(compressed);

        const decompressed = try cz.lz4.block.decompressWithSize(compressed, input.len, testing.allocator);
        defer testing.allocator.free(decompressed);

        try testing.expectEqualSlices(u8, input, decompressed);
    }
}
```

### Compatibility Tests

```zig
test "compatible with reference implementation" {
    const cz = @import("compressionz");

    // Data compressed by reference lz4
    const reference_compressed = @embedFile("testdata/ref_lz4.bin");
    const expected = @embedFile("testdata/original.bin");

    const decompressed = try cz.lz4.frame.decompress(reference_compressed, testing.allocator, .{});
    defer testing.allocator.free(decompressed);

    try testing.expectEqualSlices(u8, expected, decompressed);
}
```

## Format Specifications

- [LZ4 Block Format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md)
- [LZ4 Frame Format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md)
- [Snappy Format](https://github.com/google/snappy/blob/main/format_description.txt)

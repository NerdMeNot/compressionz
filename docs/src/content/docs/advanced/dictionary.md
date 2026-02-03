---
title: Dictionary Compression
description: Improve compression ratios for small data using dictionaries.
---

Dictionary compression dramatically improves compression ratios for small data with known patterns. This is especially useful for APIs, message formats, and structured data.

## How Dictionaries Work

Without a dictionary, compressors build patterns from scratch for each input. With a dictionary, they start with pre-computed patterns.

### Supported Codecs

| Codec | Dictionary Support |
|-------|-------------------|
| Zstd | Yes |
| Zlib | Yes |
| LZ4 | No |
| Snappy | No |
| Gzip | No |
| Brotli | No (has built-in static dict) |

## Basic Usage

### Zstd with Dictionary

```zig
const cz = @import("compressionz");

// Dictionary containing common patterns
const dictionary = @embedFile("my_dictionary.bin");

// Compress with dictionary
const compressed = try cz.zstd.compressWithDict(data, dictionary, allocator, .{});
defer allocator.free(compressed);

// Decompress with SAME dictionary
const decompressed = try cz.zstd.decompressWithDict(compressed, dictionary, allocator, .{});
defer allocator.free(decompressed);
```

### Zlib with Dictionary

```zig
const cz = @import("compressionz");

const dictionary = "common patterns in your data...";

// Compress with dictionary
const compressed = try cz.zlib.compressWithDict(data, dictionary, allocator, .{});
defer allocator.free(compressed);

// Decompress with same dictionary
const decompressed = try cz.zlib.decompressWithDict(compressed, dictionary, allocator, .{});
defer allocator.free(decompressed);
```

## Why Dictionary Compression?

### The Problem

Small data compresses poorly because:
- Not enough bytes to find patterns
- Huffman trees need bytes to build
- No context to exploit

### The Solution

A dictionary provides:
- Pre-computed common patterns
- Ready-to-use Huffman/entropy codes
- Instant context for compression

### Real-World Impact

| Data Size | Without Dict | With Dict | Improvement |
|-----------|--------------|-----------|-------------|
| 100 B | 105 B (larger!) | 45 B | 57% smaller |
| 500 B | 420 B | 180 B | 57% smaller |
| 1 KB | 780 B | 380 B | 51% smaller |
| 5 KB | 3.2 KB | 1.9 KB | 41% smaller |
| 50 KB | 28 KB | 24 KB | 14% smaller |

**Key insight:** Dictionary compression is most effective for small data (< 10 KB).

## Creating Dictionaries

### Manual Dictionary

For simple cases, create a dictionary with common patterns:

```zig
const json_dictionary =
    \\{"id":,"name":,"email":,"status":,"created_at":
    \\,"updated_at":,"type":"user","type":"admin"
    \\,"active":true,"active":false,"error":null
    \\,"message":"success","message":"error"
;

const compressed = try cz.zstd.compressWithDict(json_data, json_dictionary, allocator, .{});
```

### Trained Dictionary (Zstd)

For best results, train a dictionary on representative samples:

```bash
# Collect 1000+ representative samples
ls samples/*.json > files.txt

# Train dictionary (32 KB is a good size)
zstd --train --maxdict=32768 -o my_dictionary.bin $(cat files.txt)
```

Then use in Zig:

```zig
const dictionary = @embedFile("my_dictionary.bin");

const compressed = try cz.zstd.compressWithDict(data, dictionary, allocator, .{});
```

### Dictionary Size Guidelines

| Use Case | Recommended Size |
|----------|-----------------|
| JSON API responses | 16-32 KB |
| Log messages | 32-64 KB |
| Protocol buffers | 8-16 KB |
| HTML templates | 64-128 KB |

Larger dictionaries provide diminishing returns and increase memory usage.

## Use Cases

### API Responses

```zig
const cz = @import("compressionz");

// Pre-loaded dictionary for API responses
const api_dict = @embedFile("api_dictionary.bin");

pub fn compressResponse(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return cz.zstd.compressWithDict(data, api_dict, allocator, .{});
}

pub fn decompressRequest(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return cz.zstd.decompressWithDict(data, api_dict, allocator, .{});
}
```

### Message Queues

```zig
const cz = @import("compressionz");

const MessageCompressor = struct {
    dictionary: []const u8,
    allocator: std.mem.Allocator,

    pub fn compress(self: *MessageCompressor, message: []const u8) ![]u8 {
        return cz.zstd.compressWithDict(message, self.dictionary, self.allocator, .{});
    }

    pub fn decompress(self: *MessageCompressor, compressed: []const u8) ![]u8 {
        return cz.zstd.decompressWithDict(compressed, self.dictionary, self.allocator, .{});
    }
};
```

### Database Records

```zig
const cz = @import("compressionz");

pub fn storeRecord(db: *Database, key: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
    const compressed = try cz.zstd.compressWithDict(value, db.compression_dict, allocator, .{});
    defer allocator.free(compressed);

    try db.put(key, compressed);
}

pub fn loadRecord(db: *Database, key: []const u8, allocator: std.mem.Allocator) !?[]u8 {
    const compressed = db.get(key) orelse return null;

    return cz.zstd.decompressWithDict(compressed, db.compression_dict, allocator, .{});
}
```

## Dictionary Versioning

**Critical:** Decompression requires the exact same dictionary used for compression.

### Strategy 1: Single Global Dictionary

```zig
// Never change this dictionary (breaks existing data)
const DICTIONARY_V1 = @embedFile("dict_v1.bin");
```

### Strategy 2: Versioned Dictionaries

```zig
const dictionaries = struct {
    const v1: []const u8 = @embedFile("dict_v1.bin");
    const v2: []const u8 = @embedFile("dict_v2.bin");
    const v3: []const u8 = @embedFile("dict_v3.bin");
};

pub fn decompress(data: []const u8, version: u8, allocator: std.mem.Allocator) ![]u8 {
    const dict = switch (version) {
        1 => dictionaries.v1,
        2 => dictionaries.v2,
        3 => dictionaries.v3,
        else => return error.UnknownDictionaryVersion,
    };

    return cz.zstd.decompressWithDict(data, dict, allocator, .{});
}
```

### Strategy 3: Dictionary ID

Zstd dictionaries include a 32-bit ID:

```zig
fn getDictionaryId(dict: []const u8) u32 {
    // Zstd dictionary magic + ID at offset 4
    if (dict.len < 8) return 0;
    return std.mem.readInt(u32, dict[4..8], .little);
}
```

## Best Practices

### Do

- Train on representative samples
- Keep dictionaries versioned
- Store dictionary ID with compressed data
- Test decompression with dictionary
- Use for small, structured data

### Don't

- Change dictionaries after deployment
- Use random data as dictionary
- Over-size dictionaries (diminishing returns)
- Use for large data (> 50 KB)
- Forget to include dictionary in deployment

## Error Handling

```zig
const result = cz.zstd.decompressWithDict(data, possibly_wrong_dict, allocator, .{}) catch |err| switch (err) {
    error.DictionaryMismatch => {
        // Dictionary doesn't match compressed data
        std.debug.print("Wrong dictionary for this data\n", .{});
        return error.InvalidData;
    },
    error.InvalidData => {
        // Data corrupted or wrong format
        return error.InvalidData;
    },
    else => return err,
};
```

## Performance Impact

| Operation | Without Dict | With Dict | Overhead |
|-----------|--------------|-----------|----------|
| Compress | Baseline | +5-15% CPU | Dictionary lookup |
| Decompress | Baseline | +2-5% CPU | Dictionary copy |
| Memory | Baseline | +dict size | Dictionary storage |

The CPU overhead is typically worth the 30-60% size reduction for small data.

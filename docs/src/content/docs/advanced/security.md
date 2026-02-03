---
title: Security
description: Security considerations when using compression.
---

Compression libraries can be attack vectors if not used carefully. This guide covers security considerations and best practices.

## Decompression Bombs

A decompression bomb (zip bomb) is malicious compressed data that expands to an enormous size, causing denial of service.

### The Threat

```
Example: A 42 KB file that expands to 4.5 PB (petabytes)
```

Attackers use highly repetitive data that compresses extremely well:

```
Original: 4.5 PB of zeros
Compressed: ~42 KB
Expansion ratio: 100,000,000,000:1
```

### Protection

**Always use `max_output_size` for untrusted data:**

```zig
const cz = @import("compressionz");

pub fn safeDecompress(untrusted_data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return cz.gzip.decompress(untrusted_data, allocator, .{
        .max_output_size = 100 * 1024 * 1024,  // 100 MB limit
    });
}
```

### Recommended Limits

| Context | Limit | Rationale |
|---------|-------|-----------|
| User uploads | 10-100 MB | Reasonable file sizes |
| API requests | 1-10 MB | Prevent resource exhaustion |
| Config files | 1 MB | Configs are small |
| Log entries | 10 KB | Individual entries |
| Internal systems | Higher or none | Trusted sources |

### Example: HTTP Handler

```zig
const cz = @import("compressionz");

pub fn handleUpload(request: *Request, allocator: std.mem.Allocator) !Response {
    const content_encoding = request.headers.get("Content-Encoding");
    const body = request.body;

    const data = if (content_encoding) |encoding| blk: {
        if (std.mem.eql(u8, encoding, "gzip")) {
            break :blk cz.gzip.decompress(body, allocator, .{
                .max_output_size = 10 * 1024 * 1024,  // 10 MB
            }) catch |err| {
                if (err == error.OutputTooLarge) {
                    return Response.badRequest("Request too large");
                }
                return Response.badRequest("Invalid compressed data");
            };
        }
        break :blk body;
    } else body;

    // Process data...
}
```

## Input Validation

### Never Trust Compressed Data

Compressed data can be:
- Corrupted (accidental or malicious)
- Wrong format
- Truncated
- Crafted to exploit vulnerabilities

### Always Handle Errors

```zig
const result = cz.zstd.decompress(data, allocator, .{}) catch |err| switch (err) {
    error.InvalidData => {
        log.warn("Received invalid compressed data", .{});
        return error.BadInput;
    },
    error.ChecksumMismatch => {
        log.warn("Compressed data failed integrity check", .{});
        return error.CorruptedData;
    },
    error.OutputTooLarge => {
        log.warn("Decompression bomb detected", .{});
        return error.MaliciousInput;
    },
    error.UnexpectedEof => {
        log.warn("Truncated compressed data", .{});
        return error.IncompleteData;
    },
    else => {
        log.err("Unexpected decompression error: {}", .{err});
        return error.InternalError;
    },
};
```

## Timing Attacks

Compression ratios can leak information about plaintext content.

### The CRIME/BREACH Attack

If you compress data that includes:
1. A secret (e.g., session token)
2. Attacker-controlled input

The attacker can guess the secret by observing compressed size differences.

### Mitigation

**Don't compress data containing both secrets and user input:**

```zig
// DANGEROUS: Combines secret and user input
const bad_response = try std.fmt.allocPrint(allocator,
    "token={s}&user_input={s}", .{ secret_token, user_input }
);
const compressed = try cz.gzip.compress(bad_response, allocator, .{});
// Attacker can guess secret_token by varying user_input!

// SAFER: Compress separately or don't compress secrets
const response_data = try std.fmt.allocPrint(allocator,
    "data={s}", .{ user_input }
);
const compressed = try cz.gzip.compress(response_data, allocator, .{});
// Secret token sent via separate channel (e.g., cookie)
```

### Web Application Recommendations

1. Use random padding in responses
2. Don't compress pages with CSRF tokens and user input
3. Consider disabling compression for authenticated pages
4. Use per-request secrets that can't be guessed incrementally

## Memory Safety

compressionz is written in memory-safe Zig with vendored C libraries.

### Buffer Overflows

The C libraries (zstd, zlib, brotli) are mature and well-audited. However:

- Always use the latest versions (vendored versions are tested)
- Report any crashes to help improve safety

### Integer Overflows

Size calculations use safe Zig arithmetic:

```zig
// Zig catches overflow at runtime (in safe builds)
const size: usize = a +% b;  // Wrapping add (explicit)
const size: usize = a + b;   // Panics on overflow (default)
```

## Dictionary Security

If using dictionary compression:

### Don't Expose Dictionary Contents

Dictionaries may contain sensitive patterns from training data.

```zig
// Dictionary trained on user data
const dict = trainDictionary(user_messages);

// DANGEROUS: Sending dictionary to client
try sendToClient(dict);  // May leak private data patterns!

// SAFE: Keep dictionary server-side only
const compressed = try cz.zstd.compressWithDict(message, dict, allocator, .{});
try sendToClient(compressed);
```

### Version Dictionaries

Changing dictionaries can break decompression:

```zig
pub const DictVersion = enum(u8) {
    v1 = 1,
    v2 = 2,
    current = 2,
};

pub fn compress(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dict = dictionaries[@intFromEnum(DictVersion.current)];
    const compressed = try cz.zstd.compressWithDict(data, dict, allocator, .{});

    // Prefix with version for forward compatibility
    var result = try allocator.alloc(u8, 1 + compressed.len);
    result[0] = @intFromEnum(DictVersion.current);
    @memcpy(result[1..], compressed);
    return result;
}
```

## Secure Defaults

### Use Checksums

Enable checksums for data integrity:

```zig
// LZ4 frame with checksum (default)
const compressed = try cz.lz4.frame.compress(data, allocator, .{
    .content_checksum = true,  // Default
});

// Zstd includes checksum by default
const zstd = try cz.zstd.compress(data, allocator, .{});

// Gzip includes CRC32 by default
const gzip = try cz.gzip.compress(data, allocator, .{});
```

### Verify on Decompression

Checksums are verified automatically:

```zig
const result = cz.lz4.frame.decompress(data, allocator, .{}) catch |err| {
    if (err == error.ChecksumMismatch) {
        // Data was corrupted or tampered with
        return error.IntegrityCheckFailed;
    }
    return err;
};
```

## Security Checklist

- [ ] Set `max_output_size` for untrusted data
- [ ] Handle all decompression errors
- [ ] Don't compress secrets with user input
- [ ] Keep dictionaries private
- [ ] Enable checksums for data integrity
- [ ] Validate data after decompression
- [ ] Log security-relevant errors
- [ ] Keep compressionz updated

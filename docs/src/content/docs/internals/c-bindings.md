---
title: C Bindings
description: How compressionz wraps vendored C libraries.
---

compressionz vendors several C compression libraries. This page documents how they're integrated.

## Vendored Libraries

| Library | Version | Source | License |
|---------|---------|--------|---------|
| zstd | 1.5.7 | vendor/zstd/ | BSD |
| zlib | 1.3.1 | vendor/zlib/ | zlib |
| brotli | latest | vendor/brotli/ | MIT |

## Why Vendor?

**Benefits:**
- No system dependencies (`brew install`, `apt-get`, etc.)
- Reproducible builds
- Works on any Zig-supported platform
- Consistent behavior across systems

**Trade-offs:**
- Larger repository
- Must update manually for security fixes
- Compile time for C code

## C Import Pattern

All C bindings follow this pattern:

```zig
// Import C headers
const c = @cImport({
    @cInclude("library.h");
});

// Export Zig-friendly wrapper
pub fn compress(input: []const u8, allocator: Allocator, level: Level) ![]u8 {
    // ... wrapper implementation
}
```

## Zstd Bindings

### Import

```zig
// zstd.zig
const c = @cImport({
    @cDefine("ZSTD_STATIC_LINKING_ONLY", {});
    @cInclude("zstd.h");
});
```

### Compression

```zig
pub fn compress(input: []const u8, allocator: Allocator, level: Level) ![]u8 {
    // Calculate bound
    const bound = c.ZSTD_compressBound(input.len);
    if (c.ZSTD_isError(bound) != 0) return error.InvalidData;

    // Allocate output
    const output = try allocator.alloc(u8, bound);
    errdefer allocator.free(output);

    // Compress
    const result = c.ZSTD_compress(
        output.ptr,
        output.len,
        input.ptr,
        input.len,
        level.toZstdLevel(),
    );

    // Check for errors
    if (c.ZSTD_isError(result) != 0) {
        allocator.free(output);
        return mapZstdError(result);
    }

    // Shrink to actual size
    return allocator.realloc(output, result) catch output[0..result];
}
```

### Decompression

```zig
pub fn decompress(input: []const u8, allocator: Allocator) ![]u8 {
    // Get decompressed size from frame header
    const size = c.ZSTD_getFrameContentSize(input.ptr, input.len);

    if (size == c.ZSTD_CONTENTSIZE_ERROR) return error.InvalidData;
    if (size == c.ZSTD_CONTENTSIZE_UNKNOWN) {
        return decompressStreaming(input, allocator);
    }

    // Allocate output
    const output = try allocator.alloc(u8, size);
    errdefer allocator.free(output);

    // Decompress
    const result = c.ZSTD_decompress(
        output.ptr,
        output.len,
        input.ptr,
        input.len,
    );

    if (c.ZSTD_isError(result) != 0) {
        allocator.free(output);
        return mapZstdError(result);
    }

    return output;
}
```

### Dictionary Compression

```zig
pub fn compressWithDict(
    input: []const u8,
    allocator: Allocator,
    level: Level,
    dictionary: ?[]const u8,
) ![]u8 {
    const bound = c.ZSTD_compressBound(input.len);
    const output = try allocator.alloc(u8, bound);
    errdefer allocator.free(output);

    const result = if (dictionary) |dict|
        c.ZSTD_compress_usingDict(
            null,  // Use default context
            output.ptr,
            output.len,
            input.ptr,
            input.len,
            dict.ptr,
            dict.len,
            level.toZstdLevel(),
        )
    else
        c.ZSTD_compress(
            output.ptr,
            output.len,
            input.ptr,
            input.len,
            level.toZstdLevel(),
        );

    if (c.ZSTD_isError(result) != 0) {
        allocator.free(output);
        return mapZstdError(result);
    }

    return allocator.realloc(output, result) catch output[0..result];
}
```

## Zlib Bindings

### Import

```zig
// zlib_codec.zig
const c = @cImport({
    @cInclude("zlib.h");
});
```

### Compression

```zig
pub fn compress(
    input: []const u8,
    allocator: Allocator,
    level: Level,
    format: Format,
) ![]u8 {
    // Initialize stream
    var stream: c.z_stream = undefined;
    stream.zalloc = null;
    stream.zfree = null;
    stream.opaque = null;

    const window_bits: c_int = switch (format) {
        .deflate => -15,      // Raw deflate
        .zlib => 15,          // Zlib header
        .gzip => 15 + 16,     // Gzip header
    };

    if (c.deflateInit2(
        &stream,
        level.toZlibLevel(),
        c.Z_DEFLATED,
        window_bits,
        8,
        c.Z_DEFAULT_STRATEGY,
    ) != c.Z_OK) {
        return error.InvalidData;
    }
    defer _ = c.deflateEnd(&stream);

    // Calculate bound
    const bound = c.deflateBound(&stream, input.len);
    const output = try allocator.alloc(u8, bound);
    errdefer allocator.free(output);

    // Compress
    stream.next_in = input.ptr;
    stream.avail_in = @intCast(input.len);
    stream.next_out = output.ptr;
    stream.avail_out = @intCast(output.len);

    const result = c.deflate(&stream, c.Z_FINISH);
    if (result != c.Z_STREAM_END) {
        allocator.free(output);
        return error.InvalidData;
    }

    const written = output.len - stream.avail_out;
    return allocator.realloc(output, written) catch output[0..written];
}
```

### Decompression

```zig
pub fn decompress(
    input: []const u8,
    allocator: Allocator,
    format: Format,
) ![]u8 {
    var stream: c.z_stream = undefined;
    stream.zalloc = null;
    stream.zfree = null;
    stream.opaque = null;
    stream.next_in = input.ptr;
    stream.avail_in = @intCast(input.len);

    const window_bits: c_int = switch (format) {
        .deflate => -15,
        .zlib => 15,
        .gzip => 15 + 32,  // Auto-detect gzip or zlib
    };

    if (c.inflateInit2(&stream, window_bits) != c.Z_OK) {
        return error.InvalidData;
    }
    defer _ = c.inflateEnd(&stream);

    // Dynamic output buffer
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var buf: [65536]u8 = undefined;

    while (true) {
        stream.next_out = &buf;
        stream.avail_out = buf.len;

        const result = c.inflate(&stream, c.Z_NO_FLUSH);

        const have = buf.len - stream.avail_out;
        try output.appendSlice(buf[0..have]);

        if (result == c.Z_STREAM_END) break;
        if (result != c.Z_OK) return error.InvalidData;
    }

    return output.toOwnedSlice();
}
```

## Brotli Bindings

### Import

```zig
// brotli.zig
const c = @cImport({
    @cInclude("brotli/encode.h");
    @cInclude("brotli/decode.h");
});
```

### Compression

```zig
pub fn compress(input: []const u8, allocator: Allocator, level: Level) ![]u8 {
    // Calculate bound
    var output_size = c.BrotliEncoderMaxCompressedSize(input.len);
    if (output_size == 0) output_size = input.len + 1024;

    const output = try allocator.alloc(u8, output_size);
    errdefer allocator.free(output);

    // Compress
    const quality: c_int = switch (level) {
        .fastest => 0,
        .fast => 2,
        .default => 6,
        .better => 9,
        .best => 11,
    };

    var encoded_size = output_size;
    const result = c.BrotliEncoderCompress(
        quality,
        c.BROTLI_DEFAULT_WINDOW,
        c.BROTLI_DEFAULT_MODE,
        input.len,
        input.ptr,
        &encoded_size,
        output.ptr,
    );

    if (result != c.BROTLI_TRUE) {
        allocator.free(output);
        return error.InvalidData;
    }

    return allocator.realloc(output, encoded_size) catch output[0..encoded_size];
}
```

### Decompression

```zig
pub fn decompress(input: []const u8, allocator: Allocator) ![]u8 {
    const state = c.BrotliDecoderCreateInstance(null, null, null);
    if (state == null) return error.OutOfMemory;
    defer c.BrotliDecoderDestroyInstance(state);

    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var available_in = input.len;
    var next_in: [*]const u8 = input.ptr;
    var buf: [65536]u8 = undefined;

    while (true) {
        var available_out = buf.len;
        var next_out: [*]u8 = &buf;

        const result = c.BrotliDecoderDecompressStream(
            state,
            &available_in,
            &next_in,
            &available_out,
            &next_out,
            null,
        );

        const have = buf.len - available_out;
        try output.appendSlice(buf[0..have]);

        if (result == c.BROTLI_DECODER_RESULT_SUCCESS) break;
        if (result == c.BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT) continue;
        if (result == c.BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT) {
            return error.UnexpectedEof;
        }
        return error.InvalidData;
    }

    return output.toOwnedSlice();
}
```

## Error Mapping

Each library has its own error codes. We map them to our unified type:

```zig
fn mapZstdError(code: usize) Error {
    const err = c.ZSTD_getErrorCode(code);
    return switch (err) {
        c.ZSTD_error_memory_allocation => error.OutOfMemory,
        c.ZSTD_error_dstSize_tooSmall => error.OutputTooSmall,
        c.ZSTD_error_corruption_detected => error.InvalidData,
        c.ZSTD_error_checksum_wrong => error.ChecksumMismatch,
        c.ZSTD_error_dictionary_wrong => error.DictionaryMismatch,
        else => error.InvalidData,
    };
}

fn mapZlibError(code: c_int) Error {
    return switch (code) {
        c.Z_MEM_ERROR => error.OutOfMemory,
        c.Z_DATA_ERROR => error.InvalidData,
        c.Z_BUF_ERROR => error.OutputTooSmall,
        else => error.InvalidData,
    };
}
```

## Build Integration

### build.zig

```zig
pub fn build(b: *std.Build) void {
    const lib = b.addStaticLibrary(.{
        .name = "compressionz",
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Zstd
    lib.addCSourceFiles(.{
        .files = &zstd_sources,
        .flags = &.{ "-DZSTD_MULTITHREAD=1" },
    });
    lib.addIncludePath(.{ .path = "vendor/zstd/lib" });

    // Zlib
    lib.addCSourceFiles(.{
        .files = &zlib_sources,
        .flags = &.{},
    });
    lib.addIncludePath(.{ .path = "vendor/zlib" });

    // Brotli
    lib.addCSourceFiles(.{
        .files = &brotli_sources,
        .flags = &.{ "-DBROTLI_BUILD_PORTABLE" },
    });
    lib.addIncludePath(.{ .path = "vendor/brotli/include" });

    lib.linkLibC();
}
```

## Updating Vendored Libraries

To update a vendored library:

1. Download new version
2. Replace files in `vendor/`
3. Update version in documentation
4. Run tests: `zig build test`
5. Run benchmarks: `zig build bench -Doptimize=ReleaseFast`

Always test thoroughly after updates — API or behavior changes can break things.

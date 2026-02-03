---
title: Installation
description: Add compressionz to your Zig project.
---

compressionz can be added to any Zig project using the standard build system.

## Requirements

- **Zig 0.15.0** or later
- No additional system dependencies

## Installation via build.zig.zon

### Step 1: Add the Dependency

Add compressionz to your `build.zig.zon`:

```zig title="build.zig.zon"
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .compressionz = .{
            .url = "https://github.com/NerdMeNot/compressionz/archive/refs/tags/v1.0.0-zig0.15.2.tar.gz",
            .hash = "1220...", // Zig will tell you this on first build
        },
    },
    .paths = .{"."},
}
```

For local development, use a path dependency:

```zig title="build.zig.zon"
.dependencies = .{
    .compressionz = .{
        .path = "../compressionz",
    },
},
```

### Step 2: Configure build.zig

Add compressionz to your build configuration:

```zig title="build.zig"
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get compressionz dependency
    const compressionz = b.dependency("compressionz", .{
        .target = target,
        .optimize = optimize,
    });

    // Create your executable
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add compressionz module
    exe.root_module.addImport("compressionz", compressionz.module("compressionz"));

    b.installArtifact(exe);
}
```

### Step 3: Import and Use

```zig title="src/main.zig"
const std = @import("std");
const cz = @import("compressionz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const data = "Hello, compressionz!";

    const compressed = try cz.zstd.compress(data, allocator, .{});
    defer allocator.free(compressed);

    std.debug.print("Compressed {} bytes to {} bytes\n", .{
        data.len,
        compressed.len,
    });
}
```

### Step 4: Build

```bash
# Build your project
zig build

# Run your project
zig build run
```

## Verifying Installation

Create a simple test file to verify everything works:

```zig title="src/verify.zig"
const std = @import("std");
const cz = @import("compressionz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "The quick brown fox jumps over the lazy dog.";

    // Test Zstd
    {
        const compressed = try cz.zstd.compress(original, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        std.debug.print("Zstd: {d} -> {d} bytes\n", .{ original.len, compressed.len });
        std.debug.assert(std.mem.eql(u8, original, decompressed));
    }

    // Test LZ4
    {
        const compressed = try cz.lz4.frame.compress(original, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        std.debug.print("LZ4: {d} -> {d} bytes\n", .{ original.len, compressed.len });
        std.debug.assert(std.mem.eql(u8, original, decompressed));
    }

    // Test Snappy
    {
        const compressed = try cz.snappy.compress(original, allocator);
        defer allocator.free(compressed);
        const decompressed = try cz.snappy.decompress(compressed, allocator);
        defer allocator.free(decompressed);
        std.debug.print("Snappy: {d} -> {d} bytes\n", .{ original.len, compressed.len });
        std.debug.assert(std.mem.eql(u8, original, decompressed));
    }

    // Test Gzip
    {
        const compressed = try cz.gzip.compress(original, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        std.debug.print("Gzip: {d} -> {d} bytes\n", .{ original.len, compressed.len });
        std.debug.assert(std.mem.eql(u8, original, decompressed));
    }

    // Test Brotli
    {
        const compressed = try cz.brotli.compress(original, allocator, .{});
        defer allocator.free(compressed);
        const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        std.debug.print("Brotli: {d} -> {d} bytes\n", .{ original.len, compressed.len });
        std.debug.assert(std.mem.eql(u8, original, decompressed));
    }

    std.debug.print("\nAll codecs working correctly!\n", .{});
}
```

Expected output:

```
Zstd: 44 -> 53 bytes
LZ4: 44 -> 63 bytes
Snappy: 44 -> 46 bytes
Gzip: 44 -> 64 bytes
Brotli: 44 -> 48 bytes

All codecs working correctly!
```

## Build Optimization

For production builds, always use release optimizations:

```bash
# Development (debug)
zig build

# Production (optimized)
zig build -Doptimize=ReleaseFast

# Smaller binary
zig build -Doptimize=ReleaseSmall

# Safe release (keeps safety checks)
zig build -Doptimize=ReleaseSafe
```

Performance difference is significant:

| Mode | LZ4 Compression | Zstd Compression |
|------|-----------------|------------------|
| Debug | ~500 MB/s | ~200 MB/s |
| ReleaseFast | ~36 GB/s | ~12 GB/s |

## Troubleshooting

### Hash Mismatch

If you see a hash mismatch error:

```
error: hash mismatch
expected: 1220abc...
found:    1220def...
```

Update your `build.zig.zon` with the correct hash shown in the error.

### Missing Dependency

If the build can't find compressionz:

```
error: unable to find dependency 'compressionz'
```

1. Check your `build.zig.zon` spelling
2. Ensure the URL or path is correct
3. Run `zig build` again to fetch dependencies

### C Compilation Errors

compressionz vendors C libraries. If you see C compilation errors:

1. Ensure you're using Zig 0.15.0+
2. Check your target is supported
3. File an issue with the full error output

## Next Steps

Now that compressionz is installed:

1. [Quick Start Guide](/getting-started/quick-start/) — Learn basic usage
2. [Choosing a Codec](/getting-started/choosing-a-codec/) — Pick the right algorithm
3. [API Reference](/api/compression/) — Full API documentation

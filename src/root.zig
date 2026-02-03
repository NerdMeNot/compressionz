//! compressionz - A fast, ergonomic compression library for Zig
//!
//! Each codec has its own module with a consistent API tailored to its capabilities.
//!
//! ## Quick Start
//! ```zig
//! const cz = @import("compressionz");
//!
//! // One-shot compression
//! const compressed = try cz.zstd.compress(input, allocator, .{});
//! defer allocator.free(compressed);
//!
//! const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
//! defer allocator.free(decompressed);
//! ```
//!
//! ## Streaming API
//! ```zig
//! // Streaming compression
//! var comp = try cz.gzip.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
//! defer comp.deinit();
//! try comp.writer().writeAll(data);
//! try comp.finish();
//!
//! // Streaming decompression
//! var decomp = try cz.gzip.Decompressor(@TypeOf(reader)).init(allocator, reader);
//! defer decomp.deinit();
//! const data = try decomp.reader().readAllAlloc(allocator, max_size);
//! ```
//!
//! ## Available Codecs
//!
//! | Module | Features | Best For |
//! |--------|----------|----------|
//! | `lz4.frame` | Streaming, in-place | Fast compression with framing |
//! | `lz4.block` | In-place only | Raw blocks (size must be known) |
//! | `snappy` | In-place only | Speed-focused, Google format |
//! | `zstd` | Streaming, dictionary | Best ratio/speed balance |
//! | `gzip` | Streaming | Web, Unix compatibility |
//! | `zlib` | Streaming, dictionary | Library interchange |
//! | `brotli` | Streaming | Web assets, high compression |
//!
//! ## Format Detection
//! ```zig
//! const format = cz.detect(data);
//! switch (format) {
//!     .gzip => // use cz.gzip
//!     .zstd => // use cz.zstd
//!     // ...
//! }
//! ```

const std = @import("std");

// Codec modules - each with its own API
pub const lz4 = @import("lz4/lz4.zig");
pub const snappy = @import("snappy/snappy.zig");
pub const zstd = @import("zstd.zig");
pub const gzip = @import("gzip.zig");
pub const zlib = @import("zlib_codec.zig");
pub const brotli = @import("brotli.zig");

// Archive formats
pub const archive = @import("archive/archive.zig");

// Shared types
pub const Level = @import("level.zig").Level;
pub const Error = @import("error.zig").Error;

// Format detection
pub const Format = @import("format.zig").Format;
pub const detect = @import("format.zig").detect;

// Tests
test {
    _ = @import("format.zig");
    _ = @import("level.zig");
    _ = @import("error.zig");
    _ = @import("lz4/lz4.zig");
    _ = @import("snappy/snappy.zig");
    _ = @import("zstd.zig");
    _ = @import("gzip.zig");
    _ = @import("zlib_codec.zig");
    _ = @import("brotli.zig");
    _ = @import("archive/archive.zig");
}

test "lz4 frame compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, compressionz! This is a test of the LZ4 compression algorithm.";

    const compressed = try lz4.frame.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try lz4.frame.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "lz4 block compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, compressionz! This is a test of LZ4 raw block compression.";

    const compressed = try lz4.block.compress(input, allocator);
    defer allocator.free(compressed);

    // LZ4 block requires known size for decompression
    const decompressed = try lz4.block.decompressWithSize(compressed, input.len, allocator);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "snappy compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, compressionz! This is a test of the Snappy compression algorithm.";

    const compressed = try snappy.compress(input, allocator);
    defer allocator.free(compressed);

    const decompressed = try snappy.decompress(compressed, allocator);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "zstd compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, compressionz! This is a test of the Zstd compression algorithm.";

    const compressed = try zstd.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try zstd.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "gzip compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, compressionz! This is a test of the Gzip compression algorithm.";

    const compressed = try gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try gzip.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "zlib compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, compressionz! This is a test of the Zlib compression algorithm.";

    const compressed = try zlib.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try zlib.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "brotli compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, compressionz! This is a test of the Brotli compression algorithm.";

    const compressed = try brotli.compress(input, allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try brotli.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "format detection" {
    // LZ4 frame magic
    const lz4_data = [_]u8{ 0x04, 0x22, 0x4D, 0x18, 0x00, 0x00 };
    try std.testing.expectEqual(Format.lz4, detect(&lz4_data));

    // Gzip magic
    const gzip_data = [_]u8{ 0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00 };
    try std.testing.expectEqual(Format.gzip, detect(&gzip_data));

    // Zstd magic
    const zstd_data = [_]u8{ 0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x00 };
    try std.testing.expectEqual(Format.zstd, detect(&zstd_data));
}

test "max_output_size prevents decompression bombs" {
    const allocator = std.testing.allocator;
    const input = "Test data for max_output_size testing. " ** 10;

    // Test with zstd
    {
        const compressed = try zstd.compress(input, allocator, .{});
        defer allocator.free(compressed);

        // Should succeed with no limit
        const decompressed = try zstd.decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);
        try std.testing.expectEqualStrings(input, decompressed);

        // Should fail with small limit
        const result = zstd.decompress(compressed, allocator, .{ .max_output_size = 10 });
        try std.testing.expectError(Error.OutputTooLarge, result);
    }

    // Test with gzip
    {
        const compressed = try gzip.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const result = gzip.decompress(compressed, allocator, .{ .max_output_size = 10 });
        try std.testing.expectError(Error.OutputTooLarge, result);
    }

    // Test with brotli
    {
        const compressed = try brotli.compress(input, allocator, .{});
        defer allocator.free(compressed);

        const result = brotli.decompress(compressed, allocator, .{ .max_output_size = 10 });
        try std.testing.expectError(Error.OutputTooLarge, result);
    }
}

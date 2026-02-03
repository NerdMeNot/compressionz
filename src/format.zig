//! Format detection utilities.
//!
//! Use `detect()` to identify the compression format from magic bytes,
//! then use the appropriate codec module directly.

const std = @import("std");

/// Detected compression formats.
pub const Format = enum {
    lz4,
    zstd,
    gzip,
    zlib,
    brotli,
    snappy,
    unknown,

    /// Get human-readable name.
    pub fn name(self: Format) []const u8 {
        return switch (self) {
            .lz4 => "LZ4",
            .zstd => "Zstandard",
            .gzip => "Gzip",
            .zlib => "Zlib",
            .brotli => "Brotli",
            .snappy => "Snappy",
            .unknown => "Unknown",
        };
    }

    /// Get typical file extension.
    pub fn extension(self: Format) []const u8 {
        return switch (self) {
            .lz4 => ".lz4",
            .zstd => ".zst",
            .gzip => ".gz",
            .zlib => ".zz",
            .brotli => ".br",
            .snappy => ".snappy",
            .unknown => "",
        };
    }
};

/// Detect compression format from magic bytes.
/// Returns `.unknown` if format cannot be detected.
///
/// Note: Some formats like Brotli and raw deflate don't have magic bytes
/// and cannot be detected this way.
pub fn detect(data: []const u8) Format {
    if (data.len < 2) return .unknown;

    // LZ4 frame magic: 0x184D2204
    if (data.len >= 4 and
        data[0] == 0x04 and data[1] == 0x22 and
        data[2] == 0x4D and data[3] == 0x18)
    {
        return .lz4;
    }

    // Zstd magic: 0xFD2FB528
    if (data.len >= 4 and
        data[0] == 0x28 and data[1] == 0xB5 and
        data[2] == 0x2F and data[3] == 0xFD)
    {
        return .zstd;
    }

    // Gzip magic: 0x1F8B
    if (data[0] == 0x1F and data[1] == 0x8B) {
        return .gzip;
    }

    // Zlib magic: first byte has bits 0-3 = 8 (deflate), CMF*256+FLG divisible by 31
    const cmf = data[0];
    const flg = data[1];
    if ((cmf & 0x0F) == 8 and (@as(u16, cmf) * 256 + flg) % 31 == 0) {
        return .zlib;
    }

    // Snappy framed format magic: "sNaPpY"
    if (data.len >= 6 and std.mem.eql(u8, data[0..6], "sNaPpY")) {
        return .snappy;
    }

    // Brotli doesn't have magic bytes, cannot detect

    return .unknown;
}

// Tests
test "format detection" {
    // LZ4 frame
    const lz4_magic = [_]u8{ 0x04, 0x22, 0x4D, 0x18 };
    try std.testing.expectEqual(Format.lz4, detect(&lz4_magic));

    // Zstd
    const zstd_magic = [_]u8{ 0x28, 0xB5, 0x2F, 0xFD };
    try std.testing.expectEqual(Format.zstd, detect(&zstd_magic));

    // Gzip
    const gzip_magic = [_]u8{ 0x1F, 0x8B };
    try std.testing.expectEqual(Format.gzip, detect(&gzip_magic));

    // Unknown
    const unknown = [_]u8{ 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectEqual(Format.unknown, detect(&unknown));
}

test "format names" {
    try std.testing.expectEqualStrings("LZ4", Format.lz4.name());
    try std.testing.expectEqualStrings("Zstandard", Format.zstd.name());
    try std.testing.expectEqualStrings("Gzip", Format.gzip.name());
}

test "format extensions" {
    try std.testing.expectEqualStrings(".lz4", Format.lz4.extension());
    try std.testing.expectEqualStrings(".gz", Format.gzip.extension());
    try std.testing.expectEqualStrings(".zst", Format.zstd.extension());
}

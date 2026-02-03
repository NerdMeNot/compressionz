//! LZ4 compression and decompression.
//!
//! Supports both block format (raw LZ4) and frame format (with headers and checksums).
//!
//! ## Block Format
//! Raw LZ4 compressed data without any framing. You must know the
//! decompressed size to decompress.
//!
//! ## Frame Format (Recommended)
//! LZ4 frame format includes:
//! - Magic number for detection
//! - Frame descriptor with flags
//! - Optional content size
//! - Data blocks with checksums
//! - End marker and content checksum

const std = @import("std");
const Error = @import("../error.zig").Error;
const Level = @import("../level.zig").Level;

pub const block = @import("block.zig");
pub const frame = @import("frame.zig");

/// LZ4 frame format options.
pub const FrameOptions = struct {
    block_size: BlockSize = .default,
    block_mode: BlockMode = .linked,
    content_checksum: bool = true,
    content_size: ?usize = null,
    dictionary_id: ?u32 = null,
    level: Level = .default,
};

/// Block size for LZ4 frame format.
pub const BlockSize = enum(u3) {
    @"64KB" = 4,
    @"256KB" = 5,
    @"1MB" = 6,
    @"4MB" = 7,

    pub const default = BlockSize.@"64KB";

    pub fn bytes(self: BlockSize) usize {
        // LZ4 frame format: blockSizeID 4 = 64KB, 5 = 256KB, 6 = 1MB, 7 = 4MB
        // 64KB = 2^16, 256KB = 2^18, 1MB = 2^20, 4MB = 2^22
        // Formula: 2^(8 + 2*blockSizeID) = 2^(8 + 2*4) = 2^16 for 64KB
        return @as(usize, 1) << (@as(u5, @intFromEnum(self)) * 2 + 8);
    }
};

/// Block mode for LZ4 frame format.
pub const BlockMode = enum(u1) {
    linked = 0, // Blocks can reference previous blocks
    independent = 1, // Each block is independent
};

test {
    _ = block;
    _ = frame;
}

test "block size bytes" {
    try std.testing.expectEqual(@as(usize, 64 * 1024), BlockSize.@"64KB".bytes());
    try std.testing.expectEqual(@as(usize, 256 * 1024), BlockSize.@"256KB".bytes());
    try std.testing.expectEqual(@as(usize, 1024 * 1024), BlockSize.@"1MB".bytes());
    try std.testing.expectEqual(@as(usize, 4 * 1024 * 1024), BlockSize.@"4MB".bytes());
}

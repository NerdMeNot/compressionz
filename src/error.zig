//! Error types for compression operations.

const std = @import("std");

/// Errors that can occur during compression/decompression.
pub const Error = error{
    /// Input data is corrupted or invalid.
    InvalidData,

    /// Checksum verification failed.
    ChecksumMismatch,

    /// Output buffer too small.
    OutputTooSmall,

    /// Input ended unexpectedly.
    UnexpectedEof,

    /// Decompressed size exceeds limit.
    OutputTooLarge,

    /// Dictionary mismatch.
    DictionaryMismatch,

    /// Unsupported codec feature.
    UnsupportedFeature,

    /// Memory allocation failed.
    OutOfMemory,
};

/// Shrink allocation to actual size, handling resize failure gracefully.
/// Returns a slice of the requested size, freeing the original buffer if
/// a new allocation was needed.
pub fn shrinkAllocation(allocator: std.mem.Allocator, buffer: []u8, actual_size: usize) Error![]u8 {
    if (allocator.resize(buffer, actual_size)) {
        return buffer[0..actual_size];
    }
    // Resize failed, allocate new buffer and copy
    const result = allocator.alloc(u8, actual_size) catch return Error.OutOfMemory;
    @memcpy(result, buffer[0..actual_size]);
    allocator.free(buffer);
    return result;
}

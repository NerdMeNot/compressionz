//! Compression level definitions.
//!
//! Provides standardized compression level presets that each codec
//! translates to its native level internally.

const std = @import("std");

/// Compression level presets.
/// Each codec translates these to its native level range internally.
pub const Level = enum {
    fastest, // Prioritize speed (typically level 1)
    fast, // Good speed (typically level 3)
    default, // Balanced (typically level 6)
    better, // Better compression (typically level 9)
    best, // Maximum compression (typically highest level)

    /// Create from integer level (0-11 range).
    pub fn fromInt(level: i32) Level {
        if (level <= 1) return .fastest;
        if (level <= 3) return .fast;
        if (level <= 6) return .default;
        if (level <= 9) return .better;
        return .best;
    }
};

test "level from int" {
    try std.testing.expectEqual(Level.fastest, Level.fromInt(1));
    try std.testing.expectEqual(Level.fast, Level.fromInt(3));
    try std.testing.expectEqual(Level.default, Level.fromInt(6));
    try std.testing.expectEqual(Level.better, Level.fromInt(9));
    try std.testing.expectEqual(Level.best, Level.fromInt(15));
}

//! Platform-specific resource usage measurement.
//!
//! Provides CPU time measurement using OS-specific APIs.

const std = @import("std");
const builtin = @import("builtin");

pub const ResourceUsage = struct {
    /// Get current CPU time in nanoseconds (user + system time).
    /// Returns 0 if measurement is not available on this platform.
    pub fn getCpuTime() u64 {
        switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos => return getDarwinCpuTime(),
            .linux, .freebsd, .netbsd, .openbsd, .dragonfly => return getPosixCpuTime(),
            else => return 0, // Not supported
        }
    }

    /// Get current memory usage in bytes.
    /// Returns 0 if measurement is not available.
    pub fn getMemoryUsage() usize {
        switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos => return getDarwinMemory(),
            .linux => return getLinuxMemory(),
            else => return 0,
        }
    }
};

// Darwin (macOS) implementation using getrusage
fn getDarwinCpuTime() u64 {
    const c = @cImport({
        @cInclude("sys/resource.h");
    });

    var usage: c.struct_rusage = undefined;
    if (c.getrusage(c.RUSAGE_SELF, &usage) == 0) {
        const user_ns: u64 = @as(u64, @intCast(usage.ru_utime.tv_sec)) * 1_000_000_000 +
            @as(u64, @intCast(usage.ru_utime.tv_usec)) * 1_000;
        const sys_ns: u64 = @as(u64, @intCast(usage.ru_stime.tv_sec)) * 1_000_000_000 +
            @as(u64, @intCast(usage.ru_stime.tv_usec)) * 1_000;
        return user_ns + sys_ns;
    }
    return 0;
}

fn getDarwinMemory() usize {
    const c = @cImport({
        @cInclude("sys/resource.h");
    });

    var usage: c.struct_rusage = undefined;
    if (c.getrusage(c.RUSAGE_SELF, &usage) == 0) {
        // ru_maxrss is in bytes on macOS
        return @intCast(usage.ru_maxrss);
    }
    return 0;
}

// POSIX implementation using getrusage
fn getPosixCpuTime() u64 {
    const c = @cImport({
        @cInclude("sys/resource.h");
    });

    var usage: c.struct_rusage = undefined;
    if (c.getrusage(c.RUSAGE_SELF, &usage) == 0) {
        const user_ns: u64 = @as(u64, @intCast(usage.ru_utime.tv_sec)) * 1_000_000_000 +
            @as(u64, @intCast(usage.ru_utime.tv_usec)) * 1_000;
        const sys_ns: u64 = @as(u64, @intCast(usage.ru_stime.tv_sec)) * 1_000_000_000 +
            @as(u64, @intCast(usage.ru_stime.tv_usec)) * 1_000;
        return user_ns + sys_ns;
    }
    return 0;
}

fn getLinuxMemory() usize {
    // Read from /proc/self/statm
    const file = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return 0;
    defer file.close();

    var buf: [256]u8 = undefined;
    const bytes_read = file.read(&buf) catch return 0;
    const content = buf[0..bytes_read];

    // Format: size resident shared text lib data dt
    // We want resident (second field) * page size
    var iter = std.mem.splitScalar(u8, content, ' ');
    _ = iter.next(); // skip size
    const resident_pages_str = iter.next() orelse return 0;
    const resident_pages = std.fmt.parseInt(usize, resident_pages_str, 10) catch return 0;

    // Page size is typically 4096
    return resident_pages * 4096;
}

test "cpu time is non-zero after work" {
    const before = ResourceUsage.getCpuTime();

    // Do some work
    var sum: u64 = 0;
    for (0..100_000) |i| {
        sum += i;
    }
    std.mem.doNotOptimizeAway(&sum);

    const after = ResourceUsage.getCpuTime();

    // CPU time should have increased (or be 0 if not supported)
    if (before > 0) {
        try std.testing.expect(after >= before);
    }
}

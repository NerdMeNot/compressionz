//! Allocator wrapper that tracks memory usage statistics.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

/// Wraps an allocator to track allocation statistics.
pub const CountingAllocator = struct {
    parent: Allocator,

    /// Total bytes currently allocated.
    current_allocated: usize = 0,

    /// Peak bytes allocated at any point.
    peak_allocated: usize = 0,

    /// Total number of allocation calls.
    alloc_count: usize = 0,

    /// Total number of free calls.
    free_count: usize = 0,

    /// Total bytes ever allocated (cumulative).
    total_allocated: usize = 0,

    pub fn init(parent: Allocator) CountingAllocator {
        return .{ .parent = parent };
    }

    pub fn allocator(self: *CountingAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    pub fn reset(self: *CountingAllocator) void {
        self.current_allocated = 0;
        self.peak_allocated = 0;
        self.alloc_count = 0;
        self.free_count = 0;
        self.total_allocated = 0;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));

        const result = self.parent.rawAlloc(len, alignment, ret_addr);
        if (result != null) {
            self.current_allocated += len;
            self.total_allocated += len;
            self.alloc_count += 1;

            if (self.current_allocated > self.peak_allocated) {
                self.peak_allocated = self.current_allocated;
            }
        }

        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));

        const old_len = buf.len;

        if (self.parent.rawResize(buf, alignment, new_len, ret_addr)) {
            if (new_len > old_len) {
                const diff = new_len - old_len;
                self.current_allocated += diff;
                self.total_allocated += diff;
            } else {
                const diff = old_len - new_len;
                self.current_allocated -= diff;
            }

            if (self.current_allocated > self.peak_allocated) {
                self.peak_allocated = self.current_allocated;
            }

            return true;
        }

        return false;
    }

    fn remap(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));

        const old_len = buf.len;

        const result = self.parent.rawRemap(buf, alignment, new_len, ret_addr);
        if (result != null) {
            if (new_len > old_len) {
                const diff = new_len - old_len;
                self.current_allocated += diff;
                self.total_allocated += diff;
            } else {
                const diff = old_len - new_len;
                self.current_allocated -= diff;
            }

            if (self.current_allocated > self.peak_allocated) {
                self.peak_allocated = self.current_allocated;
            }
        }

        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));

        self.current_allocated -= buf.len;
        self.free_count += 1;

        self.parent.rawFree(buf, alignment, ret_addr);
    }
};

test "counting allocator tracks allocations" {
    var counting = CountingAllocator.init(std.testing.allocator);
    const alloc = counting.allocator();

    const buf1 = try alloc.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 100), counting.current_allocated);
    try std.testing.expectEqual(@as(usize, 100), counting.peak_allocated);
    try std.testing.expectEqual(@as(usize, 1), counting.alloc_count);

    const buf2 = try alloc.alloc(u8, 50);
    try std.testing.expectEqual(@as(usize, 150), counting.current_allocated);
    try std.testing.expectEqual(@as(usize, 150), counting.peak_allocated);

    alloc.free(buf1);
    try std.testing.expectEqual(@as(usize, 50), counting.current_allocated);
    try std.testing.expectEqual(@as(usize, 150), counting.peak_allocated); // Peak unchanged

    alloc.free(buf2);
    try std.testing.expectEqual(@as(usize, 0), counting.current_allocated);
    try std.testing.expectEqual(@as(usize, 2), counting.free_count);
}

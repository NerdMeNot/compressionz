//! TAR archive format support.
//!
//! Supports reading and writing POSIX TAR archives (ustar format).
//!
//! ## Reading TAR files
//! ```zig
//! var archive = tar.Reader(SourceType).init(allocator, file);
//! defer archive.deinit();
//!
//! while (try archive.next()) |entry| {
//!     // IMPORTANT: Entry is only valid until the next call to next()
//!     const data = try entry.readAll(allocator);
//!     defer allocator.free(data);
//!     // process data...
//! }
//! ```
//!
//! ## Writing TAR files
//! ```zig
//! var archive = tar.Writer(DestType).init(file);
//!
//! try archive.addFile("hello.txt", "Hello, World!");
//! try archive.addDirectory("subdir");
//! try archive.finish();
//! ```
//!
//! ## Entry Lifetime
//! **Warning**: Entry pointers returned by `next()` are invalidated when `next()`
//! is called again. Copy any data you need before advancing to the next entry.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = @import("../error.zig").Error;

const BLOCK_SIZE = 512;

/// File type in TAR archive.
pub const FileType = enum(u8) {
    regular = '0',
    regular_alt = 0, // Old tar format
    hard_link = '1',
    symbolic_link = '2',
    character_device = '3',
    block_device = '4',
    directory = '5',
    fifo = '6',
    contiguous = '7',
    _,

    pub fn isFile(self: FileType) bool {
        return self == .regular or self == .regular_alt;
    }

    pub fn isDirectory(self: FileType) bool {
        return self == .directory;
    }
};

/// Entry in a TAR archive.
pub const Entry = struct {
    name: []const u8,
    size: u64,
    mode: u32,
    uid: u32,
    gid: u32,
    mtime: u64,
    file_type: FileType,
    link_name: []const u8,

    // Internal state
    allocator: Allocator,
    data_offset: u64,
    reader_source: ?*anyopaque,
    read_fn: ?*const fn (*anyopaque, u64, []u8) anyerror!usize,

    /// Read the entry's data.
    pub fn readAll(self: *const Entry, allocator: Allocator) ![]u8 {
        if (self.file_type.isDirectory() or self.size == 0) {
            return allocator.alloc(u8, 0);
        }

        if (self.reader_source == null or self.read_fn == null) {
            return Error.InvalidData;
        }

        const data = try allocator.alloc(u8, self.size);
        errdefer allocator.free(data);

        var total_read: usize = 0;
        while (total_read < self.size) {
            const n = try self.read_fn.?(self.reader_source.?, self.data_offset + total_read, data[total_read..]);
            if (n == 0) {
                return Error.UnexpectedEof; // errdefer handles cleanup
            }
            total_read += n;
        }

        return data;
    }
};

/// TAR archive reader.
pub fn Reader(comptime SourceType: type) type {
    return struct {
        const Self = @This();

        source: SourceType,
        allocator: Allocator,
        current_offset: u64,
        finished: bool,
        current_entry: ?Entry,
        name_buffer: []u8,
        link_buffer: []u8,

        pub fn init(allocator: Allocator, source: SourceType) Self {
            return Self{
                .source = source,
                .allocator = allocator,
                .current_offset = 0,
                .finished = false,
                .current_entry = null,
                .name_buffer = &[_]u8{},
                .link_buffer = &[_]u8{},
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.name_buffer.len > 0) {
                self.allocator.free(self.name_buffer);
            }
            if (self.link_buffer.len > 0) {
                self.allocator.free(self.link_buffer);
            }
        }

        fn readAt(self: *Self, offset: u64, buffer: []u8) !usize {
            self.source.seekTo(offset) catch return Error.InvalidData;
            return self.source.read(buffer);
        }

        fn readAtWrapper(ctx: *anyopaque, offset: u64, buffer: []u8) anyerror!usize {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.readAt(offset, buffer);
        }

        fn parseOctal(bytes: []const u8) u64 {
            var result: u64 = 0;
            for (bytes) |b| {
                if (b == 0 or b == ' ') break;
                if (b >= '0' and b <= '7') {
                    result = result * 8 + (b - '0');
                }
            }
            return result;
        }

        fn computeChecksum(header: *const [BLOCK_SIZE]u8) u32 {
            // Checksum field (bytes 148-155) is treated as spaces
            var sum: u32 = 0;
            for (header[0..148]) |b| {
                sum += b;
            }
            sum += ' ' * 8; // Checksum field as spaces
            for (header[156..]) |b| {
                sum += b;
            }
            return sum;
        }

        /// Get the next entry, or null if done.
        pub fn next(self: *Self) !?*Entry {
            if (self.finished) return null;

            // Free previous entry's buffers
            if (self.name_buffer.len > 0) {
                self.allocator.free(self.name_buffer);
                self.name_buffer = &[_]u8{};
            }
            if (self.link_buffer.len > 0) {
                self.allocator.free(self.link_buffer);
                self.link_buffer = &[_]u8{};
            }

            // Read header block
            var header: [BLOCK_SIZE]u8 = undefined;
            var total_read: usize = 0;
            while (total_read < BLOCK_SIZE) {
                const n = try self.readAt(self.current_offset + total_read, header[total_read..]);
                if (n == 0) {
                    self.finished = true;
                    return null;
                }
                total_read += n;
            }

            // Check for end of archive (two zero blocks)
            var all_zeros = true;
            for (header) |b| {
                if (b != 0) {
                    all_zeros = false;
                    break;
                }
            }
            if (all_zeros) {
                self.finished = true;
                return null;
            }

            // Validate header checksum
            const stored_checksum = parseOctal(header[148..156]);
            const computed_checksum = computeChecksum(&header);
            if (stored_checksum != computed_checksum) {
                return Error.InvalidData;
            }

            // Parse header
            // Name: bytes 0-99
            const name_end = std.mem.indexOfScalar(u8, header[0..100], 0) orelse 100;
            self.name_buffer = try self.allocator.dupe(u8, header[0..name_end]);

            // Mode: bytes 100-107
            const mode = parseOctal(header[100..108]);

            // UID: bytes 108-115
            const uid = parseOctal(header[108..116]);

            // GID: bytes 116-123
            const gid = parseOctal(header[116..124]);

            // Size: bytes 124-135
            const size = parseOctal(header[124..136]);

            // Mtime: bytes 136-147
            const mtime = parseOctal(header[136..148]);

            // File type: byte 156
            const file_type: FileType = @enumFromInt(header[156]);

            // Link name: bytes 157-256
            const link_end = std.mem.indexOfScalar(u8, header[157..257], 0) orelse 100;
            self.link_buffer = try self.allocator.dupe(u8, header[157..][0..link_end]);

            const data_offset = self.current_offset + BLOCK_SIZE;

            // Calculate next header position (data + padding)
            const data_blocks = (size + BLOCK_SIZE - 1) / BLOCK_SIZE;
            self.current_offset = data_offset + data_blocks * BLOCK_SIZE;

            self.current_entry = Entry{
                .name = self.name_buffer,
                .size = size,
                .mode = @intCast(mode),
                .uid = @intCast(uid),
                .gid = @intCast(gid),
                .mtime = mtime,
                .file_type = file_type,
                .link_name = self.link_buffer,
                .allocator = self.allocator,
                .data_offset = data_offset,
                .reader_source = self,
                .read_fn = &readAtWrapper,
            };

            return &self.current_entry.?;
        }
    };
}

/// TAR archive writer.
pub fn Writer(comptime DestType: type) type {
    return struct {
        const Self = @This();

        dest: DestType,
        finished: bool,

        pub fn init(dest: DestType) Self {
            return Self{
                .dest = dest,
                .finished = false,
            };
        }

        fn writeOctal(buffer: []u8, value: u64) void {
            var v = value;
            var i: usize = buffer.len - 1;
            buffer[i] = 0; // Null terminator
            if (i == 0) return;
            i -= 1;

            while (i > 0) : (i -= 1) {
                buffer[i] = @intCast('0' + (v & 7));
                v >>= 3;
            }
            buffer[0] = @intCast('0' + (v & 7));
        }

        fn computeChecksum(header: *[BLOCK_SIZE]u8) u32 {
            // Checksum field (bytes 148-155) is treated as spaces
            var sum: u32 = 0;
            for (header[0..148]) |b| {
                sum += b;
            }
            sum += ' ' * 8; // Checksum field as spaces
            for (header[156..]) |b| {
                sum += b;
            }
            return sum;
        }

        /// Add a file from memory.
        pub fn addFile(self: *Self, name: []const u8, data: []const u8) !void {
            if (self.finished) return Error.InvalidData;

            var header: [BLOCK_SIZE]u8 = [_]u8{0} ** BLOCK_SIZE;

            // Name
            const name_len = @min(name.len, 100);
            @memcpy(header[0..name_len], name[0..name_len]);

            // Mode (0644)
            writeOctal(header[100..108], 0o644);

            // UID
            writeOctal(header[108..116], 0);

            // GID
            writeOctal(header[116..124], 0);

            // Size
            writeOctal(header[124..136], data.len);

            // Mtime (current time would be better, but use 0 for simplicity)
            writeOctal(header[136..148], 0);

            // File type
            header[156] = '0'; // Regular file

            // USTAR magic
            @memcpy(header[257..263], "ustar ");
            header[263] = ' ';

            // Compute and write checksum
            const checksum = computeChecksum(&header);
            writeOctal(header[148..156], checksum);
            header[155] = ' ';

            try self.dest.writer().writeAll(&header);

            // Write data
            if (data.len > 0) {
                try self.dest.writer().writeAll(data);

                // Pad to block boundary
                const padding = BLOCK_SIZE - (data.len % BLOCK_SIZE);
                if (padding < BLOCK_SIZE) {
                    const zeros = [_]u8{0} ** BLOCK_SIZE;
                    try self.dest.writer().writeAll(zeros[0..padding]);
                }
            }
        }

        /// Add a directory entry.
        pub fn addDirectory(self: *Self, name: []const u8) !void {
            if (self.finished) return Error.InvalidData;

            var header: [BLOCK_SIZE]u8 = [_]u8{0} ** BLOCK_SIZE;

            // Name (ensure trailing /)
            var name_len = @min(name.len, 99);
            @memcpy(header[0..name_len], name[0..name_len]);
            if (name_len > 0 and name[name_len - 1] != '/') {
                header[name_len] = '/';
                name_len += 1;
            }

            // Mode (0755 for directories)
            writeOctal(header[100..108], 0o755);

            // UID
            writeOctal(header[108..116], 0);

            // GID
            writeOctal(header[116..124], 0);

            // Size (0 for directories)
            writeOctal(header[124..136], 0);

            // Mtime
            writeOctal(header[136..148], 0);

            // File type
            header[156] = '5'; // Directory

            // USTAR magic
            @memcpy(header[257..263], "ustar ");
            header[263] = ' ';

            // Compute and write checksum
            const checksum = computeChecksum(&header);
            writeOctal(header[148..156], checksum);
            header[155] = ' ';

            try self.dest.writer().writeAll(&header);
        }

        /// Finish writing the archive.
        pub fn finish(self: *Self) !void {
            if (self.finished) return;

            // Write two zero blocks to mark end of archive
            const zeros = [_]u8{0} ** BLOCK_SIZE;
            try self.dest.writer().writeAll(&zeros);
            try self.dest.writer().writeAll(&zeros);

            self.finished = true;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "tar write and read round-trip" {
    const allocator = std.testing.allocator;

    // Create TAR in memory
    var tar_buffer: [4096]u8 = undefined;
    var tar_stream = std.io.fixedBufferStream(&tar_buffer);

    var writer = Writer(*@TypeOf(tar_stream)).init(&tar_stream);

    try writer.addFile("hello.txt", "Hello, World!");
    try writer.addFile("data.txt", "This is test data.");
    try writer.addDirectory("subdir");
    try writer.finish();

    const tar_data = tar_stream.getWritten();

    // Read the TAR
    var read_stream = std.io.fixedBufferStream(tar_data);
    var reader = Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    // Read first entry
    if (try reader.next()) |entry| {
        try std.testing.expectEqualStrings("hello.txt", entry.name);
        try std.testing.expect(entry.file_type.isFile());
        const data = try entry.readAll(allocator);
        defer allocator.free(data);
        try std.testing.expectEqualStrings("Hello, World!", data);
    } else {
        return error.TestFailed;
    }

    // Read second entry
    if (try reader.next()) |entry| {
        try std.testing.expectEqualStrings("data.txt", entry.name);
        const data = try entry.readAll(allocator);
        defer allocator.free(data);
        try std.testing.expectEqualStrings("This is test data.", data);
    } else {
        return error.TestFailed;
    }

    // Read directory entry
    if (try reader.next()) |entry| {
        try std.testing.expectEqualStrings("subdir/", entry.name);
        try std.testing.expect(entry.file_type.isDirectory());
    } else {
        return error.TestFailed;
    }

    // Should be done
    try std.testing.expectEqual(@as(?*Entry, null), try reader.next());
}

test "tar empty archive" {
    const allocator = std.testing.allocator;

    var tar_buffer: [2048]u8 = undefined;
    var tar_stream = std.io.fixedBufferStream(&tar_buffer);

    var writer = Writer(*@TypeOf(tar_stream)).init(&tar_stream);
    try writer.finish();

    const tar_data = tar_stream.getWritten();

    var read_stream = std.io.fixedBufferStream(tar_data);
    var reader = Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    try std.testing.expectEqual(@as(?*Entry, null), try reader.next());
}

test "tar invalid checksum" {
    const allocator = std.testing.allocator;

    // Create a valid-looking header but with invalid checksum
    var header: [BLOCK_SIZE]u8 = undefined;
    @memset(&header, 0);

    // Set a filename
    @memcpy(header[0..10], "test.txt\x00\x00");

    // Set file mode (octal 644)
    @memcpy(header[100..107], "0000644");

    // Set size to 0
    @memcpy(header[124..135], "00000000000");

    // Set checksum to garbage (should fail validation)
    @memcpy(header[148..155], "9999999");

    var read_stream = std.io.fixedBufferStream(&header);
    var reader = Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    const result = reader.next();
    try std.testing.expectError(Error.InvalidData, result);
}

test "tar truncated archive" {
    const allocator = std.testing.allocator;

    // Just a partial header (less than 512 bytes)
    const truncated = [_]u8{ 't', 'e', 's', 't', '.', 't', 'x', 't' };

    var read_stream = std.io.fixedBufferStream(&truncated);
    var reader = Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    // Should return null (end of stream) or error
    const entry = try reader.next();
    try std.testing.expectEqual(@as(?*Entry, null), entry);
}

//! ZIP archive format support.
//!
//! Supports reading and writing ZIP archives with deflate compression.
//!
//! ## Reading ZIP files
//! ```zig
//! var archive = try zip.Reader(SourceType).init(allocator, file);
//! defer archive.deinit();
//!
//! while (try archive.next()) |entry| {
//!     // IMPORTANT: Entry is valid for the lifetime of the reader
//!     const data = try entry.readAll(allocator);
//!     defer allocator.free(data);
//!     // process data...
//! }
//! ```
//!
//! ## Writing ZIP files
//! ```zig
//! var archive = try zip.Writer(DestType).init(allocator, file);
//! defer archive.deinit();
//!
//! try archive.addFile("hello.txt", "Hello, World!");
//! try archive.finish();
//! ```
//!
//! ## Entry Lifetime
//! Unlike TAR, ZIP entries are stored in an array and remain valid until
//! the reader is deinitialized. You can safely store entry pointers.

const std = @import("std");
const Allocator = std.mem.Allocator;
const zlib_codec = @import("../zlib_codec.zig");
const Error = @import("../error.zig").Error;

// ZIP file signatures
const LOCAL_FILE_HEADER_SIG: u32 = 0x04034b50;
const CENTRAL_DIR_HEADER_SIG: u32 = 0x02014b50;
const END_OF_CENTRAL_DIR_SIG: u32 = 0x06054b50;

// Compression methods
pub const CompressionMethod = enum(u16) {
    store = 0,
    deflate = 8,
    _,
};

/// Entry in a ZIP archive.
pub const Entry = struct {
    name: []const u8,
    compressed_size: u32,
    uncompressed_size: u32,
    compression_method: CompressionMethod,
    crc32: u32,
    local_header_offset: u64,
    is_directory: bool,
    mod_time: u16,
    mod_date: u16,

    // Internal state for reading
    allocator: Allocator,
    data_offset: u64,
    reader_source: ?*anyopaque,
    read_fn: ?*const fn (*anyopaque, u64, []u8) anyerror!usize,

    /// Read and decompress the entry's data.
    pub fn readAll(self: *const Entry, allocator: Allocator) ![]u8 {
        if (self.is_directory) {
            return allocator.alloc(u8, 0);
        }

        if (self.reader_source == null or self.read_fn == null) {
            return Error.InvalidData;
        }

        switch (self.compression_method) {
            .store => {
                // For stored entries, read directly into result (zero-copy)
                const result = try allocator.alloc(u8, self.uncompressed_size);
                errdefer allocator.free(result);

                var total_read: usize = 0;
                while (total_read < self.uncompressed_size) {
                    const n = try self.read_fn.?(self.reader_source.?, self.data_offset + total_read, result[total_read..]);
                    if (n == 0) return Error.UnexpectedEof;
                    total_read += n;
                }
                return result;
            },
            .deflate => {
                // Read compressed data
                const compressed = try allocator.alloc(u8, self.compressed_size);
                defer allocator.free(compressed);

                var total_read: usize = 0;
                while (total_read < self.compressed_size) {
                    const n = try self.read_fn.?(self.reader_source.?, self.data_offset + total_read, compressed[total_read..]);
                    if (n == 0) return Error.UnexpectedEof;
                    total_read += n;
                }

                return zlib_codec.decompressDeflate(compressed, allocator, .{});
            },
            else => return Error.UnsupportedFeature,
        }
    }
};

/// ZIP archive reader.
pub fn Reader(comptime SourceType: type) type {
    return struct {
        const Self = @This();

        source: SourceType,
        allocator: Allocator,
        entries: []Entry,
        current_entry: usize,
        initialized: bool,

        pub fn init(allocator: Allocator, source: SourceType) !Self {
            return Self{
                .source = source,
                .allocator = allocator,
                .entries = &[_]Entry{},
                .current_entry = 0,
                .initialized = false,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.entries) |*entry| {
                self.allocator.free(entry.name);
            }
            if (self.entries.len > 0) {
                self.allocator.free(self.entries);
            }
        }

        fn readAt(self: *Self, offset: u64, buffer: []u8) !usize {
            // Seek and read
            self.source.seekTo(offset) catch return Error.InvalidData;
            return self.source.read(buffer);
        }

        fn readAtWrapper(ctx: *anyopaque, offset: u64, buffer: []u8) anyerror!usize {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.readAt(offset, buffer);
        }

        /// Read the central directory and build entry list.
        fn readCentralDirectory(self: *Self) !void {
            // Find end of central directory
            // Search backwards for the signature
            const source_size = try self.source.getEndPos();
            if (source_size < 22) return Error.InvalidData;

            var eocd_offset: u64 = source_size - 22;
            var found = false;
            var search_buf: [22]u8 = undefined;

            // Search backwards (max 64KB for comment)
            const min_offset: u64 = if (source_size > 65557) source_size - 65557 else 0;
            while (eocd_offset >= min_offset) {
                _ = try self.readAt(eocd_offset, &search_buf);
                const sig = std.mem.readInt(u32, search_buf[0..4], .little);
                if (sig == END_OF_CENTRAL_DIR_SIG) {
                    found = true;
                    break;
                }
                if (eocd_offset == 0) break;
                eocd_offset -= 1;
            }

            if (!found) return Error.InvalidData;

            // Read EOCD
            var eocd: [22]u8 = undefined;
            _ = try self.readAt(eocd_offset, &eocd);

            const num_entries = std.mem.readInt(u16, eocd[10..12], .little);
            const central_dir_size = std.mem.readInt(u32, eocd[12..16], .little);
            const central_dir_offset = std.mem.readInt(u32, eocd[16..20], .little);

            // Validate central directory bounds
            if (central_dir_offset > source_size) return Error.InvalidData;
            const cd_end = @as(u64, central_dir_offset) + @as(u64, central_dir_size);
            if (cd_end > source_size) return Error.InvalidData;

            // Read central directory entries
            self.entries = try self.allocator.alloc(Entry, num_entries);
            var entries_initialized: usize = 0;

            // Cleanup helper for error cases - frees all initialized entry names
            errdefer {
                for (self.entries[0..entries_initialized]) |*entry| {
                    self.allocator.free(entry.name);
                }
                self.allocator.free(self.entries);
            }

            var offset: u64 = central_dir_offset;
            for (self.entries) |*entry| {
                // Bounds check before reading header
                if (offset + 46 > source_size) return Error.InvalidData;

                var header: [46]u8 = undefined;
                _ = try self.readAt(offset, &header);

                const sig = std.mem.readInt(u32, header[0..4], .little);
                if (sig != CENTRAL_DIR_HEADER_SIG) return Error.InvalidData;

                const compression = std.mem.readInt(u16, header[10..12], .little);
                const mod_time = std.mem.readInt(u16, header[12..14], .little);
                const mod_date = std.mem.readInt(u16, header[14..16], .little);
                const crc = std.mem.readInt(u32, header[16..20], .little);
                const compressed_size = std.mem.readInt(u32, header[20..24], .little);
                const uncompressed_size = std.mem.readInt(u32, header[24..28], .little);
                const name_len = std.mem.readInt(u16, header[28..30], .little);
                const extra_len = std.mem.readInt(u16, header[30..32], .little);
                const comment_len = std.mem.readInt(u16, header[32..34], .little);
                const local_header_offset = std.mem.readInt(u32, header[42..46], .little);

                // Validate local header offset is within file bounds
                if (local_header_offset + 30 > source_size) return Error.InvalidData;

                // Validate name can be read
                if (offset + 46 + name_len > source_size) return Error.InvalidData;

                // Read filename
                const name = try self.allocator.alloc(u8, name_len);
                errdefer self.allocator.free(name);
                _ = try self.readAt(offset + 46, name);

                entry.* = Entry{
                    .name = name,
                    .compressed_size = compressed_size,
                    .uncompressed_size = uncompressed_size,
                    .compression_method = @enumFromInt(compression),
                    .crc32 = crc,
                    .local_header_offset = local_header_offset,
                    .is_directory = name_len > 0 and name[name_len - 1] == '/',
                    .mod_time = mod_time,
                    .mod_date = mod_date,
                    .allocator = self.allocator,
                    .data_offset = 0, // Will be set when reading local header
                    .reader_source = self,
                    .read_fn = &readAtWrapper,
                };

                entries_initialized += 1;

                // Safe offset advancement with overflow check
                const entry_size = @as(u64, 46) + @as(u64, name_len) + @as(u64, extra_len) + @as(u64, comment_len);
                offset = offset + entry_size;
            }

            // Calculate data offsets by reading local headers
            for (self.entries) |*entry| {
                var local_header: [30]u8 = undefined;
                _ = try self.readAt(entry.local_header_offset, &local_header);

                const local_sig = std.mem.readInt(u32, local_header[0..4], .little);
                if (local_sig != LOCAL_FILE_HEADER_SIG) return Error.InvalidData;

                const local_name_len = std.mem.readInt(u16, local_header[26..28], .little);
                const local_extra_len = std.mem.readInt(u16, local_header[28..30], .little);

                // Calculate data offset with bounds check
                const data_offset = entry.local_header_offset + 30 + @as(u64, local_name_len) + @as(u64, local_extra_len);
                if (data_offset > source_size) return Error.InvalidData;

                // Validate compressed data fits within file
                if (data_offset + entry.compressed_size > source_size) return Error.InvalidData;

                entry.data_offset = data_offset;
            }

            self.initialized = true;
        }

        /// Get the next entry, or null if done.
        pub fn next(self: *Self) !?*Entry {
            if (!self.initialized) {
                try self.readCentralDirectory();
            }

            if (self.current_entry >= self.entries.len) {
                return null;
            }

            const entry = &self.entries[self.current_entry];
            self.current_entry += 1;
            return entry;
        }

        /// Get entry by name.
        pub fn getEntry(self: *Self, name: []const u8) !?*Entry {
            if (!self.initialized) {
                try self.readCentralDirectory();
            }

            for (self.entries) |*entry| {
                if (std.mem.eql(u8, entry.name, name)) {
                    return entry;
                }
            }
            return null;
        }

        /// Get number of entries.
        pub fn count(self: *Self) !usize {
            if (!self.initialized) {
                try self.readCentralDirectory();
            }
            return self.entries.len;
        }
    };
}

/// ZIP archive writer.
pub fn Writer(comptime DestType: type) type {
    return struct {
        const Self = @This();

        const CentralDirEntry = struct {
            name: []const u8,
            compressed_size: u32,
            uncompressed_size: u32,
            crc32: u32,
            local_header_offset: u32,
            compression_method: CompressionMethod,
        };

        dest: DestType,
        allocator: Allocator,
        central_dir: std.ArrayListUnmanaged(CentralDirEntry),
        current_offset: u64,
        finished: bool,

        pub fn init(allocator: Allocator, dest: DestType) !Self {
            return Self{
                .dest = dest,
                .allocator = allocator,
                .central_dir = .{},
                .current_offset = 0,
                .finished = false,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.central_dir.items) |entry| {
                self.allocator.free(entry.name);
            }
            self.central_dir.deinit(self.allocator);
        }

        /// Add a file from memory.
        pub fn addFile(self: *Self, name: []const u8, data: []const u8) !void {
            if (self.finished) return Error.InvalidData;

            // Compute CRC32
            const crc = std.hash.Crc32.hash(data);

            // Compress data
            const compressed = try zlib_codec.compressDeflate(data, self.allocator, .{});
            defer self.allocator.free(compressed);

            // Decide whether to store or deflate
            const use_compression = compressed.len < data.len;
            const method: CompressionMethod = if (use_compression) .deflate else .store;
            const stored_data = if (use_compression) compressed else data;

            // Write local file header
            const local_offset = self.current_offset;
            try self.writeLocalHeader(name, crc, @intCast(stored_data.len), @intCast(data.len), method);

            // Write data
            try self.dest.writer().writeAll(stored_data);
            self.current_offset += stored_data.len;

            // Store for central directory
            const name_copy = try self.allocator.dupe(u8, name);
            try self.central_dir.append(self.allocator, .{
                .name = name_copy,
                .compressed_size = @intCast(stored_data.len),
                .uncompressed_size = @intCast(data.len),
                .crc32 = crc,
                .local_header_offset = @intCast(local_offset),
                .compression_method = method,
            });
        }

        /// Add a directory entry.
        pub fn addDirectory(self: *Self, name: []const u8) !void {
            if (self.finished) return Error.InvalidData;

            // Ensure name ends with /
            const needs_slash = name.len == 0 or name[name.len - 1] != '/';

            const full_name = if (needs_slash)
                try std.fmt.allocPrint(self.allocator, "{s}/", .{name})
            else
                try self.allocator.dupe(u8, name);

            defer if (needs_slash) self.allocator.free(full_name);

            const local_offset = self.current_offset;
            try self.writeLocalHeader(full_name, 0, 0, 0, .store);

            const name_copy = try self.allocator.dupe(u8, full_name);
            try self.central_dir.append(self.allocator, .{
                .name = name_copy,
                .compressed_size = 0,
                .uncompressed_size = 0,
                .crc32 = 0,
                .local_header_offset = @intCast(local_offset),
                .compression_method = .store,
            });
        }

        fn writeLocalHeader(
            self: *Self,
            name: []const u8,
            crc: u32,
            compressed_size: u32,
            uncompressed_size: u32,
            method: CompressionMethod,
        ) !void {
            var header: [30]u8 = undefined;

            // Signature
            std.mem.writeInt(u32, header[0..4], LOCAL_FILE_HEADER_SIG, .little);
            // Version needed
            std.mem.writeInt(u16, header[4..6], 20, .little);
            // General purpose bit flag
            std.mem.writeInt(u16, header[6..8], 0, .little);
            // Compression method
            std.mem.writeInt(u16, header[8..10], @intFromEnum(method), .little);
            // Mod time/date (use zeros for simplicity)
            std.mem.writeInt(u16, header[10..12], 0, .little);
            std.mem.writeInt(u16, header[12..14], 0, .little);
            // CRC32
            std.mem.writeInt(u32, header[14..18], crc, .little);
            // Compressed size
            std.mem.writeInt(u32, header[18..22], compressed_size, .little);
            // Uncompressed size
            std.mem.writeInt(u32, header[22..26], uncompressed_size, .little);
            // Filename length
            std.mem.writeInt(u16, header[26..28], @intCast(name.len), .little);
            // Extra field length
            std.mem.writeInt(u16, header[28..30], 0, .little);

            try self.dest.writer().writeAll(&header);
            try self.dest.writer().writeAll(name);
            self.current_offset += 30 + name.len;
        }

        /// Finish writing the archive.
        pub fn finish(self: *Self) !void {
            if (self.finished) return;

            const central_dir_offset = self.current_offset;
            var central_dir_size: u64 = 0;

            // Write central directory
            for (self.central_dir.items) |entry| {
                var header: [46]u8 = undefined;

                // Signature
                std.mem.writeInt(u32, header[0..4], CENTRAL_DIR_HEADER_SIG, .little);
                // Version made by
                std.mem.writeInt(u16, header[4..6], 20, .little);
                // Version needed
                std.mem.writeInt(u16, header[6..8], 20, .little);
                // General purpose bit flag
                std.mem.writeInt(u16, header[8..10], 0, .little);
                // Compression method
                std.mem.writeInt(u16, header[10..12], @intFromEnum(entry.compression_method), .little);
                // Mod time/date
                std.mem.writeInt(u16, header[12..14], 0, .little);
                std.mem.writeInt(u16, header[14..16], 0, .little);
                // CRC32
                std.mem.writeInt(u32, header[16..20], entry.crc32, .little);
                // Compressed size
                std.mem.writeInt(u32, header[20..24], entry.compressed_size, .little);
                // Uncompressed size
                std.mem.writeInt(u32, header[24..28], entry.uncompressed_size, .little);
                // Filename length
                std.mem.writeInt(u16, header[28..30], @intCast(entry.name.len), .little);
                // Extra field length
                std.mem.writeInt(u16, header[30..32], 0, .little);
                // Comment length
                std.mem.writeInt(u16, header[32..34], 0, .little);
                // Disk number start
                std.mem.writeInt(u16, header[34..36], 0, .little);
                // Internal file attributes
                std.mem.writeInt(u16, header[36..38], 0, .little);
                // External file attributes
                std.mem.writeInt(u32, header[38..42], 0, .little);
                // Local header offset
                std.mem.writeInt(u32, header[42..46], entry.local_header_offset, .little);

                try self.dest.writer().writeAll(&header);
                try self.dest.writer().writeAll(entry.name);
                central_dir_size += 46 + entry.name.len;
            }

            // Write end of central directory
            var eocd: [22]u8 = undefined;

            // Signature
            std.mem.writeInt(u32, eocd[0..4], END_OF_CENTRAL_DIR_SIG, .little);
            // Disk number
            std.mem.writeInt(u16, eocd[4..6], 0, .little);
            // Disk with central dir
            std.mem.writeInt(u16, eocd[6..8], 0, .little);
            // Number of entries on disk
            std.mem.writeInt(u16, eocd[8..10], @intCast(self.central_dir.items.len), .little);
            // Total number of entries
            std.mem.writeInt(u16, eocd[10..12], @intCast(self.central_dir.items.len), .little);
            // Central dir size
            std.mem.writeInt(u32, eocd[12..16], @intCast(central_dir_size), .little);
            // Central dir offset
            std.mem.writeInt(u32, eocd[16..20], @intCast(central_dir_offset), .little);
            // Comment length
            std.mem.writeInt(u16, eocd[20..22], 0, .little);

            try self.dest.writer().writeAll(&eocd);
            self.finished = true;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "zip write and read round-trip" {
    const allocator = std.testing.allocator;

    // Create ZIP in memory
    var zip_buffer: [8192]u8 = undefined;
    var zip_stream = std.io.fixedBufferStream(&zip_buffer);

    var writer = try Writer(*@TypeOf(zip_stream)).init(allocator, &zip_stream);
    defer writer.deinit();

    try writer.addFile("hello.txt", "Hello, World!");
    try writer.addFile("data.txt", "This is some test data for compression. " ** 10);
    try writer.addDirectory("subdir");
    try writer.finish();

    const zip_data = zip_stream.getWritten();

    // Read the ZIP
    var read_stream = std.io.fixedBufferStream(zip_data);
    var reader = try Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    const count = try reader.count();
    try std.testing.expectEqual(@as(usize, 3), count);

    // Read entries
    if (try reader.getEntry("hello.txt")) |entry| {
        const data = try entry.readAll(allocator);
        defer allocator.free(data);
        try std.testing.expectEqualStrings("Hello, World!", data);
    } else {
        return error.TestFailed;
    }

    if (try reader.getEntry("data.txt")) |entry| {
        const data = try entry.readAll(allocator);
        defer allocator.free(data);
        try std.testing.expectEqualStrings("This is some test data for compression. " ** 10, data);
    } else {
        return error.TestFailed;
    }
}

test "zip empty archive" {
    const allocator = std.testing.allocator;

    var zip_buffer: [1024]u8 = undefined;
    var zip_stream = std.io.fixedBufferStream(&zip_buffer);

    var writer = try Writer(*@TypeOf(zip_stream)).init(allocator, &zip_stream);
    defer writer.deinit();
    try writer.finish();

    const zip_data = zip_stream.getWritten();

    var read_stream = std.io.fixedBufferStream(zip_data);
    var reader = try Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    try std.testing.expectEqual(@as(usize, 0), try reader.count());
}

test "zip invalid signature" {
    const allocator = std.testing.allocator;

    // Invalid end-of-central-directory signature
    const invalid_data = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

    var read_stream = std.io.fixedBufferStream(&invalid_data);
    var reader = try Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    // Reader uses lazy init, so trigger actual reading
    const result = reader.count();
    try std.testing.expectError(Error.InvalidData, result);
}

test "zip truncated archive" {
    const allocator = std.testing.allocator;

    // Just the EOCD signature without the rest of the record
    const truncated = [_]u8{ 0x50, 0x4B, 0x05, 0x06 };

    var read_stream = std.io.fixedBufferStream(&truncated);
    var reader = try Reader(*@TypeOf(read_stream)).init(allocator, &read_stream);
    defer reader.deinit();

    // Reader uses lazy init, so trigger actual reading
    const result = reader.count();
    try std.testing.expectError(Error.InvalidData, result);
}

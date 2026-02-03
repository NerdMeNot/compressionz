//! Archive formats (containers for multiple files).
//!
//! Unlike compression codecs which transform byte streams, archive formats
//! bundle multiple files with their names, paths, and metadata.
//!
//! ## Supported Formats
//!
//! - **ZIP**: Popular archive format with built-in compression (deflate)
//! - **TAR**: Unix tape archive format (no compression, often combined with gzip/zstd)
//!
//! ## Quick Start
//!
//! ```zig
//! const cz = @import("compressionz");
//!
//! // Extract all files from a ZIP buffer
//! const files = try cz.archive.extractZip(allocator, zip_data);
//! defer {
//!     for (files) |f| {
//!         allocator.free(f.name);
//!         allocator.free(f.data);
//!     }
//!     allocator.free(files);
//! }
//! ```
//!
//! ## Manual Iteration
//!
//! ```zig
//! // Read a ZIP file
//! var zip_reader = try cz.archive.zip.Reader.init(allocator, file);
//! defer zip_reader.deinit();
//!
//! while (try zip_reader.next()) |entry| {
//!     const data = try entry.readAll(allocator);
//!     defer allocator.free(data);
//! }
//!
//! // Write a ZIP file
//! var zip_writer = try cz.archive.zip.Writer.init(allocator, file);
//! defer zip_writer.deinit();
//!
//! try zip_writer.addFile("hello.txt", "Hello!");
//! try zip_writer.finish();
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const zip = @import("zip.zig");
pub const tar = @import("tar.zig");

/// A file extracted from an archive.
pub const ExtractedFile = struct {
    name: []const u8,
    data: []const u8,
    is_directory: bool,
};

/// Input for creating archives.
pub const FileEntry = struct {
    name: []const u8,
    data: []const u8,
};

/// Extract all files from a ZIP archive in memory.
/// Returns a slice of ExtractedFile. Caller must free:
/// - Each file's name and data
/// - The slice itself
pub fn extractZip(allocator: Allocator, data: []const u8) ![]ExtractedFile {
    var fbs = std.io.fixedBufferStream(data);
    var reader = try zip.Reader(*@TypeOf(fbs)).init(allocator, &fbs);
    defer reader.deinit();

    var files: std.ArrayListUnmanaged(ExtractedFile) = .{};
    errdefer {
        for (files.items) |f| {
            allocator.free(f.name);
            allocator.free(f.data);
        }
        files.deinit(allocator);
    }

    while (try reader.next()) |entry| {
        const name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(name);

        const file_data = try entry.readAll(allocator);
        errdefer allocator.free(file_data);

        try files.append(allocator, .{
            .name = name,
            .data = file_data,
            .is_directory = entry.is_directory,
        });
    }

    return files.toOwnedSlice(allocator);
}

/// Extract all files from a TAR archive in memory.
/// Returns a slice of ExtractedFile. Caller must free:
/// - Each file's name and data
/// - The slice itself
pub fn extractTar(allocator: Allocator, data: []const u8) ![]ExtractedFile {
    var fbs = std.io.fixedBufferStream(data);
    var reader = tar.Reader(*@TypeOf(fbs)).init(allocator, &fbs);
    defer reader.deinit();

    var files: std.ArrayListUnmanaged(ExtractedFile) = .{};
    errdefer {
        for (files.items) |f| {
            allocator.free(f.name);
            allocator.free(f.data);
        }
        files.deinit(allocator);
    }

    while (try reader.next()) |entry| {
        const name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(name);

        const file_data = try entry.readAll(allocator);
        errdefer allocator.free(file_data);

        try files.append(allocator, .{
            .name = name,
            .data = file_data,
            .is_directory = entry.file_type.isDirectory(),
        });
    }

    return files.toOwnedSlice(allocator);
}

/// Create a ZIP archive in memory from a list of files.
/// Returns the ZIP data. Caller must free.
pub fn createZip(allocator: Allocator, files: []const FileEntry) ![]u8 {
    // Estimate size (generous for compression overhead)
    var total_size: usize = 22; // EOCD
    for (files) |f| {
        total_size += 30 + f.name.len + f.data.len + 46 + f.name.len; // local + data + central
    }

    const buffer = try allocator.alloc(u8, total_size * 2);
    errdefer allocator.free(buffer);

    var fbs = std.io.fixedBufferStream(buffer);
    var writer = try zip.Writer(*@TypeOf(fbs)).init(allocator, &fbs);
    defer writer.deinit();

    for (files) |f| {
        try writer.addFile(f.name, f.data);
    }
    try writer.finish();

    const written = fbs.getWritten();
    const result = try allocator.dupe(u8, written);
    allocator.free(buffer);
    return result;
}

/// Create a TAR archive in memory from a list of files.
/// Returns the TAR data. Caller must free.
pub fn createTar(allocator: Allocator, files: []const FileEntry) ![]u8 {
    // Estimate size
    var total_size: usize = 1024; // End blocks
    for (files) |f| {
        // Header + data padded to 512
        total_size += 512 + ((f.data.len + 511) / 512) * 512;
    }

    const buffer = try allocator.alloc(u8, total_size);
    errdefer allocator.free(buffer);

    var fbs = std.io.fixedBufferStream(buffer);
    var writer = tar.Writer(*@TypeOf(fbs)).init(&fbs);

    for (files) |f| {
        try writer.addFile(f.name, f.data);
    }
    try writer.finish();

    const written = fbs.getWritten();
    const result = try allocator.dupe(u8, written);
    allocator.free(buffer);
    return result;
}

// Tests
test "extractZip convenience function" {
    const allocator = std.testing.allocator;

    // Create a ZIP first
    const files_in = [_]FileEntry{
        .{ .name = "hello.txt", .data = "Hello!" },
        .{ .name = "world.txt", .data = "World!" },
    };

    const zip_data = try createZip(allocator, &files_in);
    defer allocator.free(zip_data);

    // Extract it
    const files_out = try extractZip(allocator, zip_data);
    defer {
        for (files_out) |f| {
            allocator.free(f.name);
            allocator.free(f.data);
        }
        allocator.free(files_out);
    }

    try std.testing.expectEqual(@as(usize, 2), files_out.len);
    try std.testing.expectEqualStrings("hello.txt", files_out[0].name);
    try std.testing.expectEqualStrings("Hello!", files_out[0].data);
}

test "extractTar convenience function" {
    const allocator = std.testing.allocator;

    // Create a TAR first
    const files_in = [_]FileEntry{
        .{ .name = "file1.txt", .data = "Content 1" },
        .{ .name = "file2.txt", .data = "Content 2" },
    };

    const tar_data = try createTar(allocator, &files_in);
    defer allocator.free(tar_data);

    // Extract it
    const files_out = try extractTar(allocator, tar_data);
    defer {
        for (files_out) |f| {
            allocator.free(f.name);
            allocator.free(f.data);
        }
        allocator.free(files_out);
    }

    try std.testing.expectEqual(@as(usize, 2), files_out.len);
    try std.testing.expectEqualStrings("file1.txt", files_out[0].name);
    try std.testing.expectEqualStrings("Content 1", files_out[0].data);
}

test {
    _ = zip;
    _ = tar;
}

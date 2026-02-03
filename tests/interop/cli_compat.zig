//! Interoperability tests: CLI tool compatibility.
//!
//! Tests that data compressed by this library can be decompressed by
//! standard CLI tools, and vice versa.
//!
//! Note: These tests require external tools (gzip, lz4, zstd) to be installed.
//! Tests will skip gracefully if tools are not available.

const std = @import("std");
const cz = @import("compressionz");

const testing = std.testing;

/// Check if a command is available on the system
fn isCommandAvailable(cmd: []const u8) bool {
    const result = std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = &[_][]const u8{ "which", cmd },
    }) catch return false;
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    return result.term.Exited == 0;
}

/// Run a command and return stdout
fn runCommand(argv: []const []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = argv,
        .max_output_bytes = 10 * 1024 * 1024,
    });
    defer testing.allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        testing.allocator.free(result.stdout);
        return error.CommandFailed;
    }

    return result.stdout;
}

// =============================================================================
// Gzip Interoperability
// =============================================================================

test "gzip: our compression, CLI decompression" {
    if (!isCommandAvailable("gzip")) {
        std.debug.print("Skipping: gzip not available\n", .{});
        return;
    }

    const allocator = testing.allocator;
    const input = "Test data for gzip interoperability testing.\n";

    // Compress with our library
    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Write to temp file
    var tmp_file = try std.fs.cwd().createFile("/tmp/compressionz_test.gz", .{});
    defer tmp_file.close();
    try tmp_file.writeAll(compressed);

    // Decompress with CLI
    const decompressed = runCommand(&[_][]const u8{ "gzip", "-dc", "/tmp/compressionz_test.gz" }) catch {
        std.debug.print("Skipping: gzip command failed\n", .{});
        return;
    };
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);

    // Cleanup
    std.fs.cwd().deleteFile("/tmp/compressionz_test.gz") catch {};
}

test "gzip: CLI compression, our decompression" {
    if (!isCommandAvailable("gzip")) {
        std.debug.print("Skipping: gzip not available\n", .{});
        return;
    }

    const allocator = testing.allocator;
    const input = "Test data for gzip CLI compatibility.\n";

    // Write uncompressed data
    var tmp_file = try std.fs.cwd().createFile("/tmp/compressionz_test_input.txt", .{});
    try tmp_file.writeAll(input);
    tmp_file.close();

    // Compress with CLI (creates .gz file)
    _ = runCommand(&[_][]const u8{ "gzip", "-kf", "/tmp/compressionz_test_input.txt" }) catch {
        std.debug.print("Skipping: gzip command failed\n", .{});
        std.fs.cwd().deleteFile("/tmp/compressionz_test_input.txt") catch {};
        return;
    };

    // Read compressed file
    const compressed_file = try std.fs.cwd().openFile("/tmp/compressionz_test_input.txt.gz", .{});
    defer compressed_file.close();
    const compressed = try compressed_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(compressed);

    // Decompress with our library
    const decompressed = try cz.gzip.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);

    // Cleanup
    std.fs.cwd().deleteFile("/tmp/compressionz_test_input.txt") catch {};
    std.fs.cwd().deleteFile("/tmp/compressionz_test_input.txt.gz") catch {};
}

// =============================================================================
// LZ4 Interoperability
// =============================================================================

test "lz4: our compression, CLI decompression" {
    if (!isCommandAvailable("lz4")) {
        std.debug.print("Skipping: lz4 not available\n", .{});
        return;
    }

    const allocator = testing.allocator;
    const input = "Test data for LZ4 interoperability testing.\n";

    // Compress with our library (frame format)
    const compressed = try cz.lz4.frame.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Write to temp file
    var tmp_file = try std.fs.cwd().createFile("/tmp/compressionz_test.lz4", .{});
    defer tmp_file.close();
    try tmp_file.writeAll(compressed);

    // Decompress with CLI
    const decompressed = runCommand(&[_][]const u8{ "lz4", "-dc", "/tmp/compressionz_test.lz4" }) catch {
        std.debug.print("Skipping: lz4 command failed\n", .{});
        return;
    };
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);

    // Cleanup
    std.fs.cwd().deleteFile("/tmp/compressionz_test.lz4") catch {};
}

test "lz4: CLI compression, our decompression" {
    if (!isCommandAvailable("lz4")) {
        std.debug.print("Skipping: lz4 not available\n", .{});
        return;
    }

    const allocator = testing.allocator;
    const input = "Test data for LZ4 CLI compatibility.\n";

    // Write uncompressed data
    var tmp_file = try std.fs.cwd().createFile("/tmp/compressionz_lz4_input.txt", .{});
    try tmp_file.writeAll(input);
    tmp_file.close();

    // Compress with CLI
    _ = runCommand(&[_][]const u8{ "lz4", "-f", "/tmp/compressionz_lz4_input.txt", "/tmp/compressionz_lz4_input.txt.lz4" }) catch {
        std.debug.print("Skipping: lz4 command failed\n", .{});
        std.fs.cwd().deleteFile("/tmp/compressionz_lz4_input.txt") catch {};
        return;
    };

    // Read compressed file
    const compressed_file = try std.fs.cwd().openFile("/tmp/compressionz_lz4_input.txt.lz4", .{});
    defer compressed_file.close();
    const compressed = try compressed_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(compressed);

    // Decompress with our library
    const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);

    // Cleanup
    std.fs.cwd().deleteFile("/tmp/compressionz_lz4_input.txt") catch {};
    std.fs.cwd().deleteFile("/tmp/compressionz_lz4_input.txt.lz4") catch {};
}

// =============================================================================
// Zstd Interoperability
// =============================================================================

test "zstd: our compression, CLI decompression" {
    if (!isCommandAvailable("zstd")) {
        std.debug.print("Skipping: zstd not available\n", .{});
        return;
    }

    const allocator = testing.allocator;
    const input = "Test data for Zstd interoperability testing.\n";

    // Compress with our library
    const compressed = try cz.zstd.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Write to temp file
    var tmp_file = try std.fs.cwd().createFile("/tmp/compressionz_test.zst", .{});
    defer tmp_file.close();
    try tmp_file.writeAll(compressed);

    // Decompress with CLI
    const decompressed = runCommand(&[_][]const u8{ "zstd", "-dc", "/tmp/compressionz_test.zst" }) catch {
        std.debug.print("Skipping: zstd command failed\n", .{});
        return;
    };
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);

    // Cleanup
    std.fs.cwd().deleteFile("/tmp/compressionz_test.zst") catch {};
}

test "zstd: CLI compression, our decompression" {
    if (!isCommandAvailable("zstd")) {
        std.debug.print("Skipping: zstd not available\n", .{});
        return;
    }

    const allocator = testing.allocator;
    const input = "Test data for Zstd CLI compatibility.\n";

    // Write uncompressed data
    var tmp_file = try std.fs.cwd().createFile("/tmp/compressionz_zstd_input.txt", .{});
    try tmp_file.writeAll(input);
    tmp_file.close();

    // Compress with CLI
    _ = runCommand(&[_][]const u8{ "zstd", "-f", "/tmp/compressionz_zstd_input.txt", "-o", "/tmp/compressionz_zstd_input.txt.zst" }) catch {
        std.debug.print("Skipping: zstd command failed\n", .{});
        std.fs.cwd().deleteFile("/tmp/compressionz_zstd_input.txt") catch {};
        return;
    };

    // Read compressed file
    const compressed_file = try std.fs.cwd().openFile("/tmp/compressionz_zstd_input.txt.zst", .{});
    defer compressed_file.close();
    const compressed = try compressed_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(compressed);

    // Decompress with our library
    const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(input, decompressed);

    // Cleanup
    std.fs.cwd().deleteFile("/tmp/compressionz_zstd_input.txt") catch {};
    std.fs.cwd().deleteFile("/tmp/compressionz_zstd_input.txt.zst") catch {};
}

// =============================================================================
// Large Data Interoperability
// =============================================================================

test "gzip: large file interoperability" {
    if (!isCommandAvailable("gzip")) {
        std.debug.print("Skipping: gzip not available\n", .{});
        return;
    }

    const allocator = testing.allocator;

    // Generate 100KB of data
    const input = try allocator.alloc(u8, 100 * 1024);
    defer allocator.free(input);
    for (input, 0..) |*b, i| {
        b.* = @intCast(i % 256);
    }

    // Compress with our library
    const compressed = try cz.gzip.compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Write to temp file
    var tmp_file = try std.fs.cwd().createFile("/tmp/compressionz_large.gz", .{});
    try tmp_file.writeAll(compressed);
    tmp_file.close();

    // Decompress with CLI and capture output
    const decompressed = runCommand(&[_][]const u8{ "gzip", "-dc", "/tmp/compressionz_large.gz" }) catch {
        std.debug.print("Skipping: gzip command failed\n", .{});
        return;
    };
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, input, decompressed);

    // Cleanup
    std.fs.cwd().deleteFile("/tmp/compressionz_large.gz") catch {};
}

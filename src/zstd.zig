//! Zstandard compression and decompression.
//!
//! Zstd provides excellent compression ratios with good speed.
//! Supports both one-shot and streaming APIs, as well as dictionary compression.
//!
//! ## One-shot API
//! ```zig
//! const cz = @import("compressionz");
//!
//! const compressed = try cz.zstd.compress(input, allocator, .{});
//! defer allocator.free(compressed);
//!
//! const decompressed = try cz.zstd.decompress(compressed, allocator, .{});
//! defer allocator.free(decompressed);
//! ```
//!
//! ## Streaming API
//! ```zig
//! // Compression
//! var comp = try cz.zstd.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
//! defer comp.deinit();
//! try comp.writer().writeAll(data);
//! try comp.finish();
//!
//! // Decompression
//! var decomp = try cz.zstd.Decompressor(@TypeOf(reader)).init(allocator, reader);
//! defer decomp.deinit();
//! const data = try decomp.reader().readAllAlloc(allocator, max_size);
//! ```
//!
//! ## Dictionary Compression
//! ```zig
//! const compressed = try cz.zstd.compressWithDict(input, dict, allocator, .{});
//! const decompressed = try cz.zstd.decompressWithDict(compressed, dict, allocator, .{});
//! ```

const std = @import("std");
const err = @import("error.zig");
const Error = err.Error;
const shrinkAllocation = err.shrinkAllocation;
const Level = @import("level.zig").Level;

const c = @cImport({
    @cInclude("zstd.h");
});

// These constants have issues with @cImport, define manually
const ZSTD_CONTENTSIZE_UNKNOWN: c_ulonglong = @bitCast(@as(i64, -1));
const ZSTD_CONTENTSIZE_ERROR: c_ulonglong = @bitCast(@as(i64, -2));

// ============================================================================
// Options
// ============================================================================

/// Options for one-shot compression.
pub const CompressOptions = struct {
    level: Level = .default,
};

/// Options for one-shot decompression.
pub const DecompressOptions = struct {
    /// Maximum output size (protection against decompression bombs).
    max_output_size: ?usize = null,
};

// ============================================================================
// One-shot API
// ============================================================================

/// Compress data with Zstd.
/// Caller owns returned slice and must free with allocator.
pub fn compress(input: []const u8, allocator: std.mem.Allocator, options: CompressOptions) Error![]u8 {
    return compressWithDict(input, null, allocator, options);
}

/// Compress data with Zstd using a dictionary.
/// Dictionary compression can significantly improve ratios for small data.
/// Caller owns returned slice and must free with allocator.
pub fn compressWithDict(
    input: []const u8,
    dictionary: ?[]const u8,
    allocator: std.mem.Allocator,
    options: CompressOptions,
) Error![]u8 {
    if (input.len == 0) {
        return allocator.alloc(u8, 0) catch return Error.OutOfMemory;
    }

    const max_size = c.ZSTD_compressBound(input.len);
    const output = allocator.alloc(u8, max_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    const zstd_level = levelToZstdLevel(options.level);

    const zstd_result = if (dictionary) |dict| blk: {
        const cctx = c.ZSTD_createCCtx() orelse return Error.OutOfMemory;
        defer _ = c.ZSTD_freeCCtx(cctx);
        break :blk c.ZSTD_compress_usingDict(
            cctx,
            output.ptr,
            output.len,
            input.ptr,
            input.len,
            dict.ptr,
            dict.len,
            zstd_level,
        );
    } else c.ZSTD_compress(
        output.ptr,
        output.len,
        input.ptr,
        input.len,
        zstd_level,
    );

    if (c.ZSTD_isError(zstd_result) != 0) {
        return Error.InvalidData;
    }

    return shrinkAllocation(allocator, output, zstd_result);
}

/// Decompress Zstd data.
/// Caller owns returned slice and must free with allocator.
pub fn decompress(input: []const u8, allocator: std.mem.Allocator, options: DecompressOptions) Error![]u8 {
    return decompressWithDict(input, null, allocator, options);
}

/// Decompress Zstd data using a dictionary.
/// Caller owns returned slice and must free with allocator.
pub fn decompressWithDict(
    input: []const u8,
    dictionary: ?[]const u8,
    allocator: std.mem.Allocator,
    options: DecompressOptions,
) Error![]u8 {
    const max_output_size = options.max_output_size;

    if (input.len == 0) {
        return allocator.alloc(u8, 0) catch return Error.OutOfMemory;
    }

    // Try to get decompressed size from frame header
    const frame_size = c.ZSTD_getFrameContentSize(input.ptr, input.len);

    var output_size: usize = undefined;
    if (frame_size == ZSTD_CONTENTSIZE_UNKNOWN or frame_size == ZSTD_CONTENTSIZE_ERROR) {
        // Unknown size, estimate
        output_size = input.len * 4;
        if (output_size < 1024) output_size = 1024;
    } else {
        output_size = frame_size;
        // Check limit early if we know the size
        if (max_output_size) |limit| {
            if (output_size > limit) return Error.OutputTooLarge;
        }
    }

    // Cap initial allocation at limit if set
    if (max_output_size) |limit| {
        output_size = @min(output_size, limit);
    }

    var output = allocator.alloc(u8, output_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    // Use dictionary API if dictionary provided, otherwise simple API
    const zstd_result = if (dictionary) |dict| blk: {
        const dctx = c.ZSTD_createDCtx() orelse return Error.OutOfMemory;
        defer _ = c.ZSTD_freeDCtx(dctx);
        break :blk c.ZSTD_decompress_usingDict(
            dctx,
            output.ptr,
            output.len,
            input.ptr,
            input.len,
            dict.ptr,
            dict.len,
        );
    } else c.ZSTD_decompress(
        output.ptr,
        output.len,
        input.ptr,
        input.len,
    );

    if (c.ZSTD_isError(zstd_result) != 0) {
        // Maybe buffer too small, try larger
        if (frame_size == ZSTD_CONTENTSIZE_UNKNOWN) {
            // Overflow-safe multiplication
            const multiplied = @mulWithOverflow(output_size, 4);
            var new_size = if (multiplied[1] != 0) std.math.maxInt(usize) else multiplied[0];
            // Check limit before growing
            if (max_output_size) |limit| {
                if (new_size > limit) {
                    // Try with exactly the limit
                    new_size = limit;
                    if (new_size <= output_size) {
                        return Error.OutputTooLarge;
                    }
                }
            }

            // Use realloc to resize buffer (errdefer still protects us)
            output = allocator.realloc(output, new_size) catch return Error.OutOfMemory;

            const retry_result = if (dictionary) |dict| blk: {
                const dctx = c.ZSTD_createDCtx() orelse return Error.OutOfMemory;
                defer _ = c.ZSTD_freeDCtx(dctx);
                break :blk c.ZSTD_decompress_usingDict(
                    dctx,
                    output.ptr,
                    output.len,
                    input.ptr,
                    input.len,
                    dict.ptr,
                    dict.len,
                );
            } else c.ZSTD_decompress(
                output.ptr,
                output.len,
                input.ptr,
                input.len,
            );

            if (c.ZSTD_isError(retry_result) != 0) {
                // If we hit the limit and still failed, it's too large
                if (max_output_size != null and new_size == max_output_size.?) {
                    return Error.OutputTooLarge;
                }
                return Error.InvalidData;
            }

            return shrinkAllocation(allocator, output, retry_result);
        }
        return Error.InvalidData;
    }

    return shrinkAllocation(allocator, output, zstd_result);
}

/// Maximum compressed size estimate.
pub fn maxCompressedSize(input_size: usize) usize {
    return c.ZSTD_compressBound(input_size);
}

fn levelToZstdLevel(level: Level) c_int {
    return switch (level) {
        .fastest => 1,
        .fast => 3,
        .default => 3,
        .better => 9,
        .best => 19,
    };
}

// ============================================================================
// Streaming Decompressor
// ============================================================================

/// Streaming decompressor for Zstd data.
pub fn Decompressor(comptime ReaderType: type) type {
    return struct {
        const Self = @This();
        const BUFFER_SIZE = 16 * 1024;

        source: ReaderType,
        dstream: *c.ZSTD_DStream,
        allocator: std.mem.Allocator,
        input_buffer: [BUFFER_SIZE]u8,
        input_pos: usize,
        input_len: usize,
        finished: bool,

        pub const InitError = error{OutOfMemory};
        pub const ReadError = Error || ReaderType.Error;
        pub const Reader = std.io.GenericReader(*Self, ReadError, read);

        pub fn init(allocator: std.mem.Allocator, source: ReaderType) InitError!Self {
            const dstream = c.ZSTD_createDStream() orelse return error.OutOfMemory;

            if (c.ZSTD_isError(c.ZSTD_initDStream(dstream)) != 0) {
                _ = c.ZSTD_freeDStream(dstream);
                return error.OutOfMemory;
            }

            return Self{
                .source = source,
                .dstream = dstream,
                .allocator = allocator,
                .input_buffer = undefined,
                .input_pos = 0,
                .input_len = 0,
                .finished = false,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = c.ZSTD_freeDStream(self.dstream);
        }

        pub fn read(self: *Self, buffer: []u8) ReadError!usize {
            if (self.finished) return 0;
            if (buffer.len == 0) return 0;

            var output = c.ZSTD_outBuffer{
                .dst = buffer.ptr,
                .size = buffer.len,
                .pos = 0,
            };

            while (output.pos < output.size) {
                // Need more input?
                if (self.input_pos >= self.input_len) {
                    const bytes_read = self.source.read(&self.input_buffer) catch |e| {
                        return e;
                    };

                    if (bytes_read == 0) {
                        if (output.pos == 0) {
                            return Error.UnexpectedEof;
                        }
                        break;
                    }

                    self.input_pos = 0;
                    self.input_len = bytes_read;
                }

                var input = c.ZSTD_inBuffer{
                    .src = &self.input_buffer,
                    .size = self.input_len,
                    .pos = self.input_pos,
                };

                const result = c.ZSTD_decompressStream(self.dstream, &output, &input);
                self.input_pos = input.pos;

                if (c.ZSTD_isError(result) != 0) {
                    return Error.InvalidData;
                }

                if (result == 0) {
                    self.finished = true;
                    break;
                }
            }

            return output.pos;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}

// ============================================================================
// Streaming Compressor
// ============================================================================

/// Streaming compressor for Zstd data.
pub fn Compressor(comptime WriterType: type) type {
    return struct {
        const Self = @This();
        const BUFFER_SIZE = 16 * 1024;

        dest: WriterType,
        cstream: *c.ZSTD_CStream,
        allocator: std.mem.Allocator,
        output_buffer: [BUFFER_SIZE]u8,
        finished: bool,

        pub const Options = struct {
            level: Level = .default,
        };

        pub const InitError = error{OutOfMemory};
        pub const WriteError = Error || WriterType.Error;
        pub const Writer = std.io.GenericWriter(*Self, WriteError, write);

        pub fn init(allocator: std.mem.Allocator, dest: WriterType, options: Options) InitError!Self {
            const cstream = c.ZSTD_createCStream() orelse return error.OutOfMemory;

            const level: c_int = switch (options.level) {
                .fastest => 1,
                .fast => 3,
                .default => 3,
                .better => 9,
                .best => 19,
            };

            if (c.ZSTD_isError(c.ZSTD_initCStream(cstream, level)) != 0) {
                _ = c.ZSTD_freeCStream(cstream);
                return error.OutOfMemory;
            }

            return Self{
                .dest = dest,
                .cstream = cstream,
                .allocator = allocator,
                .output_buffer = undefined,
                .finished = false,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = c.ZSTD_freeCStream(self.cstream);
        }

        pub fn write(self: *Self, data: []const u8) WriteError!usize {
            if (self.finished) return 0;
            if (data.len == 0) return 0;

            var input = c.ZSTD_inBuffer{
                .src = data.ptr,
                .size = data.len,
                .pos = 0,
            };

            while (input.pos < input.size) {
                var output = c.ZSTD_outBuffer{
                    .dst = &self.output_buffer,
                    .size = BUFFER_SIZE,
                    .pos = 0,
                };

                const result = c.ZSTD_compressStream(self.cstream, &output, &input);

                if (c.ZSTD_isError(result) != 0) {
                    return Error.InvalidData;
                }

                if (output.pos > 0) {
                    self.dest.writeAll(self.output_buffer[0..output.pos]) catch |e| {
                        return e;
                    };
                }
            }

            return data.len;
        }

        pub fn flush(self: *Self) WriteError!void {
            if (self.finished) return;

            while (true) {
                var output = c.ZSTD_outBuffer{
                    .dst = &self.output_buffer,
                    .size = BUFFER_SIZE,
                    .pos = 0,
                };

                const result = c.ZSTD_flushStream(self.cstream, &output);

                if (output.pos > 0) {
                    self.dest.writeAll(self.output_buffer[0..output.pos]) catch |e| {
                        return e;
                    };
                }

                if (c.ZSTD_isError(result) != 0) {
                    return Error.InvalidData;
                }

                if (result == 0) break;
            }
        }

        pub fn finish(self: *Self) WriteError!void {
            if (self.finished) return;

            while (true) {
                var output = c.ZSTD_outBuffer{
                    .dst = &self.output_buffer,
                    .size = BUFFER_SIZE,
                    .pos = 0,
                };

                const result = c.ZSTD_endStream(self.cstream, &output);

                if (output.pos > 0) {
                    self.dest.writeAll(self.output_buffer[0..output.pos]) catch |e| {
                        return e;
                    };
                }

                if (c.ZSTD_isError(result) != 0) {
                    return Error.InvalidData;
                }

                if (result == 0) {
                    self.finished = true;
                    break;
                }
            }
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, Zstd! This is a test of the compression algorithm. " ++
        "Repeated text helps compression: Hello Hello Hello Hello Hello.";

    const compressed = try compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Should actually compress
    try std.testing.expect(compressed.len < input.len);

    const decompressed = try decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "empty input" {
    const allocator = std.testing.allocator;

    const compressed = try compress("", allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings("", decompressed);
}

test "compression levels" {
    const allocator = std.testing.allocator;
    const input = "Test data for compression level testing. " ** 10;

    for ([_]Level{ .fast, .default, .best }) |level| {
        const compressed = try compress(input, allocator, .{ .level = level });
        defer allocator.free(compressed);

        const decompressed = try decompress(compressed, allocator, .{});
        defer allocator.free(decompressed);

        try std.testing.expectEqualStrings(input, decompressed);
    }
}

test "max_output_size limit" {
    const allocator = std.testing.allocator;
    const input = "Test data for size limit validation.";

    const compressed = try compress(input, allocator, .{});
    defer allocator.free(compressed);

    const result = decompress(compressed, allocator, .{ .max_output_size = 10 });
    try std.testing.expectError(Error.OutputTooLarge, result);
}

test "streaming round-trip" {
    const allocator = std.testing.allocator;
    const input = "Hello, streaming zstd compression! " ** 100;

    // Compress
    var compressed_buf: [32768]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();

    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(output);

    try std.testing.expectEqualStrings(input, output);
}

test "streaming empty input" {
    const allocator = std.testing.allocator;

    var compressed_buf: [256]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.finish();

    const compressed = compressed_stream.getWritten();
    try std.testing.expect(compressed.len > 0);

    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(output);

    try std.testing.expectEqual(@as(usize, 0), output.len);
}

test "streaming compression levels" {
    const allocator = std.testing.allocator;
    const input = "Test data for compression level comparison. " ** 50;

    for ([_]Level{ .fastest, .default, .best }) |level| {
        var compressed_buf: [8192]u8 = undefined;
        var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

        var comp = try Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{ .level = level });
        defer comp.deinit();

        try comp.writer().writeAll(input);
        try comp.finish();

        const compressed = compressed_stream.getWritten();

        var fbs = std.io.fixedBufferStream(compressed);
        var decomp = try Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
        defer decomp.deinit();

        const output = try decomp.reader().readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(output);

        try std.testing.expectEqualStrings(input, output);
    }
}

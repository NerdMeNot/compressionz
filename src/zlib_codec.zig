//! Zlib and raw Deflate compression/decompression.
//!
//! - **Zlib format**: deflate + zlib header (2 bytes) + adler32 checksum
//! - **Deflate format**: raw deflate with no headers or checksums
//!
//! Both formats support dictionary compression for improved ratios on small data.
//!
//! ## One-shot API
//! ```zig
//! const cz = @import("compressionz");
//!
//! // Zlib format
//! const compressed = try cz.zlib.compress(input, allocator, .{});
//! const decompressed = try cz.zlib.decompress(compressed, allocator, .{});
//!
//! // Deflate format (raw, no headers)
//! const compressed = try cz.zlib.compressDeflate(input, allocator, .{});
//! const decompressed = try cz.zlib.decompressDeflate(compressed, allocator, .{});
//! ```
//!
//! ## Dictionary Compression
//! ```zig
//! const compressed = try cz.zlib.compressWithDict(input, dict, allocator, .{});
//! const decompressed = try cz.zlib.decompressWithDict(compressed, dict, allocator, .{});
//! ```
//!
//! ## Streaming API
//! ```zig
//! // Zlib streaming
//! var comp = try cz.zlib.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
//! var decomp = try cz.zlib.Decompressor(@TypeOf(reader)).init(allocator, reader);
//!
//! // Deflate streaming
//! var comp = try cz.zlib.DeflateCompressor(@TypeOf(writer)).init(allocator, writer, .{});
//! var decomp = try cz.zlib.DeflateDecompressor(@TypeOf(reader)).init(allocator, reader);
//! ```

const std = @import("std");
const err = @import("error.zig");
const Error = err.Error;
const shrinkAllocation = err.shrinkAllocation;
const Level = @import("level.zig").Level;

const c = @cImport({
    @cInclude("zlib.h");
});

// Zlib windowBits constants
const ZLIB_WINDOW_BITS = 15;
const RAW_DEFLATE_WINDOW_BITS = -15; // Negative for raw deflate

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
// One-shot Zlib API
// ============================================================================

/// Compress data with zlib format.
/// Caller owns returned slice and must free with allocator.
pub fn compress(input: []const u8, allocator: std.mem.Allocator, options: CompressOptions) Error![]u8 {
    return compressWithDict(input, null, allocator, options);
}

/// Compress data with zlib format using a dictionary.
/// Dictionary compression can significantly improve ratios for small data with known patterns.
/// Caller owns returned slice and must free with allocator.
pub fn compressWithDict(
    input: []const u8,
    dictionary: ?[]const u8,
    allocator: std.mem.Allocator,
    options: CompressOptions,
) Error![]u8 {
    return compressInternal(input, dictionary, allocator, options, ZLIB_WINDOW_BITS);
}

/// Decompress zlib format data.
/// Caller owns returned slice and must free with allocator.
pub fn decompress(input: []const u8, allocator: std.mem.Allocator, options: DecompressOptions) Error![]u8 {
    return decompressWithDict(input, null, allocator, options);
}

/// Decompress zlib format data using a dictionary.
/// Caller owns returned slice and must free with allocator.
pub fn decompressWithDict(
    input: []const u8,
    dictionary: ?[]const u8,
    allocator: std.mem.Allocator,
    options: DecompressOptions,
) Error![]u8 {
    return decompressInternal(input, dictionary, allocator, options, ZLIB_WINDOW_BITS);
}

// ============================================================================
// One-shot Deflate API (raw, no headers)
// ============================================================================

/// Compress data with raw deflate format (no headers).
/// Caller owns returned slice and must free with allocator.
pub fn compressDeflate(input: []const u8, allocator: std.mem.Allocator, options: CompressOptions) Error![]u8 {
    return compressDeflateWithDict(input, null, allocator, options);
}

/// Compress data with raw deflate format using a dictionary.
/// Caller owns returned slice and must free with allocator.
pub fn compressDeflateWithDict(
    input: []const u8,
    dictionary: ?[]const u8,
    allocator: std.mem.Allocator,
    options: CompressOptions,
) Error![]u8 {
    return compressInternal(input, dictionary, allocator, options, RAW_DEFLATE_WINDOW_BITS);
}

/// Decompress raw deflate format data.
/// Caller owns returned slice and must free with allocator.
pub fn decompressDeflate(input: []const u8, allocator: std.mem.Allocator, options: DecompressOptions) Error![]u8 {
    return decompressDeflateWithDict(input, null, allocator, options);
}

/// Decompress raw deflate format data using a dictionary.
/// Caller owns returned slice and must free with allocator.
pub fn decompressDeflateWithDict(
    input: []const u8,
    dictionary: ?[]const u8,
    allocator: std.mem.Allocator,
    options: DecompressOptions,
) Error![]u8 {
    return decompressInternal(input, dictionary, allocator, options, RAW_DEFLATE_WINDOW_BITS);
}

// ============================================================================
// Internal compression/decompression
// ============================================================================

fn compressInternal(
    input: []const u8,
    dictionary: ?[]const u8,
    allocator: std.mem.Allocator,
    options: CompressOptions,
    window_bits: c_int,
) Error![]u8 {
    if (input.len == 0) {
        return allocator.alloc(u8, 0) catch return Error.OutOfMemory;
    }

    const max_size = maxCompressedSize(input.len);
    const output = allocator.alloc(u8, max_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    var stream: c.z_stream = std.mem.zeroes(c.z_stream);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    stream.next_out = output.ptr;
    stream.avail_out = @intCast(output.len);

    const zlib_level = levelToZlibLevel(options.level);

    if (c.deflateInit2(
        &stream,
        zlib_level,
        c.Z_DEFLATED,
        window_bits,
        8, // memLevel
        c.Z_DEFAULT_STRATEGY,
    ) != c.Z_OK) {
        return Error.OutOfMemory;
    }
    defer _ = c.deflateEnd(&stream);

    // Set dictionary if provided
    if (dictionary) |dict| {
        if (c.deflateSetDictionary(&stream, dict.ptr, @intCast(dict.len)) != c.Z_OK) {
            return Error.InvalidData;
        }
    }

    const zlib_result = c.deflate(&stream, c.Z_FINISH);
    if (zlib_result != c.Z_STREAM_END) {
        return Error.InvalidData;
    }

    const written = output.len - stream.avail_out;
    return shrinkAllocation(allocator, output, written);
}

fn decompressInternal(
    input: []const u8,
    dictionary: ?[]const u8,
    allocator: std.mem.Allocator,
    options: DecompressOptions,
    window_bits: c_int,
) Error![]u8 {
    const max_output_size = options.max_output_size;

    if (input.len == 0) {
        return allocator.alloc(u8, 0) catch return Error.OutOfMemory;
    }

    var output_size: usize = input.len * 4;
    if (output_size < 1024) output_size = 1024;

    // Cap initial allocation at limit if set
    if (max_output_size) |limit| {
        output_size = @min(output_size, limit);
    }

    var output = allocator.alloc(u8, output_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    var stream: c.z_stream = std.mem.zeroes(c.z_stream);
    stream.next_in = @constCast(input.ptr);
    stream.avail_in = @intCast(input.len);
    stream.next_out = output.ptr;
    stream.avail_out = @intCast(output.len);

    if (c.inflateInit2(&stream, window_bits) != c.Z_OK) {
        return Error.OutOfMemory;
    }
    defer _ = c.inflateEnd(&stream);

    // Set dictionary if provided (for raw deflate with dictionary, set it before first inflate)
    if (dictionary) |dict| {
        if (window_bits < 0) { // Raw deflate
            if (c.inflateSetDictionary(&stream, dict.ptr, @intCast(dict.len)) != c.Z_OK) {
                return Error.InvalidData;
            }
        }
    }

    while (true) {
        const zlib_result = c.inflate(&stream, c.Z_NO_FLUSH);

        switch (zlib_result) {
            c.Z_STREAM_END => {
                const written = output.len - stream.avail_out;
                return shrinkAllocation(allocator, output, written);
            },
            c.Z_NEED_DICT => {
                // Stream requires dictionary
                if (dictionary) |dict| {
                    if (c.inflateSetDictionary(&stream, dict.ptr, @intCast(dict.len)) != c.Z_OK) {
                        return Error.InvalidData;
                    }
                    // Continue decompression after setting dictionary
                    continue;
                }
                return Error.InvalidData; // Dictionary required but not provided
            },
            c.Z_OK, c.Z_BUF_ERROR => {
                if (stream.avail_out == 0) {
                    // Need more output space
                    const written = output.len - stream.avail_out;
                    // Overflow-safe multiplication
                    const doubled = @mulWithOverflow(output.len, 2);
                    var new_size = if (doubled[1] != 0) std.math.maxInt(usize) else doubled[0];

                    // Check limit before growing
                    if (max_output_size) |limit| {
                        if (written >= limit) {
                            return Error.OutputTooLarge;
                        }
                        new_size = @min(new_size, limit);
                        if (new_size <= written) {
                            return Error.OutputTooLarge;
                        }
                    }

                    // Use realloc for efficiency (may resize in-place)
                    output = allocator.realloc(output, new_size) catch return Error.OutOfMemory;
                    stream.next_out = output.ptr + written;
                    stream.avail_out = @intCast(output.len - written);
                } else {
                    return Error.UnexpectedEof;
                }
            },
            else => return Error.InvalidData,
        }
    }
}

/// Maximum compressed size estimate.
/// Returns maxInt on overflow.
pub fn maxCompressedSize(input_size: usize) usize {
    // Conservative estimate: input + 0.1% + 12 bytes overhead + 6 for zlib header/trailer
    const overhead = input_size >> 10;
    var result = @addWithOverflow(input_size, overhead);
    if (result[1] != 0) return std.math.maxInt(usize);
    result = @addWithOverflow(result[0], 18); // 12 + 6
    if (result[1] != 0) return std.math.maxInt(usize);
    return result[0];
}

fn levelToZlibLevel(level: Level) c_int {
    return switch (level) {
        .fastest => 1,
        .fast => 3,
        .default => 6,
        .better => 7,
        .best => 9,
    };
}

// ============================================================================
// Streaming Zlib Decompressor
// ============================================================================

/// Streaming decompressor for zlib format data.
pub fn Decompressor(comptime ReaderType: type) type {
    return DecompressorInternal(ReaderType, ZLIB_WINDOW_BITS);
}

/// Streaming decompressor for raw deflate format data.
pub fn DeflateDecompressor(comptime ReaderType: type) type {
    return DecompressorInternal(ReaderType, RAW_DEFLATE_WINDOW_BITS);
}

fn DecompressorInternal(comptime ReaderType: type, comptime window_bits: c_int) type {
    return struct {
        const Self = @This();
        const BUFFER_SIZE = 16 * 1024;

        source: ReaderType,
        z: *c.z_stream,
        allocator: std.mem.Allocator,
        input_buffer: [BUFFER_SIZE]u8,
        finished: bool,

        pub const InitError = error{OutOfMemory};
        pub const ReadError = Error || ReaderType.Error;
        pub const Reader = std.io.GenericReader(*Self, ReadError, read);

        pub fn init(allocator: std.mem.Allocator, source: ReaderType) InitError!Self {
            const z = allocator.create(c.z_stream) catch return error.OutOfMemory;
            z.* = std.mem.zeroes(c.z_stream);

            if (c.inflateInit2(z, window_bits) != c.Z_OK) {
                allocator.destroy(z);
                return error.OutOfMemory;
            }

            return Self{
                .source = source,
                .z = z,
                .allocator = allocator,
                .input_buffer = undefined,
                .finished = false,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = c.inflateEnd(self.z);
            self.allocator.destroy(self.z);
        }

        pub fn read(self: *Self, buffer: []u8) ReadError!usize {
            if (self.finished) return 0;
            if (buffer.len == 0) return 0;

            self.z.next_out = buffer.ptr;
            self.z.avail_out = @intCast(buffer.len);

            while (self.z.avail_out > 0) {
                if (self.z.avail_in == 0) {
                    const bytes_read = self.source.read(&self.input_buffer) catch |e| {
                        return e;
                    };

                    if (bytes_read == 0) {
                        if (self.z.avail_out == buffer.len) {
                            return Error.UnexpectedEof;
                        }
                        break;
                    }

                    self.z.next_in = &self.input_buffer;
                    self.z.avail_in = @intCast(bytes_read);
                }

                const result = c.inflate(self.z, c.Z_NO_FLUSH);

                switch (result) {
                    c.Z_STREAM_END => {
                        self.finished = true;
                        break;
                    },
                    c.Z_OK, c.Z_BUF_ERROR => {
                        if (result == c.Z_BUF_ERROR and self.z.avail_in > 0 and self.z.avail_out > 0) {
                            return Error.InvalidData;
                        }
                    },
                    c.Z_DATA_ERROR => return Error.InvalidData,
                    c.Z_MEM_ERROR => return Error.OutOfMemory,
                    else => return Error.InvalidData,
                }
            }

            return buffer.len - self.z.avail_out;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}

// ============================================================================
// Streaming Zlib Compressor
// ============================================================================

/// Streaming compressor for zlib format data.
pub fn Compressor(comptime WriterType: type) type {
    return CompressorInternal(WriterType, ZLIB_WINDOW_BITS);
}

/// Streaming compressor for raw deflate format data.
pub fn DeflateCompressor(comptime WriterType: type) type {
    return CompressorInternal(WriterType, RAW_DEFLATE_WINDOW_BITS);
}

fn CompressorInternal(comptime WriterType: type, comptime window_bits: c_int) type {
    return struct {
        const Self = @This();
        const BUFFER_SIZE = 16 * 1024;

        dest: WriterType,
        z: *c.z_stream,
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
            const z = allocator.create(c.z_stream) catch return error.OutOfMemory;
            z.* = std.mem.zeroes(c.z_stream);

            const zlib_level: c_int = switch (options.level) {
                .fastest => 1,
                .fast => 3,
                .default => 6,
                .better => 7,
                .best => 9,
            };

            if (c.deflateInit2(
                z,
                zlib_level,
                c.Z_DEFLATED,
                window_bits,
                8,
                c.Z_DEFAULT_STRATEGY,
            ) != c.Z_OK) {
                allocator.destroy(z);
                return error.OutOfMemory;
            }

            return Self{
                .dest = dest,
                .z = z,
                .allocator = allocator,
                .output_buffer = undefined,
                .finished = false,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = c.deflateEnd(self.z);
            self.allocator.destroy(self.z);
        }

        pub fn write(self: *Self, data: []const u8) WriteError!usize {
            if (self.finished) return 0;
            if (data.len == 0) return 0;

            self.z.next_in = @constCast(data.ptr);
            self.z.avail_in = @intCast(data.len);

            while (self.z.avail_in > 0) {
                self.z.next_out = &self.output_buffer;
                self.z.avail_out = BUFFER_SIZE;

                const result = c.deflate(self.z, c.Z_NO_FLUSH);

                if (result != c.Z_OK and result != c.Z_BUF_ERROR) {
                    return Error.InvalidData;
                }

                const produced = BUFFER_SIZE - self.z.avail_out;
                if (produced > 0) {
                    self.dest.writeAll(self.output_buffer[0..produced]) catch |e| {
                        return e;
                    };
                }
            }

            return data.len;
        }

        pub fn flush(self: *Self) WriteError!void {
            if (self.finished) return;

            while (true) {
                self.z.next_out = &self.output_buffer;
                self.z.avail_out = BUFFER_SIZE;

                const result = c.deflate(self.z, c.Z_SYNC_FLUSH);

                const produced = BUFFER_SIZE - self.z.avail_out;
                if (produced > 0) {
                    self.dest.writeAll(self.output_buffer[0..produced]) catch |e| {
                        return e;
                    };
                }

                if (result == c.Z_BUF_ERROR or self.z.avail_out > 0) {
                    break;
                }
            }
        }

        pub fn finish(self: *Self) WriteError!void {
            if (self.finished) return;

            while (true) {
                self.z.next_out = &self.output_buffer;
                self.z.avail_out = BUFFER_SIZE;

                const result = c.deflate(self.z, c.Z_FINISH);

                const produced = BUFFER_SIZE - self.z.avail_out;
                if (produced > 0) {
                    self.dest.writeAll(self.output_buffer[0..produced]) catch |e| {
                        return e;
                    };
                }

                if (result == c.Z_STREAM_END) {
                    self.finished = true;
                    break;
                }

                if (result != c.Z_OK and result != c.Z_BUF_ERROR) {
                    return Error.InvalidData;
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

test "zlib compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, Zlib! This is a test of the compression algorithm. " ++
        "Repeated text helps compression: Hello Hello Hello Hello Hello.";

    const compressed = try compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Should actually compress
    try std.testing.expect(compressed.len < input.len);

    const decompressed = try decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "deflate compress and decompress" {
    const allocator = std.testing.allocator;
    const input = "Hello, Deflate! Raw deflate without headers. " ++
        "Repeated text helps compression: Test Test Test Test Test.";

    const compressed = try compressDeflate(input, allocator, .{});
    defer allocator.free(compressed);

    // Should actually compress
    try std.testing.expect(compressed.len < input.len);

    const decompressed = try decompressDeflate(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "zlib empty input" {
    const allocator = std.testing.allocator;

    const compressed = try compress("", allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings("", decompressed);
}

test "zlib compression levels" {
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

test "zlib decompress invalid data" {
    const allocator = std.testing.allocator;
    const invalid_data = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    const result = decompress(&invalid_data, allocator, .{});
    try std.testing.expectError(Error.InvalidData, result);
}

test "deflate decompress invalid data" {
    const allocator = std.testing.allocator;
    const invalid_data = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    const result = decompressDeflate(&invalid_data, allocator, .{});
    try std.testing.expectError(Error.InvalidData, result);
}

test "zlib decompress with size limit" {
    const allocator = std.testing.allocator;
    const input = "Test data for size limit validation in zlib format.";

    const compressed = try compress(input, allocator, .{});
    defer allocator.free(compressed);

    const result = decompress(compressed, allocator, .{ .max_output_size = 10 });
    try std.testing.expectError(Error.OutputTooLarge, result);
}

test "zlib maxCompressedSize overflow" {
    const huge = std.math.maxInt(usize) - 10;
    const result = maxCompressedSize(huge);
    try std.testing.expectEqual(std.math.maxInt(usize), result);
}

test "zlib streaming round-trip" {
    const allocator = std.testing.allocator;
    const input = "Hello, streaming zlib compression! " ** 100;

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

test "deflate streaming round-trip" {
    const allocator = std.testing.allocator;
    const input = "Hello, streaming deflate compression! " ** 100;

    // Compress
    var compressed_buf: [32768]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try DeflateCompressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();

    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try DeflateDecompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    const output = try decomp.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(output);

    try std.testing.expectEqualStrings(input, output);
}

test "zlib streaming empty input" {
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

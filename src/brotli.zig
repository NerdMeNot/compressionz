//! Brotli compression and decompression.
//!
//! Brotli provides excellent compression ratios, especially for web content.
//! It's the standard compression for WOFF2 fonts and is widely supported in browsers.
//!
//! ## One-shot API
//! ```zig
//! const cz = @import("compressionz");
//!
//! const compressed = try cz.brotli.compress(input, allocator, .{});
//! defer allocator.free(compressed);
//!
//! const decompressed = try cz.brotli.decompress(compressed, allocator, .{});
//! defer allocator.free(decompressed);
//! ```
//!
//! ## Streaming API
//! ```zig
//! // Compression
//! var comp = try cz.brotli.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
//! defer comp.deinit();
//! try comp.writer().writeAll(data);
//! try comp.finish();
//!
//! // Decompression
//! var decomp = try cz.brotli.Decompressor(@TypeOf(reader)).init(allocator, reader);
//! defer decomp.deinit();
//! const data = try decomp.reader().readAllAlloc(allocator, max_size);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const err = @import("error.zig");
const Error = err.Error;
const shrinkAllocation = err.shrinkAllocation;
const Level = @import("level.zig").Level;

const c = @cImport({
    @cInclude("brotli/decode.h");
    @cInclude("brotli/encode.h");
});

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

/// Compress data using Brotli.
/// Caller owns returned slice and must free with allocator.
pub fn compress(input: []const u8, allocator: Allocator, options: CompressOptions) Error![]u8 {
    if (input.len == 0) {
        return allocator.alloc(u8, 0) catch return Error.OutOfMemory;
    }

    const quality = levelToQuality(options.level);

    // Calculate max output size
    const max_size = c.BrotliEncoderMaxCompressedSize(input.len);
    if (max_size == 0) {
        return Error.InvalidData;
    }

    const output = allocator.alloc(u8, max_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    var encoded_size: usize = max_size;
    const brotli_result = c.BrotliEncoderCompress(
        quality,
        c.BROTLI_DEFAULT_WINDOW,
        c.BROTLI_MODE_GENERIC,
        input.len,
        input.ptr,
        &encoded_size,
        output.ptr,
    );

    if (brotli_result != c.BROTLI_TRUE) {
        return Error.InvalidData;
    }

    return shrinkAllocation(allocator, output, encoded_size);
}

/// Decompress Brotli data.
/// Caller owns returned slice and must free with allocator.
pub fn decompress(input: []const u8, allocator: Allocator, options: DecompressOptions) Error![]u8 {
    const max_output_size = options.max_output_size;

    if (input.len == 0) {
        return allocator.alloc(u8, 0) catch return Error.OutOfMemory;
    }

    // Start with a reasonable initial size
    var output_size: usize = input.len * 4;
    if (output_size < 1024) output_size = 1024;

    // Cap initial allocation at limit if set
    if (max_output_size) |limit| {
        output_size = @min(output_size, limit);
    }

    var output = allocator.alloc(u8, output_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    // Create decoder state
    const state = c.BrotliDecoderCreateInstance(null, null, null);
    if (state == null) {
        return Error.OutOfMemory;
    }
    defer c.BrotliDecoderDestroyInstance(state);

    var available_in: usize = input.len;
    var next_in: [*c]const u8 = input.ptr;
    var available_out: usize = output_size;
    var next_out: [*c]u8 = output.ptr;
    var total_out: usize = 0;

    while (true) {
        const brotli_result = c.BrotliDecoderDecompressStream(
            state,
            &available_in,
            &next_in,
            &available_out,
            &next_out,
            &total_out,
        );

        switch (brotli_result) {
            c.BROTLI_DECODER_RESULT_SUCCESS => {
                return shrinkAllocation(allocator, output, total_out);
            },
            c.BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT => {
                // Grow output buffer (with overflow protection)
                const doubled = @mulWithOverflow(output_size, 2);
                var new_size = if (doubled[1] != 0) std.math.maxInt(usize) else doubled[0];

                // Check limit before growing
                if (max_output_size) |limit| {
                    if (total_out >= limit) {
                        return Error.OutputTooLarge;
                    }
                    new_size = @min(new_size, limit);
                    if (new_size <= total_out) {
                        return Error.OutputTooLarge;
                    }
                }

                // Use realloc for efficiency (may resize in-place)
                output = allocator.realloc(output, new_size) catch return Error.OutOfMemory;
                output_size = new_size;
                available_out = output_size - total_out;
                next_out = output.ptr + total_out;
            },
            c.BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT => {
                return Error.UnexpectedEof;
            },
            else => {
                return Error.InvalidData;
            },
        }
    }
}

/// Calculate maximum compressed size for buffer allocation.
/// Returns maxInt on overflow.
pub fn maxCompressedSize(input_size: usize) usize {
    const size = c.BrotliEncoderMaxCompressedSize(input_size);
    if (size == 0) {
        // Brotli returns 0 for very large inputs; use safe fallback
        const result = @addWithOverflow(input_size, 1024);
        return if (result[1] != 0) std.math.maxInt(usize) else result[0];
    }
    return size;
}

fn levelToQuality(level: Level) c_int {
    return switch (level) {
        .fastest => 1,
        .fast => 4,
        .default => 6,
        .better => 9,
        .best => 11,
    };
}

// ============================================================================
// Streaming Decompressor
// ============================================================================

/// Streaming decompressor for Brotli data.
pub fn Decompressor(comptime ReaderType: type) type {
    return struct {
        const Self = @This();
        const BUFFER_SIZE = 16 * 1024;

        source: ReaderType,
        state: *c.BrotliDecoderState,
        allocator: Allocator,
        input_buffer: [BUFFER_SIZE]u8,
        input_ptr: [*c]const u8,
        input_avail: usize,
        finished: bool,

        pub const InitError = error{OutOfMemory};
        pub const ReadError = Error || ReaderType.Error;
        pub const Reader = std.io.GenericReader(*Self, ReadError, read);

        pub fn init(allocator: Allocator, source: ReaderType) InitError!Self {
            const state = c.BrotliDecoderCreateInstance(null, null, null) orelse return error.OutOfMemory;

            return Self{
                .source = source,
                .state = state,
                .allocator = allocator,
                .input_buffer = undefined,
                .input_ptr = undefined,
                .input_avail = 0,
                .finished = false,
            };
        }

        pub fn deinit(self: *Self) void {
            c.BrotliDecoderDestroyInstance(self.state);
        }

        pub fn read(self: *Self, buffer: []u8) ReadError!usize {
            if (self.finished) return 0;
            if (buffer.len == 0) return 0;

            var output_ptr: [*c]u8 = buffer.ptr;
            var output_avail: usize = buffer.len;
            var total_out: usize = 0;

            while (output_avail > 0) {
                // Need more input?
                if (self.input_avail == 0) {
                    const bytes_read = self.source.read(&self.input_buffer) catch |e| {
                        return e;
                    };

                    if (bytes_read == 0) {
                        if (output_avail == buffer.len) {
                            return Error.UnexpectedEof;
                        }
                        break;
                    }

                    self.input_ptr = &self.input_buffer;
                    self.input_avail = bytes_read;
                }

                const result = c.BrotliDecoderDecompressStream(
                    self.state,
                    &self.input_avail,
                    &self.input_ptr,
                    &output_avail,
                    &output_ptr,
                    &total_out,
                );

                switch (result) {
                    c.BROTLI_DECODER_RESULT_SUCCESS => {
                        self.finished = true;
                        break;
                    },
                    c.BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT => {
                        // Continue to read more
                    },
                    c.BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT => {
                        // Output buffer full, return what we have
                        break;
                    },
                    else => return Error.InvalidData,
                }
            }

            return buffer.len - output_avail;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}

// ============================================================================
// Streaming Compressor
// ============================================================================

/// Streaming compressor for Brotli data.
pub fn Compressor(comptime WriterType: type) type {
    return struct {
        const Self = @This();
        const BUFFER_SIZE = 16 * 1024;

        dest: WriterType,
        state: *c.BrotliEncoderState,
        allocator: Allocator,
        output_buffer: [BUFFER_SIZE]u8,
        finished: bool,

        pub const Options = struct {
            level: Level = .default,
        };

        pub const InitError = error{OutOfMemory};
        pub const WriteError = Error || WriterType.Error;
        pub const Writer = std.io.GenericWriter(*Self, WriteError, write);

        pub fn init(allocator: Allocator, dest: WriterType, options: Options) InitError!Self {
            const state = c.BrotliEncoderCreateInstance(null, null, null) orelse return error.OutOfMemory;

            const quality: u32 = switch (options.level) {
                .fastest => 1,
                .fast => 4,
                .default => 6,
                .better => 9,
                .best => 11,
            };

            _ = c.BrotliEncoderSetParameter(state, c.BROTLI_PARAM_QUALITY, quality);

            return Self{
                .dest = dest,
                .state = state,
                .allocator = allocator,
                .output_buffer = undefined,
                .finished = false,
            };
        }

        pub fn deinit(self: *Self) void {
            c.BrotliEncoderDestroyInstance(self.state);
        }

        pub fn write(self: *Self, data: []const u8) WriteError!usize {
            if (self.finished) return 0;
            if (data.len == 0) return 0;

            var input_ptr: [*c]const u8 = data.ptr;
            var input_avail: usize = data.len;

            while (input_avail > 0) {
                var output_ptr: [*c]u8 = &self.output_buffer;
                var output_avail: usize = BUFFER_SIZE;

                if (c.BrotliEncoderCompressStream(
                    self.state,
                    c.BROTLI_OPERATION_PROCESS,
                    &input_avail,
                    &input_ptr,
                    &output_avail,
                    &output_ptr,
                    null,
                ) != c.BROTLI_TRUE) {
                    return Error.InvalidData;
                }

                const produced = BUFFER_SIZE - output_avail;
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
                var input_avail: usize = 0;
                var input_ptr: [*c]const u8 = undefined;
                var output_ptr: [*c]u8 = &self.output_buffer;
                var output_avail: usize = BUFFER_SIZE;

                if (c.BrotliEncoderCompressStream(
                    self.state,
                    c.BROTLI_OPERATION_FLUSH,
                    &input_avail,
                    &input_ptr,
                    &output_avail,
                    &output_ptr,
                    null,
                ) != c.BROTLI_TRUE) {
                    return Error.InvalidData;
                }

                const produced = BUFFER_SIZE - output_avail;
                if (produced > 0) {
                    self.dest.writeAll(self.output_buffer[0..produced]) catch |e| {
                        return e;
                    };
                }

                if (c.BrotliEncoderHasMoreOutput(self.state) == 0) {
                    break;
                }
            }
        }

        pub fn finish(self: *Self) WriteError!void {
            if (self.finished) return;

            while (true) {
                var input_avail: usize = 0;
                var input_ptr: [*c]const u8 = undefined;
                var output_ptr: [*c]u8 = &self.output_buffer;
                var output_avail: usize = BUFFER_SIZE;

                if (c.BrotliEncoderCompressStream(
                    self.state,
                    c.BROTLI_OPERATION_FINISH,
                    &input_avail,
                    &input_ptr,
                    &output_avail,
                    &output_ptr,
                    null,
                ) != c.BROTLI_TRUE) {
                    return Error.InvalidData;
                }

                const produced = BUFFER_SIZE - output_avail;
                if (produced > 0) {
                    self.dest.writeAll(self.output_buffer[0..produced]) catch |e| {
                        return e;
                    };
                }

                if (c.BrotliEncoderIsFinished(self.state) != 0) {
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
    const input = "Hello, Brotli! This is a test of the compression algorithm. " ++
        "Repeated text helps compression: Hello Hello Hello Hello Hello.";

    const compressed = try compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Brotli should actually compress this
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

    // Test different levels
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
    const input = "Hello, streaming brotli compression! " ** 100;

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

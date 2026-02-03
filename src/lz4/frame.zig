//! LZ4 frame format compression and decompression.
//!
//! The frame format is the recommended way to use LZ4. It includes:
//! - Magic number (4 bytes): 0x184D2204
//! - Frame descriptor (3-15 bytes)
//! - Data blocks (variable)
//! - End mark (4 bytes of zeros)
//! - Optional content checksum (4 bytes)
//!
//! ## One-shot API
//! ```zig
//! const cz = @import("compressionz");
//!
//! const compressed = try cz.lz4.frame.compress(input, allocator, .{});
//! defer allocator.free(compressed);
//!
//! const decompressed = try cz.lz4.frame.decompress(compressed, allocator, .{});
//! defer allocator.free(decompressed);
//! ```
//!
//! ## Streaming API
//! ```zig
//! // Compression
//! var comp = try cz.lz4.frame.Compressor(@TypeOf(writer)).init(allocator, writer, .{});
//! defer comp.deinit();
//! try comp.writer().writeAll(data);
//! try comp.finish();
//!
//! // Decompression
//! var decomp = try cz.lz4.frame.Decompressor(@TypeOf(reader)).init(allocator, reader);
//! defer decomp.deinit();
//! const data = try decomp.reader().readAllAlloc(allocator, max_size);
//! ```
//!
//! ## In-place API
//! ```zig
//! // For when you want to manage your own buffers
//! const result = try cz.lz4.frame.compressInto(input, output_buffer, .{});
//! const result = try cz.lz4.frame.decompressInto(compressed, output_buffer);
//! ```

const std = @import("std");
const Error = @import("../error.zig").Error;
const Level = @import("../level.zig").Level;
const lz4 = @import("lz4.zig");
const lz4_block = @import("block.zig");

const MAGIC = 0x184D2204;
const MIN_FRAME_SIZE = 7; // Magic (4) + FLG/BD (2) + HC (1)

// ============================================================================
// Options
// ============================================================================

/// Options for one-shot compression.
pub const CompressOptions = struct {
    block_size: lz4.BlockSize = .default,
    block_mode: lz4.BlockMode = .independent,
    content_checksum: bool = true,
    content_size: ?usize = null,
    dictionary_id: ?u32 = null,
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

/// Compress data into LZ4 frame format.
/// Caller owns returned slice and must free with allocator.
pub fn compress(input: []const u8, allocator: std.mem.Allocator, options: CompressOptions) Error![]u8 {
    // Calculate maximum output size
    const block_max = options.block_size.bytes();
    const num_blocks = if (input.len == 0) 1 else (input.len + block_max - 1) / block_max;
    const max_block_overhead = num_blocks * (4 + lz4_block.maxCompressedSize(block_max) - block_max);
    const frame_overhead = 15 + 4 + 4; // Header + end mark + checksum
    const max_size = input.len + max_block_overhead + frame_overhead;

    const output = allocator.alloc(u8, max_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    const result = try compressInto(input, output, options);
    return shrinkAllocation(allocator, output, result.len);
}

/// Compress into provided buffer.
/// Returns slice of written data.
pub fn compressInto(input: []const u8, output: []u8, options: CompressOptions) Error![]u8 {
    var dst: usize = 0;

    // Write magic number
    if (output.len < MIN_FRAME_SIZE) return Error.OutputTooSmall;
    std.mem.writeInt(u32, output[dst..][0..4], MAGIC, .little);
    dst += 4;

    // Build frame descriptor
    var flg: u8 = 0x40; // Version = 01 (bits 6-7)
    if (options.block_mode == .independent) {
        flg |= 0x20; // Block independence (bit 5)
    }
    if (options.content_checksum) {
        flg |= 0x04; // Content checksum (bit 2)
    }
    if (options.content_size != null) {
        flg |= 0x08; // Content size (bit 3)
    }

    const bd: u8 = @as(u8, @intFromEnum(options.block_size)) << 4;

    output[dst] = flg;
    dst += 1;
    output[dst] = bd;
    dst += 1;

    // Write content size if present
    if (options.content_size) |size| {
        if (dst + 8 > output.len) return Error.OutputTooSmall;
        std.mem.writeInt(u64, output[dst..][0..8], size, .little);
        dst += 8;
    }

    // Write header checksum
    const header_end = dst;
    const header_start: usize = 4;
    var hc: u8 = 0;
    for (output[header_start..header_end]) |b| {
        hc = hc ^ b;
    }
    output[dst] = hc;
    dst += 1;

    // Compress data in blocks
    const block_max = options.block_size.bytes();
    var src: usize = 0;
    var content_hasher = std.hash.XxHash32.init(0);

    while (src < input.len) {
        const chunk_size = @min(block_max, input.len - src);
        const chunk = input[src..][0..chunk_size];

        // Reserve space for block size
        if (dst + 4 > output.len) return Error.OutputTooSmall;
        const block_size_pos = dst;
        dst += 4;

        // Try to compress the block
        const max_compressed = lz4_block.maxCompressedSize(chunk_size);
        if (dst + max_compressed > output.len) return Error.OutputTooSmall;

        const compressed_block = lz4_block.compressInto(chunk, output[dst..]) catch {
            // Compression failed, store uncompressed
            if (dst + chunk_size > output.len) return Error.OutputTooSmall;
            @memcpy(output[dst..][0..chunk_size], chunk);
            std.mem.writeInt(u32, output[block_size_pos..][0..4], @intCast(chunk_size | 0x80000000), .little);
            dst += chunk_size;
            src += chunk_size;
            content_hasher.update(chunk);
            continue;
        };

        // Check if compression helped
        if (compressed_block.len >= chunk_size) {
            // Store uncompressed
            if (dst + chunk_size > output.len) return Error.OutputTooSmall;
            @memcpy(output[dst..][0..chunk_size], chunk);
            std.mem.writeInt(u32, output[block_size_pos..][0..4], @intCast(chunk_size | 0x80000000), .little);
            dst += chunk_size;
        } else {
            // Store compressed
            std.mem.writeInt(u32, output[block_size_pos..][0..4], @intCast(compressed_block.len), .little);
            dst += compressed_block.len;
        }

        content_hasher.update(chunk);
        src += chunk_size;
    }

    // Write end mark
    if (dst + 4 > output.len) return Error.OutputTooSmall;
    std.mem.writeInt(u32, output[dst..][0..4], 0, .little);
    dst += 4;

    // Write content checksum if enabled
    if (options.content_checksum) {
        if (dst + 4 > output.len) return Error.OutputTooSmall;
        std.mem.writeInt(u32, output[dst..][0..4], content_hasher.final(), .little);
        dst += 4;
    }

    return output[0..dst];
}

/// Decompress LZ4 frame format data.
/// Caller owns returned slice and must free with allocator.
pub fn decompress(input: []const u8, allocator: std.mem.Allocator, options: DecompressOptions) Error![]u8 {
    const max_output_size = options.max_output_size;

    if (input.len < MIN_FRAME_SIZE) return Error.InvalidData;

    // Verify magic
    const magic = std.mem.readInt(u32, input[0..4], .little);
    if (magic != MAGIC) return Error.InvalidData;

    const flg = input[4];
    const bd = input[5];
    const has_content_size = (flg & 0x08) != 0;

    // Parse block max size from BD byte (bits 4-6)
    const block_size_id: u3 = @truncate((bd >> 4) & 0x07);
    const max_block_size: usize = @as(usize, 1) << (@as(u5, block_size_id) * 2 + 8);

    var content_size: ?usize = null;
    if (has_content_size and input.len >= 14) {
        content_size = @intCast(std.mem.readInt(u64, input[6..14], .little));
        // Check limit early if we know the size
        if (max_output_size) |limit| {
            if (content_size.? > limit) return Error.OutputTooLarge;
        }
    }

    // Allocate output buffer
    var initial_size = content_size orelse input.len * 4;
    // Cap initial allocation at limit if set
    if (max_output_size) |limit| {
        initial_size = @min(initial_size, limit);
    }
    var output = allocator.alloc(u8, initial_size) catch return Error.OutOfMemory;
    errdefer allocator.free(output);

    // Heap-allocate temp buffer based on frame's max block size
    const temp_buf = allocator.alloc(u8, max_block_size) catch return Error.OutOfMemory;
    defer allocator.free(temp_buf);

    // Decompress into buffer, growing if needed
    var dst: usize = 0;
    var src: usize = 6;
    if (has_content_size) {
        src += 8;
    }
    src += 1; // Header checksum

    const has_content_checksum = (flg & 0x04) != 0;
    var content_hasher = std.hash.XxHash32.init(0);

    while (src + 4 <= input.len) {
        const block_size_raw = std.mem.readInt(u32, input[src..][0..4], .little);
        src += 4;

        if (block_size_raw == 0) break;

        const is_uncompressed = (block_size_raw & 0x80000000) != 0;
        const block_size: usize = @intCast(block_size_raw & 0x7FFFFFFF);

        if (src + block_size > input.len) {
            return Error.UnexpectedEof;
        }

        if (is_uncompressed) {
            // Check limit before growing
            if (max_output_size) |limit| {
                if (dst + block_size > limit) return Error.OutputTooLarge;
            }
            // Grow buffer if needed (overflow-safe)
            if (dst + block_size > output.len) {
                const doubled = @mulWithOverflow(output.len, 2);
                const doubled_size = if (doubled[1] != 0) std.math.maxInt(usize) else doubled[0];
                var new_size = @max(doubled_size, dst + block_size);
                if (max_output_size) |limit| {
                    new_size = @min(new_size, limit);
                }
                output = allocator.realloc(output, new_size) catch return Error.OutOfMemory;
            }
            @memcpy(output[dst..][0..block_size], input[src..][0..block_size]);
            content_hasher.update(output[dst..][0..block_size]);
            dst += block_size;
        } else {
            const decompressed_block = lz4_block.decompressInto(
                input[src..][0..block_size],
                temp_buf,
            ) catch return Error.InvalidData;

            // Check limit before growing
            if (max_output_size) |limit| {
                if (dst + decompressed_block.len > limit) return Error.OutputTooLarge;
            }
            // Grow buffer if needed (overflow-safe)
            if (dst + decompressed_block.len > output.len) {
                const doubled = @mulWithOverflow(output.len, 2);
                const doubled_size = if (doubled[1] != 0) std.math.maxInt(usize) else doubled[0];
                var new_size = @max(doubled_size, dst + decompressed_block.len);
                if (max_output_size) |limit| {
                    new_size = @min(new_size, limit);
                }
                output = allocator.realloc(output, new_size) catch return Error.OutOfMemory;
            }
            @memcpy(output[dst..][0..decompressed_block.len], decompressed_block);
            content_hasher.update(decompressed_block);
            dst += decompressed_block.len;
        }

        src += block_size;
    }

    // Verify content checksum
    if (has_content_checksum) {
        if (src + 4 > input.len) {
            return Error.UnexpectedEof;
        }
        const expected_hash = std.mem.readInt(u32, input[src..][0..4], .little);
        if (content_hasher.final() != expected_hash) {
            return Error.ChecksumMismatch;
        }
    }

    // Shrink to actual size
    return shrinkAllocation(allocator, output, dst);
}

/// Decompress into provided buffer.
/// Returns slice of written data.
pub fn decompressInto(input: []const u8, output: []u8) Error![]u8 {
    if (input.len < MIN_FRAME_SIZE) return Error.InvalidData;

    const magic = std.mem.readInt(u32, input[0..4], .little);
    if (magic != MAGIC) return Error.InvalidData;

    const flg = input[4];
    const has_content_size = (flg & 0x08) != 0;
    const has_content_checksum = (flg & 0x04) != 0;

    var src: usize = 6;
    if (has_content_size) {
        src += 8;
    }
    src += 1;

    var dst: usize = 0;
    var content_hasher = std.hash.XxHash32.init(0);

    while (src + 4 <= input.len) {
        const block_size_raw = std.mem.readInt(u32, input[src..][0..4], .little);
        src += 4;

        if (block_size_raw == 0) break;

        const is_uncompressed = (block_size_raw & 0x80000000) != 0;
        const block_size: usize = @intCast(block_size_raw & 0x7FFFFFFF);

        if (src + block_size > input.len) return Error.UnexpectedEof;

        if (is_uncompressed) {
            if (dst + block_size > output.len) return Error.OutputTooSmall;
            @memcpy(output[dst..][0..block_size], input[src..][0..block_size]);
            content_hasher.update(output[dst..][0..block_size]);
            dst += block_size;
        } else {
            const decompressed_block = lz4_block.decompressInto(
                input[src..][0..block_size],
                output[dst..],
            ) catch return Error.InvalidData;
            content_hasher.update(decompressed_block);
            dst += decompressed_block.len;
        }

        src += block_size;
    }

    if (has_content_checksum) {
        if (src + 4 > input.len) return Error.UnexpectedEof;
        const expected_hash = std.mem.readInt(u32, input[src..][0..4], .little);
        if (content_hasher.final() != expected_hash) return Error.ChecksumMismatch;
    }

    return output[0..dst];
}

/// Shrink allocation to actual size, handling resize failure gracefully.
fn shrinkAllocation(allocator: std.mem.Allocator, buffer: []u8, actual_size: usize) Error![]u8 {
    if (allocator.resize(buffer, actual_size)) {
        return buffer[0..actual_size];
    }
    // Resize failed, allocate new buffer and copy
    const result = allocator.alloc(u8, actual_size) catch return Error.OutOfMemory;
    @memcpy(result, buffer[0..actual_size]);
    allocator.free(buffer);
    return result;
}

// ============================================================================
// Streaming Decompressor
// ============================================================================

/// Streaming decompressor for LZ4 frame format data.
pub fn Decompressor(comptime ReaderType: type) type {
    return struct {
        const Self = @This();
        const BUFFER_SIZE = 64 * 1024;

        source: ReaderType,
        allocator: std.mem.Allocator,
        input_buffer: []u8,
        output_buffer: []u8, // Buffer for decompressed block data
        output_pos: usize, // Current position in output_buffer
        output_len: usize, // Valid data length in output_buffer
        block_size: usize,
        has_content_checksum: bool,
        finished: bool,
        header_read: bool,

        pub const InitError = error{OutOfMemory};
        pub const ReadError = Error || ReaderType.Error;
        pub const Reader = std.io.GenericReader(*Self, ReadError, read);

        pub fn init(allocator: std.mem.Allocator, source: ReaderType) InitError!Self {
            const input_buffer = allocator.alloc(u8, BUFFER_SIZE) catch return error.OutOfMemory;
            errdefer allocator.free(input_buffer);

            // Output buffer for decompressed data (blocks can decompress to max block size)
            const output_buffer = allocator.alloc(u8, BUFFER_SIZE) catch return error.OutOfMemory;

            return Self{
                .source = source,
                .allocator = allocator,
                .input_buffer = input_buffer,
                .output_buffer = output_buffer,
                .output_pos = 0,
                .output_len = 0,
                .block_size = 64 * 1024,
                .has_content_checksum = false,
                .finished = false,
                .header_read = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.input_buffer);
            self.allocator.free(self.output_buffer);
        }

        fn readHeader(self: *Self) ReadError!void {
            var header: [15]u8 = undefined;

            // Read magic
            var total: usize = 0;
            while (total < 4) {
                const n = self.source.read(header[total..4]) catch |e| return e;
                if (n == 0) return Error.UnexpectedEof;
                total += n;
            }

            const magic = std.mem.readInt(u32, header[0..4], .little);
            if (magic != MAGIC) return Error.InvalidData;

            // Read FLG and BD
            total = 0;
            while (total < 2) {
                const n = self.source.read(header[4 + total .. 6]) catch |e| return e;
                if (n == 0) return Error.UnexpectedEof;
                total += n;
            }

            const flg = header[4];
            const bd = header[5];

            self.has_content_checksum = (flg & 0x04) != 0;
            const has_content_size = (flg & 0x08) != 0;

            // Block size from BD
            const block_size_id: u3 = @truncate((bd >> 4) & 0x07);
            self.block_size = @as(usize, 1) << (@as(u5, block_size_id) * 2 + 8);

            // Skip content size if present
            if (has_content_size) {
                total = 0;
                while (total < 8) {
                    const n = self.source.read(header[6 + total .. 14]) catch |e| return e;
                    if (n == 0) return Error.UnexpectedEof;
                    total += n;
                }
            }

            // Read header checksum
            var hc: [1]u8 = undefined;
            total = 0;
            while (total < 1) {
                const n = self.source.read(&hc) catch |e| return e;
                if (n == 0) return Error.UnexpectedEof;
                total += n;
            }

            self.header_read = true;
        }

        /// Read and decompress the next block into output_buffer.
        fn readNextBlock(self: *Self) ReadError!bool {
            // Read block header
            var block_header: [4]u8 = undefined;
            var total: usize = 0;
            while (total < 4) {
                const n = self.source.read(block_header[total..4]) catch |e| return e;
                if (n == 0) {
                    if (total == 0) {
                        self.finished = true;
                        return false;
                    }
                    return Error.UnexpectedEof;
                }
                total += n;
            }

            const block_size_raw = std.mem.readInt(u32, &block_header, .little);

            // End mark
            if (block_size_raw == 0) {
                self.finished = true;
                return false;
            }

            const is_uncompressed = (block_size_raw & 0x80000000) != 0;
            const block_size: usize = @intCast(block_size_raw & 0x7FFFFFFF);

            if (block_size > self.input_buffer.len) {
                return Error.InvalidData;
            }

            // Read compressed block data
            total = 0;
            while (total < block_size) {
                const n = self.source.read(self.input_buffer[total..block_size]) catch |e| return e;
                if (n == 0) return Error.UnexpectedEof;
                total += n;
            }

            // Decompress or copy to output buffer
            if (is_uncompressed) {
                @memcpy(self.output_buffer[0..block_size], self.input_buffer[0..block_size]);
                self.output_len = block_size;
            } else {
                const decompressed_block = lz4_block.decompressInto(
                    self.input_buffer[0..block_size],
                    self.output_buffer,
                ) catch return Error.InvalidData;
                self.output_len = decompressed_block.len;
            }

            self.output_pos = 0;
            return true;
        }

        pub fn read(self: *Self, buffer: []u8) ReadError!usize {
            if (self.finished) return 0;
            if (buffer.len == 0) return 0;

            if (!self.header_read) {
                try self.readHeader();
            }

            // If we have buffered data from a previous block, return it first
            if (self.output_pos < self.output_len) {
                const available = self.output_len - self.output_pos;
                const copy_len = @min(available, buffer.len);
                @memcpy(buffer[0..copy_len], self.output_buffer[self.output_pos..][0..copy_len]);
                self.output_pos += copy_len;
                return copy_len;
            }

            // Need to read next block
            if (!try self.readNextBlock()) {
                return 0; // No more blocks
            }

            // Return data from the freshly decompressed block
            const copy_len = @min(self.output_len, buffer.len);
            @memcpy(buffer[0..copy_len], self.output_buffer[0..copy_len]);
            self.output_pos = copy_len;
            return copy_len;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}

// ============================================================================
// Streaming Compressor
// ============================================================================

/// Streaming compressor for LZ4 frame format data.
pub fn Compressor(comptime WriterType: type) type {
    return struct {
        const Self = @This();
        const BLOCK_SIZE = 64 * 1024;

        dest: WriterType,
        allocator: std.mem.Allocator,
        input_buffer: []u8,
        input_len: usize,
        output_buffer: []u8,
        header_written: bool,
        finished: bool,

        pub const Options = struct {
            level: Level = .default,
        };

        pub const InitError = error{OutOfMemory};
        pub const WriteError = Error || WriterType.Error;
        pub const Writer = std.io.GenericWriter(*Self, WriteError, write);

        pub fn init(allocator: std.mem.Allocator, dest: WriterType, options: Options) InitError!Self {
            _ = options;

            const input_buffer = allocator.alloc(u8, BLOCK_SIZE) catch return error.OutOfMemory;
            errdefer allocator.free(input_buffer);

            const output_buffer = allocator.alloc(u8, lz4_block.maxCompressedSize(BLOCK_SIZE)) catch return error.OutOfMemory;

            return Self{
                .dest = dest,
                .allocator = allocator,
                .input_buffer = input_buffer,
                .input_len = 0,
                .output_buffer = output_buffer,
                .header_written = false,
                .finished = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.input_buffer);
            self.allocator.free(self.output_buffer);
        }

        fn writeHeader(self: *Self) WriteError!void {
            var header: [7]u8 = undefined;

            // Magic
            std.mem.writeInt(u32, header[0..4], MAGIC, .little);

            // FLG: version=01, block_independence=1
            header[4] = 0x60;

            // BD: block_size=64KB (4)
            header[5] = 0x40;

            // Header checksum (simple XOR)
            header[6] = header[4] ^ header[5];

            self.dest.writeAll(&header) catch |e| return e;
            self.header_written = true;
        }

        fn flushBlock(self: *Self) WriteError!void {
            if (self.input_len == 0) return;

            const compressed = lz4_block.compressInto(
                self.input_buffer[0..self.input_len],
                self.output_buffer,
            ) catch {
                // Store uncompressed
                var block_header: [4]u8 = undefined;
                std.mem.writeInt(u32, &block_header, @as(u32, @intCast(self.input_len)) | 0x80000000, .little);
                self.dest.writeAll(&block_header) catch |e| return e;
                self.dest.writeAll(self.input_buffer[0..self.input_len]) catch |e| return e;
                self.input_len = 0;
                return;
            };

            // Check if compression helped
            if (compressed.len >= self.input_len) {
                // Store uncompressed
                var block_header: [4]u8 = undefined;
                std.mem.writeInt(u32, &block_header, @as(u32, @intCast(self.input_len)) | 0x80000000, .little);
                self.dest.writeAll(&block_header) catch |e| return e;
                self.dest.writeAll(self.input_buffer[0..self.input_len]) catch |e| return e;
            } else {
                // Store compressed
                var block_header: [4]u8 = undefined;
                std.mem.writeInt(u32, &block_header, @intCast(compressed.len), .little);
                self.dest.writeAll(&block_header) catch |e| return e;
                self.dest.writeAll(compressed) catch |e| return e;
            }

            self.input_len = 0;
        }

        pub fn write(self: *Self, data: []const u8) WriteError!usize {
            if (self.finished) return 0;
            if (data.len == 0) return 0;

            if (!self.header_written) {
                try self.writeHeader();
            }

            var remaining = data;
            while (remaining.len > 0) {
                const space = BLOCK_SIZE - self.input_len;
                const copy_len = @min(space, remaining.len);

                @memcpy(self.input_buffer[self.input_len..][0..copy_len], remaining[0..copy_len]);
                self.input_len += copy_len;
                remaining = remaining[copy_len..];

                if (self.input_len == BLOCK_SIZE) {
                    try self.flushBlock();
                }
            }

            return data.len;
        }

        pub fn flush(self: *Self) WriteError!void {
            if (self.finished) return;
            if (!self.header_written) {
                try self.writeHeader();
            }
            try self.flushBlock();
        }

        pub fn finish(self: *Self) WriteError!void {
            if (self.finished) return;

            if (!self.header_written) {
                try self.writeHeader();
            }

            try self.flushBlock();

            // Write end mark
            var end_mark: [4]u8 = undefined;
            std.mem.writeInt(u32, &end_mark, 0, .little);
            self.dest.writeAll(&end_mark) catch |e| return e;

            self.finished = true;
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
    const input = "Hello, LZ4 Frame Format! This is a test of the frame compression.";

    const compressed = try compress(input, allocator, .{});
    defer allocator.free(compressed);

    try std.testing.expectEqual(@as(u32, MAGIC), std.mem.readInt(u32, compressed[0..4], .little));

    const decompressed = try decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "compress with content size" {
    const allocator = std.testing.allocator;
    const input = "Content with known size for frame format test.";

    const compressed = try compress(input, allocator, .{
        .content_size = input.len,
        .content_checksum = true,
    });
    defer allocator.free(compressed);

    const flg = compressed[4];
    try std.testing.expect((flg & 0x08) != 0);

    const decompressed = try decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "compress large data" {
    const allocator = std.testing.allocator;

    var input: [100 * 1024]u8 = undefined;
    for (&input, 0..) |*b, i| {
        b.* = @intCast(i % 256);
    }

    const compressed = try compress(&input, allocator, .{});
    defer allocator.free(compressed);

    const decompressed = try decompress(compressed, allocator, .{});
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, &input, decompressed);
}

test "decompress into buffer" {
    const allocator = std.testing.allocator;
    const input = "Test decompression into pre-allocated buffer.";

    const compressed = try compress(input, allocator, .{});
    defer allocator.free(compressed);

    var output: [1024]u8 = undefined;
    const decompressed = try decompressInto(compressed, &output);

    try std.testing.expectEqualStrings(input, decompressed);
}

test "decompress invalid magic" {
    const allocator = std.testing.allocator;
    // Invalid magic number
    const invalid_data = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x40, 0x40, 0x00 };
    const result = decompress(&invalid_data, allocator, .{});
    try std.testing.expectError(Error.InvalidData, result);
}

test "decompress truncated header" {
    const allocator = std.testing.allocator;
    // Valid magic but truncated
    const truncated = [_]u8{ 0x04, 0x22, 0x4D, 0x18, 0x40 };
    const result = decompress(&truncated, allocator, .{});
    try std.testing.expectError(Error.InvalidData, result);
}

test "decompress corrupted checksum" {
    const allocator = std.testing.allocator;
    const input = "Test checksum validation!";

    const compressed = try compress(input, allocator, .{ .content_checksum = true });
    defer allocator.free(compressed);

    // Corrupt the last 4 bytes (content checksum)
    var corrupted = try allocator.alloc(u8, compressed.len);
    defer allocator.free(corrupted);
    @memcpy(corrupted, compressed);
    corrupted[corrupted.len - 1] ^= 0xFF;

    const result = decompress(corrupted, allocator, .{});
    try std.testing.expectError(Error.ChecksumMismatch, result);
}

test "decompress with size limit" {
    const allocator = std.testing.allocator;
    const input = "This is test data that will be limited during decompression.";

    const compressed = try compress(input, allocator, .{});
    defer allocator.free(compressed);

    // Try to decompress with a limit smaller than actual size
    const result = decompress(compressed, allocator, .{ .max_output_size = 10 });
    try std.testing.expectError(Error.OutputTooLarge, result);
}

test "streaming round-trip" {
    const allocator = std.testing.allocator;
    const input = "Hello, streaming lz4 compression! " ** 100;

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

test "streaming with small buffer reads" {
    // This test verifies the fix for data loss when reading with small buffers
    const allocator = std.testing.allocator;
    const input = "Test data for small buffer streaming. " ** 100; // ~3800 bytes

    // Compress
    var compressed_buf: [8192]u8 = undefined;
    var compressed_stream = std.io.fixedBufferStream(&compressed_buf);

    var comp = try Compressor(@TypeOf(compressed_stream).Writer).init(allocator, compressed_stream.writer(), .{});
    defer comp.deinit();
    try comp.writer().writeAll(input);
    try comp.finish();

    const compressed = compressed_stream.getWritten();

    // Decompress with very small buffer (16 bytes at a time)
    var fbs = std.io.fixedBufferStream(compressed);
    var decomp = try Decompressor(@TypeOf(fbs).Reader).init(allocator, fbs.reader());
    defer decomp.deinit();

    var result: std.ArrayListUnmanaged(u8) = .{};
    defer result.deinit(allocator);

    var small_buf: [16]u8 = undefined;
    while (true) {
        const n = try decomp.reader().read(&small_buf);
        if (n == 0) break;
        try result.appendSlice(allocator, small_buf[0..n]);
    }

    try std.testing.expectEqualStrings(input, result.items);
}

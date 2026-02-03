---
title: Archive Formats
description: Read and write ZIP and TAR archives.
---

compressionz includes support for ZIP and TAR archive formats, allowing you to bundle multiple files with their names and metadata.

## Supported Formats

| Format | Compression | Use Case |
|--------|-------------|----------|
| **ZIP** | Deflate (built-in) | Cross-platform, Windows-friendly |
| **TAR** | None (external) | Unix, often combined with gzip/zstd |

## ZIP Reading

### Iterator-Based Reading

```zig
const cz = @import("compressionz");
const std = @import("std");

pub fn readZip(allocator: std.mem.Allocator, zip_path: []const u8) !void {
    const file = try std.fs.cwd().openFile(zip_path, .{});
    defer file.close();

    var reader = try cz.archive.zip.Reader.init(allocator, file);
    defer reader.deinit();

    while (try reader.next()) |entry| {
        std.debug.print("{s}: {d} bytes\n", .{ entry.name, entry.uncompressed_size });

        if (!entry.is_directory) {
            const data = try entry.readAll(allocator);
            defer allocator.free(data);
            // Process file data...
        }
    }
}
```

### Entry Properties

```zig
while (try reader.next()) |entry| {
    std.debug.print("Name: {s}\n", .{entry.name});
    std.debug.print("Compressed size: {d}\n", .{entry.compressed_size});
    std.debug.print("Uncompressed size: {d}\n", .{entry.uncompressed_size});
    std.debug.print("Is directory: {}\n", .{entry.is_directory});
}
```

## ZIP Writing

```zig
const cz = @import("compressionz");
const std = @import("std");

pub fn createZipFile(allocator: std.mem.Allocator, output_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    var writer = try cz.archive.zip.Writer.init(allocator, file);
    defer writer.deinit();

    // Add files
    try writer.addFile("readme.txt", "This is a README file.");
    try writer.addFile("src/main.zig", "const std = @import(\"std\");");
    try writer.addFile("data/config.json", "{\"version\": 1}");

    // Add directory (optional - directories are created implicitly)
    try writer.addDirectory("empty_dir/");

    // Finalize (writes central directory)
    try writer.finish();
}
```

## TAR Reading

### Iterator-Based Reading

```zig
const cz = @import("compressionz");
const std = @import("std");

pub fn readTar(allocator: std.mem.Allocator, tar_path: []const u8) !void {
    const file = try std.fs.cwd().openFile(tar_path, .{});
    defer file.close();

    var reader = cz.archive.tar.Reader(@TypeOf(file.reader())).init(allocator, file.reader());
    defer reader.deinit();

    while (try reader.next()) |entry| {
        std.debug.print("File: {s}\n", .{entry.name});
        std.debug.print("Size: {d}\n", .{entry.size});
        std.debug.print("Type: {}\n", .{entry.file_type});

        if (!entry.file_type.isDirectory()) {
            const data = try entry.readAll(allocator);
            defer allocator.free(data);
            // Process file data...
        }
    }
}
```

**Important:** TAR entry pointers are invalidated when `next()` is called again. Copy any data you need before advancing.

## TAR Writing

```zig
const cz = @import("compressionz");
const std = @import("std");

pub fn createTarFile(output_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    var writer = cz.archive.tar.Writer(@TypeOf(file.writer())).init(file.writer());

    // Add files
    try writer.addFile("file1.txt", "Content of file 1");
    try writer.addFile("file2.txt", "Content of file 2");

    // Add directory
    try writer.addDirectory("subdir/");

    // Finalize (writes end-of-archive markers)
    try writer.finish();
}
```

## Compressed Archives

### TAR + Gzip (.tar.gz / .tgz)

```zig
const cz = @import("compressionz");
const std = @import("std");

// Create .tar.gz
pub fn createTarGz(allocator: std.mem.Allocator, output_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    // Gzip compressor wrapping file writer
    var gzip = try cz.gzip.Compressor(@TypeOf(file.writer())).init(allocator, file.writer(), .{});
    defer gzip.deinit();

    // TAR writer wrapping gzip
    var tar = cz.archive.tar.Writer(@TypeOf(gzip.writer())).init(gzip.writer());

    try tar.addFile("hello.txt", "Hello, World!");
    try tar.addFile("data.json", "{\"key\": \"value\"}");
    try tar.finish();
    try gzip.finish();
}

// Extract .tar.gz
pub fn extractTarGz(allocator: std.mem.Allocator, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // Gzip decompressor wrapping file reader
    var gzip = try cz.gzip.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
    defer gzip.deinit();

    // TAR reader wrapping gzip
    var tar = cz.archive.tar.Reader(@TypeOf(gzip.reader())).init(allocator, gzip.reader());
    defer tar.deinit();

    while (try tar.next()) |entry| {
        std.debug.print("{s}: {d} bytes\n", .{ entry.name, entry.size });
    }
}
```

### TAR + Zstd (.tar.zst)

```zig
// Create .tar.zst
pub fn createTarZst(allocator: std.mem.Allocator, output_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    var zstd = try cz.zstd.Compressor(@TypeOf(file.writer())).init(allocator, file.writer(), .{
        .level = .best,
    });
    defer zstd.deinit();

    var tar = cz.archive.tar.Writer(@TypeOf(zstd.writer())).init(zstd.writer());

    try tar.addFile("file.txt", "Content");
    try tar.finish();
    try zstd.finish();
}

// Extract .tar.zst
pub fn extractTarZst(allocator: std.mem.Allocator, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var zstd = try cz.zstd.Decompressor(@TypeOf(file.reader())).init(allocator, file.reader());
    defer zstd.deinit();

    var tar = cz.archive.tar.Reader(@TypeOf(zstd.reader())).init(allocator, zstd.reader());
    defer tar.deinit();

    while (try tar.next()) |entry| {
        std.debug.print("{s}\n", .{entry.name});
    }
}
```

## Use Cases

### Backup System

```zig
const cz = @import("compressionz");
const std = @import("std");

pub fn createBackup(allocator: std.mem.Allocator, source_dir: []const u8, output_path: []const u8) !void {
    const output = try std.fs.cwd().createFile(output_path, .{});
    defer output.close();

    // Compress with zstd
    var zstd = try cz.zstd.Compressor(@TypeOf(output.writer())).init(allocator, output.writer(), .{
        .level = .best,
    });
    defer zstd.deinit();

    // Write as TAR
    var tar = cz.archive.tar.Writer(@TypeOf(zstd.writer())).init(zstd.writer());

    // Walk directory and add files
    var dir = try std.fs.cwd().openDir(source_dir, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const data = try dir.readFileAlloc(allocator, entry.path, 100 * 1024 * 1024);
            defer allocator.free(data);
            try tar.addFile(entry.path, data);
        }
    }

    try tar.finish();
    try zstd.finish();
}
```

### Download Handler

```zig
pub fn handleDownloadAsZip(request: *Request, response: *Response, allocator: std.mem.Allocator) !void {
    const files = try getRequestedFiles(request);

    // Create ZIP in memory
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var writer = try cz.archive.zip.Writer.init(allocator, output.writer());
    defer writer.deinit();

    for (files) |file| {
        try writer.addFile(file.name, file.data);
    }
    try writer.finish();

    response.headers.set("Content-Type", "application/zip");
    response.headers.set("Content-Disposition", "attachment; filename=\"files.zip\"");
    try response.send(output.items);
}
```

## Error Handling

```zig
const result = cz.archive.zip.Reader.init(allocator, file) catch |err| switch (err) {
    error.InvalidData => {
        std.debug.print("Not a valid ZIP file\n", .{});
        return error.InvalidArchive;
    },
    error.OutOfMemory => {
        std.debug.print("Archive too large\n", .{});
        return error.ResourceExhausted;
    },
    else => return err,
};
```

## Limitations

### ZIP
- No encryption support
- No ZIP64 (large file) support
- Deflate compression only

### TAR
- No extended attributes
- No ACLs
- POSIX ustar format only

For advanced archive features, consider dedicated libraries.

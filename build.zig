const std = @import("std");

const Build = std.Build;
const Step = Build.Step;
const Compile = Step.Compile;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build vendored C libraries
    const brotli_lib = buildBrotli(b, target, optimize);
    const zlib_lib = buildZlib(b, target, optimize);
    const zstd_lib = buildZstd(b, target, optimize);

    // Include paths for @cImport
    const brotli_include = b.path("vendor/brotli/include");
    const zlib_include = b.path("vendor/zlib");
    const zstd_include = b.path("vendor/zstd/lib");

    // Main library module (for consumers)
    const compressionz_mod = b.addModule("compressionz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    compressionz_mod.linkLibrary(brotli_lib);
    compressionz_mod.linkLibrary(zlib_lib);
    compressionz_mod.linkLibrary(zstd_lib);
    compressionz_mod.addIncludePath(brotli_include);
    compressionz_mod.addIncludePath(zlib_include);
    compressionz_mod.addIncludePath(zstd_include);

    // Create root module for library
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addIncludePath(brotli_include);
    lib_mod.addIncludePath(zlib_include);
    lib_mod.addIncludePath(zstd_include);

    // Static library
    const lib = b.addLibrary(.{
        .name = "compressionz",
        .root_module = lib_mod,
        .linkage = .static,
    });
    lib.linkLibrary(brotli_lib);
    lib.linkLibrary(zlib_lib);
    lib.linkLibrary(zstd_lib);
    b.installArtifact(lib);

    // Unit Tests (in source files)
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addIncludePath(brotli_include);
    test_mod.addIncludePath(zlib_include);
    test_mod.addIncludePath(zstd_include);
    const tests = b.addTest(.{
        .root_module = test_mod,
    });
    tests.linkLibrary(brotli_lib);
    tests.linkLibrary(zlib_lib);
    tests.linkLibrary(zstd_lib);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests (in source files)");
    test_step.dependOn(&run_tests.step);

    // Helper to create test modules for external test files
    const TestCategory = struct {
        name: []const u8,
        description: []const u8,
        files: []const []const u8,
    };

    const test_categories = [_]TestCategory{
        .{
            .name = "test-integration",
            .description = "Run integration tests (round-trip, archives, dictionary)",
            .files = &.{ "tests/integration/round_trip.zig", "tests/integration/archives.zig", "tests/integration/dictionary.zig" },
        },
        .{
            .name = "test-robustness",
            .description = "Run robustness tests (malformed input, limits, checksums)",
            .files = &.{ "tests/robustness/malformed.zig", "tests/robustness/limits.zig", "tests/robustness/checksums.zig" },
        },
        .{
            .name = "test-stress",
            .description = "Run stress tests (large files, boundaries, many entries, streaming, concurrent)",
            .files = &.{ "tests/stress/large_files.zig", "tests/stress/boundary.zig", "tests/stress/many_entries.zig", "tests/stress/streaming.zig", "tests/stress/concurrent.zig" },
        },
        .{
            .name = "test-interop",
            .description = "Run interoperability tests (CLI tool compatibility)",
            .files = &.{"tests/interop/cli_compat.zig"},
        },
        .{
            .name = "test-fuzz",
            .description = "Run fuzz tests (random input, memory)",
            .files = &.{ "tests/fuzz/fuzz.zig", "tests/fuzz/memory.zig" },
        },
    };

    // Test-all step that runs everything
    const test_all_step = b.step("test-all", "Run all tests (unit + integration + robustness + stress + fuzz)");
    test_all_step.dependOn(&run_tests.step);

    for (test_categories) |category| {
        const category_step = b.step(category.name, category.description);

        for (category.files) |file| {
            const ext_test_mod = b.createModule(.{
                .root_source_file = b.path(file),
                .target = target,
                .optimize = optimize,
            });
            ext_test_mod.addIncludePath(brotli_include);
            ext_test_mod.addIncludePath(zlib_include);
            ext_test_mod.addIncludePath(zstd_include);
            ext_test_mod.addImport("compressionz", compressionz_mod);

            const ext_tests = b.addTest(.{
                .root_module = ext_test_mod,
            });
            ext_tests.linkLibrary(brotli_lib);
            ext_tests.linkLibrary(zlib_lib);
            ext_tests.linkLibrary(zstd_lib);

            const run_ext_tests = b.addRunArtifact(ext_tests);
            category_step.dependOn(&run_ext_tests.step);
            test_all_step.dependOn(&run_ext_tests.step);
        }
    }

    // Check step for IDE
    const check_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    check_mod.addIncludePath(brotli_include);
    check_mod.addIncludePath(zlib_include);
    check_mod.addIncludePath(zstd_include);
    const check = b.addLibrary(.{
        .name = "compressionz_check",
        .root_module = check_mod,
        .linkage = .static,
    });
    check.linkLibrary(brotli_lib);
    check.linkLibrary(zlib_lib);
    check.linkLibrary(zstd_lib);

    const check_step = b.step("check", "Check for semantic errors");
    check_step.dependOn(&check.step);

    // Benchmark executable
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("benchmarks/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_mod.addIncludePath(brotli_include);
    bench_mod.addIncludePath(zlib_include);
    bench_mod.addIncludePath(zstd_include);
    bench_mod.addImport("compressionz", compressionz_mod);

    const bench_exe = b.addExecutable(.{
        .name = "bench_compression",
        .root_module = bench_mod,
    });
    bench_exe.linkLibrary(brotli_lib);
    bench_exe.linkLibrary(zlib_lib);
    bench_exe.linkLibrary(zstd_lib);
    bench_exe.linkLibC(); // For getrusage
    b.installArtifact(bench_exe);

    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run compression benchmarks");
    bench_step.dependOn(&run_bench.step);
}

fn buildZlib(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Compile {
    const zlib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "z",
        .root_module = zlib_mod,
        .linkage = .static,
    });

    lib.addIncludePath(b.path("vendor/zlib"));

    const cflags = &[_][]const u8{
        "-DHAVE_UNISTD_H",
        "-DHAVE_STDARG_H",
        "-fno-sanitize=undefined",
    };

    const sources = &[_][]const u8{
        "vendor/zlib/adler32.c",
        "vendor/zlib/compress.c",
        "vendor/zlib/crc32.c",
        "vendor/zlib/deflate.c",
        "vendor/zlib/gzclose.c",
        "vendor/zlib/gzlib.c",
        "vendor/zlib/gzread.c",
        "vendor/zlib/gzwrite.c",
        "vendor/zlib/infback.c",
        "vendor/zlib/inffast.c",
        "vendor/zlib/inflate.c",
        "vendor/zlib/inftrees.c",
        "vendor/zlib/trees.c",
        "vendor/zlib/uncompr.c",
        "vendor/zlib/zutil.c",
    };

    lib.addCSourceFiles(.{
        .files = sources,
        .flags = cflags,
    });

    lib.linkLibC();
    return lib;
}

fn buildZstd(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Compile {
    const zstd_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zstd",
        .root_module = zstd_mod,
        .linkage = .static,
    });

    // Include paths
    lib.addIncludePath(b.path("vendor/zstd/lib"));
    lib.addIncludePath(b.path("vendor/zstd/lib/common"));

    const cflags = &[_][]const u8{
        "-DZSTD_MULTITHREAD=0", // Disable threading for simplicity
        "-DZSTD_LEGACY_SUPPORT=0", // Disable legacy format support
        "-DZSTD_DISABLE_ASM", // Disable ASM for cross-platform compatibility
        "-fno-sanitize=undefined",
    };

    // Common sources
    const common_sources = &[_][]const u8{
        "vendor/zstd/lib/common/debug.c",
        "vendor/zstd/lib/common/entropy_common.c",
        "vendor/zstd/lib/common/error_private.c",
        "vendor/zstd/lib/common/fse_decompress.c",
        "vendor/zstd/lib/common/pool.c",
        "vendor/zstd/lib/common/threading.c",
        "vendor/zstd/lib/common/xxhash.c",
        "vendor/zstd/lib/common/zstd_common.c",
    };

    // Compress sources
    const compress_sources = &[_][]const u8{
        "vendor/zstd/lib/compress/fse_compress.c",
        "vendor/zstd/lib/compress/hist.c",
        "vendor/zstd/lib/compress/huf_compress.c",
        "vendor/zstd/lib/compress/zstd_compress.c",
        "vendor/zstd/lib/compress/zstd_compress_literals.c",
        "vendor/zstd/lib/compress/zstd_compress_sequences.c",
        "vendor/zstd/lib/compress/zstd_compress_superblock.c",
        "vendor/zstd/lib/compress/zstd_double_fast.c",
        "vendor/zstd/lib/compress/zstd_fast.c",
        "vendor/zstd/lib/compress/zstd_lazy.c",
        "vendor/zstd/lib/compress/zstd_ldm.c",
        "vendor/zstd/lib/compress/zstd_opt.c",
        "vendor/zstd/lib/compress/zstdmt_compress.c",
        "vendor/zstd/lib/compress/zstd_preSplit.c",
    };

    // Decompress sources
    const decompress_sources = &[_][]const u8{
        "vendor/zstd/lib/decompress/huf_decompress.c",
        "vendor/zstd/lib/decompress/zstd_ddict.c",
        "vendor/zstd/lib/decompress/zstd_decompress.c",
        "vendor/zstd/lib/decompress/zstd_decompress_block.c",
    };

    lib.addCSourceFiles(.{
        .files = common_sources,
        .flags = cflags,
    });
    lib.addCSourceFiles(.{
        .files = compress_sources,
        .flags = cflags,
    });
    lib.addCSourceFiles(.{
        .files = decompress_sources,
        .flags = cflags,
    });

    lib.linkLibC();
    return lib;
}

fn buildBrotli(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *Compile {
    const brotli_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "brotli",
        .root_module = brotli_mod,
        .linkage = .static,
    });

    lib.addIncludePath(b.path("vendor/brotli/include"));

    const cflags = &[_][]const u8{
        "-DBROTLI_BUILD_PORTABLE",
        "-fno-sanitize=undefined",
    };

    const common_sources = &[_][]const u8{
        "vendor/brotli/common/constants.c",
        "vendor/brotli/common/context.c",
        "vendor/brotli/common/dictionary.c",
        "vendor/brotli/common/platform.c",
        "vendor/brotli/common/shared_dictionary.c",
        "vendor/brotli/common/transform.c",
    };

    const dec_sources = &[_][]const u8{
        "vendor/brotli/dec/bit_reader.c",
        "vendor/brotli/dec/decode.c",
        "vendor/brotli/dec/huffman.c",
        "vendor/brotli/dec/prefix.c",
        "vendor/brotli/dec/state.c",
        "vendor/brotli/dec/static_init.c",
    };

    const enc_sources = &[_][]const u8{
        "vendor/brotli/enc/backward_references.c",
        "vendor/brotli/enc/backward_references_hq.c",
        "vendor/brotli/enc/bit_cost.c",
        "vendor/brotli/enc/block_splitter.c",
        "vendor/brotli/enc/brotli_bit_stream.c",
        "vendor/brotli/enc/cluster.c",
        "vendor/brotli/enc/command.c",
        "vendor/brotli/enc/compound_dictionary.c",
        "vendor/brotli/enc/compress_fragment.c",
        "vendor/brotli/enc/compress_fragment_two_pass.c",
        "vendor/brotli/enc/dictionary_hash.c",
        "vendor/brotli/enc/encode.c",
        "vendor/brotli/enc/encoder_dict.c",
        "vendor/brotli/enc/entropy_encode.c",
        "vendor/brotli/enc/fast_log.c",
        "vendor/brotli/enc/histogram.c",
        "vendor/brotli/enc/literal_cost.c",
        "vendor/brotli/enc/memory.c",
        "vendor/brotli/enc/metablock.c",
        "vendor/brotli/enc/static_dict.c",
        "vendor/brotli/enc/static_dict_lut.c",
        "vendor/brotli/enc/static_init.c",
        "vendor/brotli/enc/utf8_util.c",
    };

    lib.addCSourceFiles(.{
        .files = common_sources,
        .flags = cflags,
    });
    lib.addCSourceFiles(.{
        .files = dec_sources,
        .flags = cflags,
    });
    lib.addCSourceFiles(.{
        .files = enc_sources,
        .flags = cflags,
    });

    lib.linkLibC();
    return lib;
}

// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

// https://astro.build/config
export default defineConfig({
  site: "https://compressionz.nerdmenot.in",
  integrations: [
    starlight({
      title: "compressionz",
      logo: {
        light: "./public/logo-light.png",
        dark: "./public/logo-dark.png",
        replacesTitle: true,
      },
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/NerdMeNot/compressionz",
        },
      ],
      components: {
        ThemeSelect: "./src/components/ThemeSelect.astro",
        Head: "./src/components/Head.astro",
      },
      customCss: ["./src/styles/global.css"],
      sidebar: [
        { label: "Introduction", slug: "index" },
        {
          label: "Getting Started",
          items: [
            { label: "Introduction", slug: "getting-started/introduction" },
            { label: "Installation", slug: "getting-started/installation" },
            { label: "Quick Start", slug: "getting-started/quick-start" },
            { label: "Choosing a Codec", slug: "getting-started/choosing-a-codec" },
          ],
        },
        {
          label: "API Reference",
          items: [
            { label: "Compression", slug: "api/compression" },
            { label: "Decompression", slug: "api/decompression" },
            { label: "Streaming", slug: "api/streaming" },
            { label: "Zero-Copy", slug: "api/zero-copy" },
            { label: "Options", slug: "api/options" },
            { label: "Error Handling", slug: "api/errors" },
          ],
        },
        {
          label: "Codecs",
          items: [
            { label: "Overview", slug: "codecs/overview" },
            { label: "Zstandard (Zstd)", slug: "codecs/zstd" },
            { label: "LZ4", slug: "codecs/lz4" },
            { label: "Snappy", slug: "codecs/snappy" },
            { label: "Gzip", slug: "codecs/gzip" },
            { label: "Brotli", slug: "codecs/brotli" },
            { label: "Zlib & Deflate", slug: "codecs/zlib" },
          ],
        },
        {
          label: "Advanced",
          items: [
            { label: "Dictionary Compression", slug: "advanced/dictionary" },
            { label: "Archive Formats", slug: "advanced/archives" },
            { label: "Codec Detection", slug: "advanced/detection" },
            { label: "Memory Management", slug: "advanced/memory" },
            { label: "Testing", slug: "advanced/testing" },
            { label: "Security", slug: "advanced/security" },
          ],
        },
        {
          label: "Performance",
          items: [
            { label: "Benchmarks", slug: "performance/benchmarks" },
            { label: "Optimization Guide", slug: "performance/optimization" },
          ],
        },
        {
          label: "Internals",
          items: [
            { label: "Architecture", slug: "internals/architecture" },
            { label: "SIMD Optimizations", slug: "internals/simd" },
            { label: "Pure Zig Codecs", slug: "internals/pure-zig" },
            { label: "C Bindings", slug: "internals/c-bindings" },
          ],
        },
      ],
    }),
  ],
});

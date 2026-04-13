# TODO — gshard

## Runtime sharding (browser shared library)

A JS/TS library that can fetch a `.gshard` directory from a static host (like GitHub Pages) and reassemble the file in-browser at runtime.

### Architecture

```
gshard-web/
├── src/
│   ├── index.ts          # Main entry: fetchGshard(baseUrl) -> Blob | ArrayBuffer
│   ├── manifest.ts       # Parse manifest.gshard from text
│   ├── fetcher.ts        # Parallel chunk fetching with progress
│   └── assembler.ts      # Reassemble chunks into a single buffer
├── package.json
├── tsconfig.json
└── README.md
```

### Core API (draft)

```ts
import { fetchGshard } from 'gshard-web';

// Fetch and reassemble a sharded file from a static host
const blob = await fetchGshard('https://user.github.io/repo/assets/model.bin.gshard/', {
  concurrency: 4,           // parallel fetches (default: 4)
  onProgress: (loaded, total) => { ... },
});

// Use the blob
const url = URL.createObjectURL(blob);
```

### Tasks

- [ ] Set up project with Vite / esbuild for library mode
- [ ] Implement manifest parser (`manifest.gshard` → `{ name, chunks, chunkSize, totalSize }`)
- [ ] Implement parallel chunk fetcher with configurable concurrency
- [ ] Implement assembler: merge `ArrayBuffer[]` → single `Blob` or `ArrayBuffer`
- [ ] Integrity validation (compare assembled size against manifest)
- [ ] Progress callback support
- [ ] Error handling: retry logic, partial failure reporting
- [ ] Publish as npm package or standalone ES module
- [ ] Add optional WASM assembler (Odin compiled to WASM) for performance on very large files
  - [ ] Evaluate if `odin build -target:js_wasm32` is sufficient
  - [ ] Benchmark JS vs WASM assembly for files > 500 MB

### Nice-to-haves

- [ ] Streaming reassembly for files too large to hold in memory
- [ ] SHA-256 checksum per chunk in manifest for integrity verification
- [ ] CLI `gshard verify <dir>.gshard` command to validate chunk integrity
- [ ] Browser extension / service worker for transparent `.gshard` URL interception

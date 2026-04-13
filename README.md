# gshard

Break down large files into smaller chunks to upload them to repositories with limited upload sizes (like Git/GitHub's 100 MB hard limit).

## Compile-time sharding (CLI)

Built with [Odin](https://odin-lang.org).

### Build

```bash
odin build . -out:gshard -o:speed
```

### Usage

**Split** a file into shards (default: 50 MB chunks):

```bash
gshard large_model.bin
# Creates large_model.bin.gshard/
#   ├── manifest.gshard
#   ├── chunk_0000.bin
#   ├── chunk_0001.bin
#   └── ...
```

**Custom chunk size:**

```bash
gshard large_model.bin --size=25000000   # ~25 MB chunks
```

**Rebuild** the original file from shards:

```bash
gshard rebuild large_model.bin.gshard
# Recreates large_model.bin
```

### Manifest format

The `manifest.gshard` file is plain text:
```
<original filename>
<chunk count>
<chunk size in bytes>
<total file size in bytes>
```

## Runtime sharding (browser library)

A JS/TS library that fetches a `.gshard` directory from a static host (like GitHub Pages) and reassembles the file in-browser at runtime. Useful for serving large assets from static hosting without hitting file size limits.

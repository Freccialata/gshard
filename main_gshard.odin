package gshard

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:path/filepath"

APP_VERSION :: "0.1.0"

// Default shard size: 50 MB (just under GitHub's 50 MB warning threshold)
DEFAULT_SHARD_SIZE :: 50 * 1024 * 1024

GSHARD_EXT :: ".gshard"
MANIFEST_NAME :: "manifest.gshard"

// ── Manifest format (simple text) ──────────────────────────────────────────
// Line 0:  original filename   (e.g. "model.bin")
// Line 1:  total chunks        (e.g. "7")
// Line 2:  chunk size in bytes (e.g. "52428800")
// Line 3:  total file size     (e.g. "340000000")

Manifest :: struct {
	original_name: string,
	chunk_count:   int,
	chunk_size:    int,
	total_size:    i64,
}

// ── Helpers ────────────────────────────────────────────────────────────────

fatal :: proc(msg: string, args: ..any) {
	fmt.eprintfln(msg, ..args)
	os.exit(1)
}

format_size :: proc(bytes: i64) -> string {
	if bytes < 1024 {
		return fmt.tprintf("%d B", bytes)
	} else if bytes < 1024 * 1024 {
		return fmt.tprintf("%.1f KB", f64(bytes) / 1024.0)
	} else if bytes < 1024 * 1024 * 1024 {
		return fmt.tprintf("%.1f MB", f64(bytes) / (1024.0 * 1024.0))
	} else {
		return fmt.tprintf("%.2f GB", f64(bytes) / (1024.0 * 1024.0 * 1024.0))
	}
}

join :: proc(parts: []string) -> string {
	result := filepath.join(parts)
	// filepath.join returns the resulting string; allocation failure would panic by default
	return result
}

// ── Split command ──────────────────────────────────────────────────────────

cmd_split :: proc(file_path: string, shard_size: int) {
	// Validate input file
	if !os.exists(file_path) {
		fatal("Error: file '%s' does not exist.", file_path)
	}
	if os.is_dir(file_path) {
		fatal("Error: '%s' is a directory, not a file.", file_path)
	}

	// Read entire file
	data, read_ok := os.read_entire_file(file_path)
	if !read_ok {
		fatal("Error: could not read file '%s'", file_path)
	}
	defer delete(data)

	total_size := i64(len(data))
	if total_size == 0 {
		fatal("Error: file '%s' is empty.", file_path)
	}

	filename := filepath.base(file_path)
	parent_dir := filepath.dir(file_path)

	// Create output directory: <filename>.gshard/
	out_dir: string
	if len(parent_dir) > 0 {
		out_dir = join({parent_dir, fmt.tprintf("%s%s", filename, GSHARD_EXT)})
	} else {
		out_dir = fmt.tprintf("%s%s", filename, GSHARD_EXT)
	}

	if os.exists(out_dir) {
		fatal("Error: output directory '%s' already exists. Remove it first.", out_dir)
	}

	mkdir_err := os.make_directory(out_dir)
	if mkdir_err != os.ERROR_NONE {
		fatal("Error: could not create directory '%s'", out_dir)
	}

	// Calculate chunks
	chunk_count := int(total_size) / shard_size
	if int(total_size) % shard_size != 0 {
		chunk_count += 1
	}

	fmt.printfln("Splitting '%s' (%s) into %d chunks of %s each...",
		filename, format_size(total_size), chunk_count, format_size(i64(shard_size)))

	// Write chunks
	for i := 0; i < chunk_count; i += 1 {
		start := i * shard_size
		end := min((i + 1) * shard_size, int(total_size))
		chunk_data := data[start:end]

		chunk_name := fmt.tprintf("chunk_%04d.bin", i)
		chunk_path := join({out_dir, chunk_name})

		write_ok := os.write_entire_file(chunk_path, chunk_data)
		if !write_ok {
			fatal("Error: could not write chunk '%s'", chunk_path)
		}

		fmt.printfln("  [%d/%d] %s (%s)", i + 1, chunk_count, chunk_name, format_size(i64(len(chunk_data))))
	}

	// Write manifest
	manifest_content := fmt.tprintf("%s\n%d\n%d\n%d\n", filename, chunk_count, shard_size, total_size)
	manifest_path := join({out_dir, MANIFEST_NAME})
	manifest_ok := os.write_entire_file(manifest_path, transmute([]byte)manifest_content)
	if !manifest_ok {
		fatal("Error: could not write manifest '%s'", manifest_path)
	}

	fmt.printfln("\nDone! Output directory: %s", out_dir)
	fmt.printfln("To rebuild: gshard rebuild %s", out_dir)
}

// ── Rebuild command ────────────────────────────────────────────────────────

parse_manifest :: proc(dir_path: string) -> Manifest {
	manifest_path := join({dir_path, MANIFEST_NAME})

	data, read_ok := os.read_entire_file(manifest_path)
	if !read_ok {
		fatal("Error: could not read manifest at '%s'", manifest_path)
	}
	defer delete(data)

	content := string(data)
	lines := strings.split_lines(content)
	defer delete(lines)

	// Need at least 4 lines
	if len(lines) < 4 {
		fatal("Error: invalid manifest format in '%s'. Expected 4 lines, got %d.", manifest_path, len(lines))
	}

	chunk_count, chunk_ok := strconv.parse_int(strings.trim_space(lines[1]))
	if !chunk_ok {
		fatal("Error: invalid chunk count in manifest: '%s'.", lines[1])
	}

	chunk_size, size_ok := strconv.parse_int(strings.trim_space(lines[2]))
	if !size_ok {
		fatal("Error: invalid chunk size in manifest: '%s'.", lines[2])
	}

	total_size, total_ok := strconv.parse_i64(strings.trim_space(lines[3]))
	if !total_ok {
		fatal("Error: invalid total size in manifest: '%s'.", lines[3])
	}

	return Manifest{
		original_name = strings.clone(strings.trim_space(lines[0])),
		chunk_count   = chunk_count,
		chunk_size    = chunk_size,
		total_size    = total_size,
	}
}

cmd_rebuild :: proc(dir_path: string) {
	// Validate input directory
	if !os.exists(dir_path) {
		fatal("Error: directory '%s' does not exist.", dir_path)
	}
	if !os.is_dir(dir_path) {
		fatal("Error: '%s' is not a directory.", dir_path)
	}

	manifest := parse_manifest(dir_path)
	defer delete(manifest.original_name)

	fmt.printfln("Rebuilding '%s' from %d chunks (%s total)...",
		manifest.original_name, manifest.chunk_count, format_size(manifest.total_size))

	// Allocate output buffer
	output := make([]byte, manifest.total_size)
	defer delete(output)

	// Read each chunk into the buffer
	for i := 0; i < manifest.chunk_count; i += 1 {
		chunk_name := fmt.tprintf("chunk_%04d.bin", i)
		chunk_path := join({dir_path, chunk_name})

		chunk_data, read_ok := os.read_entire_file(chunk_path)
		if !read_ok {
			fatal("Error: could not read chunk '%s'", chunk_path)
		}
		defer delete(chunk_data)

		start := i * manifest.chunk_size
		copy(output[start:], chunk_data)

		fmt.printfln("  [%d/%d] %s (%s)", i + 1, manifest.chunk_count, chunk_name, format_size(i64(len(chunk_data))))
	}

	// Write output file next to the .gshard directory
	parent_dir := filepath.dir(dir_path)
	out_path: string
	if len(parent_dir) > 0 {
		out_path = join({parent_dir, manifest.original_name})
	} else {
		out_path = manifest.original_name
	}

	if os.exists(out_path) {
		fatal("Error: output file '%s' already exists. Remove it first.", out_path)
	}

	write_ok := os.write_entire_file(out_path, output)
	if !write_ok {
		fatal("Error: could not write output file '%s'", out_path)
	}

	fmt.printfln("\nDone! Rebuilt file: %s (%s)", out_path, format_size(manifest.total_size))
}

// ── CLI entry point ────────────────────────────────────────────────────────

print_usage :: proc() {
	fmt.eprintln("gshard — split and rebuild large files for git-friendly storage")
	fmt.eprintln("Version: " + APP_VERSION)
	fmt.eprintln()
	fmt.eprintln("Usage:")
	fmt.eprintln("  gshard <file_path>                        Split a file into shards (default 50 MB)")
	fmt.eprintln("  gshard <file_path> --size=<bytes>         Split with custom shard size")
	fmt.eprintln("  gshard rebuild <path>.gshard              Rebuild file from shards")
	fmt.eprintln()
	fmt.eprintln("Examples:")
	fmt.eprintln("  gshard large_model.bin")
	fmt.eprintln("  gshard large_model.bin --size=25000000    Split into ~25 MB chunks")
	fmt.eprintln("  gshard rebuild large_model.bin.gshard")
}

main :: proc() {
	args := os.args[1:] // skip executable name

	if len(args) == 0 {
		print_usage()
		os.exit(1)
	}

	// Check for help flag
	for arg in args {
		if arg == "--help" || arg == "-h" {
			print_usage()
			os.exit(0)
		}
	}

	// Parse command
	if args[0] == "rebuild" {
		if len(args) < 2 {
			fmt.eprintln("Error: 'rebuild' requires a path to a .gshard directory.")
			print_usage()
			os.exit(1)
		}
		cmd_rebuild(args[1])
	} else {
		// Split mode
		file_path := args[0]
		shard_size := DEFAULT_SHARD_SIZE

		// Parse optional --size flag
		for arg in args[1:] {
			if strings.has_prefix(arg, "--size=") {
				size_str := strings.trim_prefix(arg, "--size=")
				parsed, ok := strconv.parse_int(size_str)
				if !ok || parsed <= 0 {
					fatal("Error: invalid shard size '%s'. Must be a positive integer (bytes).", size_str)
				}
				shard_size = parsed
			} else {
				fmt.eprintfln("Warning: unknown option '%s', ignoring.", arg)
			}
		}

		cmd_split(file_path, shard_size)
	}
}

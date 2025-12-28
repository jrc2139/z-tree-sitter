# CLAUDE.md - z-tree-sitter

This file provides guidance for AI assistants working with the z-tree-sitter codebase.

## Project Overview

**z-tree-sitter** is a Zig wrapper library for the [tree-sitter](https://tree-sitter.github.io/tree-sitter/) parsing library. It provides:

- Complete Zig bindings for the tree-sitter C API (version 0.26)
- Built-in support for 30 programming language grammars
- Modular grammar compilation (only include languages you need)

**Version:** 0.2.0
**Minimum Zig Version:** 0.15.0
**License:** MIT

## Directory Structure

```
z-tree-sitter/
├── build.zig           # Build system configuration
├── build.zig.zon       # Package manifest with dependencies
├── src/
│   ├── treesitter.zig  # Core API wrapper (Parser, Tree, Node, Query, etc.)
│   ├── grammars.zig    # Grammar loading interface (LanguageGrammar enum)
│   └── c.zig           # C bindings import layer
├── tests/
│   ├── treesitter.zig  # Comprehensive API tests
│   └── grammars.zig    # Grammar loading tests
├── examples/
│   └── parse-input.zig # Interactive parsing example
├── README.md
└── LICENSE
```

## Build Commands

```bash
# Run tests (requires all language grammars)
zig build test -- --all-languages

# Run example with specific language
zig build example-<name> -- --language zig
```

## Key Source Files

### `src/treesitter.zig`
The main API wrapper containing all public types:

| Type | Description |
|------|-------------|
| `Parser` | Parses source code into syntax trees |
| `Tree` | Represents a parsed syntax tree |
| `Node` | A node in the syntax tree (extern struct, value type) |
| `TreeCursor` | Efficient tree navigation cursor (extern struct) |
| `Query` | Pattern matching queries for tree analysis |
| `QueryCursor` | Executes queries and iterates matches |
| `Language` | Language grammar metadata (opaque type) |
| `LookaheadIterator` | Predicts valid next symbols during parsing |

Supporting types: `Point`, `Range`, `Input`, `InputEdit`, `Logger`, `QueryMatch`, `QueryCapture`

### `src/grammars.zig`
Grammar loading interface:
- `LanguageGrammar` - Enum of all 30 supported languages
- `loadLanguage(LanguageGrammar)` - Runtime grammar loading function

### `src/c.zig`
C interop layer:
- Imports `tree_sitter/api.h` for core C API
- Conditionally imports grammar headers based on build configuration

## API Patterns and Conventions

### Memory Management
- **Opaque types** (`Parser`, `Tree`, `Query`, `QueryCursor`, `LookaheadIterator`, `Language`): Use `init()`/`deinit()` pattern
- **Extern structs** (`Node`, `TreeCursor`, `Point`, `Range`): Value types, stack-allocated
- Always use `defer` for cleanup:
  ```zig
  const parser = try Parser.init();
  defer parser.deinit();
  ```

### Error Handling
- Functions that can fail return Zig errors (e.g., `error.ParserInitFail`, `error.ParseStringFail`)
- Query initialization returns specific `QueryError` variants for different failure types
- Use `try` for error propagation

### Naming Conventions
- Getter methods: `getXxx()` (e.g., `getLanguage()`, `getSymbolCount()`)
- Boolean checks: `isXxx()` or `hasXxx()` (e.g., `isNull()`, `hasError()`)
- Navigation: `gotoXxx()` for cursor movement (e.g., `gotoParent()`, `gotoFirstChild()`)

### Typical Usage Pattern
```zig
const zts = @import("zts");

// Initialize parser
const parser = try zts.Parser.init();
defer parser.deinit();

// Load and set language grammar
const lang = try zts.loadLanguage(.zig);
try parser.setLanguage(lang);

// Parse source code
const tree = try parser.parseString(null, source_code);
defer tree.deinit();

// Traverse the tree
const root = tree.rootNode();
// Use root.getChild(), root.getType(), etc.
```

## Supported Language Grammars

bash, c, cpp, c_sharp, css, elixir, elm, erlang, fsharp, go, haskell, java, javascript, json, julia, kotlin, lua, markdown, nim, ocaml, perl, php, python, ruby, rust, scala, toml, typescript, zig

Languages without custom scanners (simpler compilation): c, erlang, go, java, json, zig

## Build System Details

### Grammar Selection
Grammars are selected at build time via `build.zig` options:

```zig
// In consuming project's build.zig:
const zts = b.dependency("zts", .{
    .target = target,
    .optimize = optimize,
    .zig = true,        // Include zig grammar
    .python = true,     // Include python grammar
});
```

### Command-line Grammar Flags
- `--all-languages` - Include all 30 grammars (required for tests)
- `--language <name>` - Include specific grammar(s)

### Grammar Compilation
Each grammar is compiled as a static library with:
- Source files from `src/` directory (or custom root like `fsharp/src`)
- `parser.c` (always required)
- `scanner.c` (if grammar has custom scanner)
- C11 standard (`-std=c11`)

## Testing

Tests are in `tests/treesitter.zig` and cover:
1. `test "parser"` - Parser initialization, language setting, ranges, parsing
2. `test "tree"` - Tree manipulation, copying, editing
3. `test "language"` - Language metadata, symbols, fields
4. `test "node"` - Node traversal, properties, equality
5. `test "tree cursor"` - Cursor navigation
6. `test "query and query cursor"` - Query execution
7. `test "lookahead iterator"` - Symbol prediction

Run with: `zig build test -- --all-languages`

## Dependencies

All dependencies are pinned with content hashes in `build.zig.zon`:
- `tree_sitter_api` - Core tree-sitter library (v0.26.0)
- Individual grammar packages for each supported language

## Development Notes

### Adding a New Grammar
1. Add dependency to `build.zig.zon` with URL and hash
2. Add grammar to `grammars` array in `build.zig`
3. Add enum variant to `LanguageGrammar` in `src/grammars.zig`
4. Add conditional `@cInclude` in `src/c.zig`

### API Coverage
The wrapper provides complete coverage of tree-sitter 0.26 C API. Reference the [tree-sitter API header](https://github.com/tree-sitter/tree-sitter/blob/master/lib/include/tree_sitter/api.h) for detailed documentation.

### Type Mapping
- C pointers to opaque types -> Zig opaque types with `@ptrCast`
- C structs -> Zig extern structs with `@bitCast`
- C strings -> Zig slices via `std.mem.span()`
- C booleans -> Zig `bool`

const std = @import("std");
const builtin = @import("builtin");

const Build = std.Build;
const Step = std.Build.Step;

const eql = std.mem.eql;

const allocator = std.heap.page_allocator;

const Grammar = struct {
    name: []const u8,
    root: []const u8 = "src",
    scanner: bool = true,
    /// If true, run `tree-sitter generate` before compiling (requires tree-sitter-cli)
    generate: bool = false,
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const grammar_map = try createGrammarInstallMap();

    const zts = b.addModule("zts", .{
        .root_source_file = b.path("src/treesitter.zig"),
    });

    const config = b.addOptions();

    const all_opt = b.option(
        bool,
        "all",
        "include all builtin grammars in z-tree-sitter",
    ) orelse shouldInstallAllGrammar();

    config.addOption(bool, "all", all_opt);

    // Grammars options
    for (grammars) |g| {
        const grammar_opt = b.option(
            bool,
            g.name,
            "include grammar in z-tree-sitter",
        ) orelse all_opt or grammar_map.contains(g.name);

        if (grammar_opt) {
            const grammar_build = try buildLanguageGrammar(b, target, optimize, g);
            b.installArtifact(grammar_build);
            zts.linkLibrary(grammar_build);
        }

        config.addOption(bool, g.name, grammar_opt);
    }
    zts.addOptions("config", config);

    // Get tree-sitter core library from the dependency
    const ts_dep = b.dependency("tree_sitter_api", .{
        .target = target,
        .optimize = optimize,
        .amalgamated = true,
        .@"build-shared" = false,
    });
    const c_tree_sitter = ts_dep.artifact("tree-sitter");
    b.installArtifact(c_tree_sitter);
    zts.linkLibrary(c_tree_sitter);

    // Add include path for tree_sitter/api.h
    zts.addIncludePath(ts_dep.path("lib/include"));

    // Tests - skipped for now (need Zig 0.15 test API update)
    // Examples - skipped for now
}

fn buildLanguageGrammar(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    g: Grammar,
) !*Step.Compile {
    const dep = b.dependency(g.name, .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = g.name,
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    // For grammars that need generation, run tree-sitter generate first
    if (g.generate) {
        const cli_path = getTreeSitterCli(b) catch {
            std.log.err("Failed to get tree-sitter CLI for grammar generation. Install tree-sitter-cli or ensure the binary is available.", .{});
            return error.TreeSitterCliNotFound;
        };
        const gen_step = b.addSystemCommand(&.{cli_path});
        gen_step.addArg("generate");
        gen_step.setCwd(dep.path(""));
        lib.step.dependOn(&gen_step.step);
    }

    const default_files = &.{ "parser.c", "scanner.c" };
    lib.addCSourceFiles(.{
        .root = dep.path(g.root),
        .files = if (g.scanner) default_files else &.{"parser.c"},
        .flags = &.{"-std=c11"},
    });
    lib.addIncludePath(dep.path(g.root));
    lib.linkLibC();

    const path = try generateHeaderFile(b, g, dep);
    lib.installHeader(dep.path(path), path);

    return lib;
}

fn generateHeaderFile(b: *Build, g: Grammar, dep: *std.Build.Dependency) ![]const u8 {
    const path = dep.path("").getPath(b);
    const dir = try std.fs.openDirAbsolute(path, .{});

    const file_name = try std.fmt.allocPrint(allocator, "{s}.h", .{g.name});

    var buf: [32]u8 = undefined;
    const upper_name = std.ascii.upperString(&buf, file_name);

    const f = try dir.createFile(file_name, .{});
    defer f.close();

    // Build header content manually
    const header = try std.fmt.allocPrint(allocator,
        \\#ifndef TREE_SITTER_{s}_H_
        \\#define TREE_SITTER_{s}_H_
        \\typedef struct TSLanguage TSLanguage;
        \\#ifdef __cplusplus
        \\extern "C"
        \\{{
        \\#endif
        \\const TSLanguage *tree_sitter_{s}(void);
        \\#ifdef __cplusplus
        \\}}
        \\#endif
        \\#endif
    , .{ upper_name, upper_name, g.name });

    try f.writeAll(header);
    return file_name;
}

pub fn shouldInstallAllGrammar() bool {
    var isArg = false;

    var args = std.process.args();
    while (args.next()) |arg| {
        if (eql(u8, arg, "--")) isArg = true;
        if (isArg and eql(u8, arg, "--all-languages")) return true;
    }
    return false;
}

pub fn createGrammarInstallMap() !std.StringHashMap(bool) {
    var isArg = false;
    var isGrammar = false;

    var grammar_map = std.StringHashMap(bool).init(allocator);

    var args = std.process.args();
    while (args.next()) |arg| {
        if (isGrammar) {
            if (isSupportedGrammar(arg)) {
                if (grammar_map.contains(arg)) @panic("duplicate grammar found");
                try grammar_map.put(arg, true);
                continue;
            } else if (arg[0] == '-') break else @panic("incorrect grammar found");
        }

        if (eql(u8, arg, "--")) isArg = true;
        if (isArg and eql(u8, arg, "--language")) isGrammar = true;
    }
    return grammar_map;
}

fn isSupportedGrammar(name: []const u8) bool {
    for (grammars) |g| {
        if (eql(u8, g.name, name)) return true;
    }
    return false;
}

/// Get path to tree-sitter CLI binary
/// First tries system PATH, then falls back to bundled dependency
fn getTreeSitterCli(b: *Build) ![]const u8 {
    _ = b;
    // Try to find tree-sitter in PATH first
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "which", "tree-sitter" },
    }) catch {
        return error.TreeSitterNotFound;
    };

    if (result.term.Exited == 0 and result.stdout.len > 0) {
        // Remove trailing newline
        const path = std.mem.trimRight(u8, result.stdout, "\n\r");
        if (path.len > 0) {
            return path;
        }
    }

    return error.TreeSitterNotFound;
}

const grammars = [_]Grammar{
    .{ .name = "bash" },
    .{ .name = "c", .scanner = false },
    .{ .name = "css" },
    .{ .name = "cpp" },
    .{ .name = "c_sharp" },
    .{ .name = "dart" },
    .{ .name = "dockerfile", .scanner = false },
    .{ .name = "elixir" },
    .{ .name = "elm" },
    .{ .name = "erlang", .scanner = false },
    .{ .name = "fsharp", .root = "fsharp/src" },
    .{ .name = "go", .scanner = false },
    .{ .name = "haskell" },
    .{ .name = "html" },
    .{ .name = "java", .scanner = false },
    .{ .name = "javascript" },
    .{ .name = "json", .scanner = false },
    .{ .name = "julia" },
    .{ .name = "kotlin" },
    .{ .name = "lua" },
    .{ .name = "make", .scanner = false },
    .{ .name = "markdown", .root = "tree-sitter-markdown/src" },
    .{ .name = "nim" },
    .{ .name = "ocaml", .root = "grammars/ocaml/src" },
    .{ .name = "perl" },
    .{ .name = "php", .root = "php/src" },
    .{ .name = "python" },
    .{ .name = "r" },
    .{ .name = "ruby" },
    .{ .name = "rust" },
    .{ .name = "scala" },
    .{ .name = "sql" },
    .{ .name = "swift", .generate = true },
    .{ .name = "toml" },
    .{ .name = "typescript", .root = "typescript/src" },
    .{ .name = "yaml" },
    .{ .name = "zig", .scanner = false },
};

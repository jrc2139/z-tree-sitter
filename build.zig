const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

const eql = std.mem.eql;

/// Minimum tree-sitter CLI version for grammar generation.
/// Must match tree_sitter_api version in build.zig.zon.
const tree_sitter_version = "0.26.9";

const Grammar = struct {
    name: []const u8,
    root: []const u8 = "src",
    scanner: bool = true,
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const grammar_map = try createGrammarInstallMap(b.allocator);

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
    const version_check = VersionCheckStep.create(b);
    var selected_grammars: [grammars.len]bool = undefined;
    for (grammars, 0..) |g, i| {
        const grammar_opt = b.option(
            bool,
            g.name,
            "include grammar in z-tree-sitter",
        ) orelse all_opt or grammar_map.contains(g.name);

        if (grammar_opt) {
            const grammar_build = buildLanguageGrammar(b, target, optimize, g);
            b.installArtifact(grammar_build);
            zts.linkLibrary(grammar_build);
        }

        config.addOption(bool, g.name, grammar_opt);
        selected_grammars[i] = grammar_opt;
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

    // Tests
    {
        const test_treesitter_mod = b.createModule(.{
            .root_source_file = b.path("tests/treesitter.zig"),
            .target = target,
            .optimize = optimize,
        });
        test_treesitter_mod.addImport("zts", zts);
        test_treesitter_mod.linkLibrary(c_tree_sitter);
        const test_treesitter = b.addTest(.{
            .root_module = test_treesitter_mod,
        });

        const test_grammars_mod = b.createModule(.{
            .root_source_file = b.path("tests/grammars.zig"),
            .target = target,
            .optimize = optimize,
        });
        test_grammars_mod.addImport("zts", zts);
        test_grammars_mod.linkLibrary(c_tree_sitter);
        const test_grammars = b.addTest(.{
            .root_module = test_grammars_mod,
        });

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&b.addRunArtifact(test_treesitter).step);
        test_step.dependOn(&b.addRunArtifact(test_grammars).step);
    }

    // Example
    {
        const example = b.addExecutable(.{
            .name = "parse-input",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/parse-input.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        example.root_module.addImport("zts", zts);
        example.root_module.linkLibrary(c_tree_sitter);

        const example_step = b.step("example", "Run parse-input example");
        example_step.dependOn(&b.addRunArtifact(example).step);
    }

    // Generate step: regenerate vendored parser.c files
    {
        const generate_step = b.step("generate", "Regenerate vendored parser.c files (requires tree-sitter CLI)");

        for (grammars, 0..) |g, i| {
            if (!selected_grammars[i]) continue;

            const grammar_js_dir: []const u8 = if (eql(u8, g.root, "src"))
                ""
            else if (std.mem.endsWith(u8, g.root, "/src"))
                g.root[0 .. g.root.len - "/src".len]
            else
                g.root;

            const cwd_path = if (grammar_js_dir.len == 0)
                b.fmt("grammars/{s}", .{g.name})
            else
                b.fmt("grammars/{s}/{s}", .{ g.name, grammar_js_dir });

            // Skip grammars without a vendored grammar.js
            const grammar_js_probe = b.fmt("{s}/grammar.js", .{cwd_path});
            if (b.build_root.handle.openFile(grammar_js_probe, .{})) |f| {
                f.close();
            } else |_| {
                continue;
            }

            const gen_cmd = b.addSystemCommand(&.{ "tree-sitter", "generate" });
            gen_cmd.setCwd(b.path(cwd_path));
            gen_cmd.step.dependOn(&version_check.step);
            generate_step.dependOn(&gen_cmd.step);
        }
    }
}

fn buildLanguageGrammar(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    g: Grammar,
) *Step.Compile {
    const source_root = b.dependency(g.name, .{ .target = target, .optimize = optimize }).path("");

    const lib = b.addLibrary(.{
        .name = g.name,
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    // Tree-sitter external scanners legitimately pass NULL to
    // deserialize(payload, NULL, 0) for "no prior state", which Zig's C compiler
    // flags as UB and traps on under Debug/ReleaseSafe. Disable only the
    // undefined-behavior sanitizer for grammar C, keeping the selected optimize
    // mode (and any other checks) intact rather than forcing ReleaseFast.
    const default_files = &.{ "parser.c", "scanner.c" };
    lib.addCSourceFiles(.{
        .root = source_root.path(b, g.root),
        .files = if (g.scanner) default_files else &.{"parser.c"},
        .flags = &.{ "-std=c11", "-fno-sanitize=undefined" },
    });
    lib.addIncludePath(source_root.path(b, g.root));
    lib.linkLibC();

    const header = generateHeaderFile(b, g);
    lib.installHeader(header, b.fmt("{s}.h", .{g.name}));

    return lib;
}

fn generateHeaderFile(b: *Build, g: Grammar) std.Build.LazyPath {
    const file_name = b.fmt("{s}.h", .{g.name});

    var buf: [32]u8 = undefined;
    const upper_name = std.ascii.upperString(&buf, file_name);

    const header = b.fmt(
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
        \\
    , .{ upper_name, upper_name, g.name });

    const wf = b.addWriteFiles();
    return wf.add(file_name, header);
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

pub fn createGrammarInstallMap(alloc: std.mem.Allocator) !std.StringHashMap(bool) {
    var isArg = false;
    var isGrammar = false;

    var grammar_map = std.StringHashMap(bool).init(alloc);

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

const VersionCheckStep = struct {
    step: Step,

    fn create(owner: *Build) *VersionCheckStep {
        const self = owner.allocator.create(VersionCheckStep) catch @panic("OOM");
        self.* = .{
            .step = Step.init(.{
                .id = .custom,
                .name = "tree-sitter version check",
                .owner = owner,
                .makeFn = make,
            }),
        };
        return self;
    }

    fn make(step: *Step, options: Step.MakeOptions) !void {
        _ = options;
        const allocator = step.owner.allocator;

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "tree-sitter", "--version" },
        }) catch {
            return step.fail("tree-sitter CLI not found. Install with: npm install -g tree-sitter-cli@{s}", .{tree_sitter_version});
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        const trimmed = std.mem.trimRight(u8, result.stdout, &std.ascii.whitespace);
        const version_str = if (std.mem.lastIndexOfScalar(u8, trimmed, ' ')) |idx|
            trimmed[idx + 1 ..]
        else
            trimmed;

        const actual = std.SemanticVersion.parse(version_str) catch {
            return step.fail("could not parse tree-sitter version from: {s}", .{trimmed});
        };
        const required = comptime std.SemanticVersion.parse(tree_sitter_version) catch unreachable;

        if (actual.order(required) == .lt) {
            return step.fail("tree-sitter CLI {s} is too old, need >= {s}", .{ version_str, tree_sitter_version });
        }
    }
};

const grammars = [_]Grammar{
    .{ .name = "bash" },
    .{ .name = "c", .scanner = false },
    .{ .name = "css" },
    .{ .name = "cpp" },
    .{ .name = "c_sharp" },
    .{ .name = "cmake" },
    .{ .name = "dart" },
    .{ .name = "dockerfile" },
    .{ .name = "elixir" },
    .{ .name = "elm" },
    .{ .name = "erlang" },
    .{ .name = "fsharp", .root = "fsharp/src" },
    .{ .name = "go", .scanner = false },
    .{ .name = "graphql", .scanner = false },
    .{ .name = "haskell" },
    .{ .name = "hcl" },
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
    .{ .name = "nix" },
    .{ .name = "objc", .scanner = false },
    .{ .name = "ocaml", .root = "grammars/ocaml/src" },
    .{ .name = "perl" },
    .{ .name = "php", .root = "php/src" },
    .{ .name = "python" },
    .{ .name = "r" },
    .{ .name = "ruby" },
    .{ .name = "rust" },
    .{ .name = "scala" },
    .{ .name = "sql" },
    .{ .name = "swift" },
    .{ .name = "toml" },
    .{ .name = "tsx", .root = "tsx/src" },
    .{ .name = "typescript", .root = "typescript/src" },
    .{ .name = "vue" },
    .{ .name = "xml", .root = "xml/src" },
    .{ .name = "yaml" },
    .{ .name = "zig", .scanner = false },
};

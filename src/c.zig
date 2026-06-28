const config = @import("config");

pub const tree_sitter = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub const grammars = @cImport({
    if (config.bash) @cInclude("bash.h");
    if (config.c) @cInclude("c.h");
    if (config.css) @cInclude("css.h");
    if (config.cpp) @cInclude("cpp.h");
    if (config.c_sharp) @cInclude("c_sharp.h");
    if (config.cmake) @cInclude("cmake.h");
    if (config.dart) @cInclude("dart.h");
    if (config.dockerfile) @cInclude("dockerfile.h");
    if (config.elixir) @cInclude("elixir.h");
    if (config.elm) @cInclude("elm.h");
    if (config.erlang) @cInclude("erlang.h");
    if (config.fsharp) @cInclude("fsharp.h");
    if (config.go) @cInclude("go.h");
    if (config.graphql) @cInclude("graphql.h");
    if (config.haskell) @cInclude("haskell.h");
    if (config.hcl) @cInclude("hcl.h");
    if (config.html) @cInclude("html.h");
    if (config.java) @cInclude("java.h");
    if (config.javascript) @cInclude("javascript.h");
    if (config.json) @cInclude("json.h");
    if (config.julia) @cInclude("julia.h");
    if (config.kotlin) @cInclude("kotlin.h");
    if (config.lua) @cInclude("lua.h");
    if (config.make) @cInclude("make.h");
    if (config.markdown) @cInclude("markdown.h");
    if (config.nim) @cInclude("nim.h");
    if (config.nix) @cInclude("nix.h");
    if (config.objc) @cInclude("objc.h");
    if (config.ocaml) @cInclude("ocaml.h");
    if (config.perl) @cInclude("perl.h");
    if (config.php) @cInclude("php.h");
    if (config.python) @cInclude("python.h");
    if (config.r) @cInclude("r.h");
    if (config.ruby) @cInclude("ruby.h");
    if (config.rust) @cInclude("rust.h");
    if (config.scala) @cInclude("scala.h");
    if (config.sql) @cInclude("sql.h");
    if (config.swift) @cInclude("swift.h");
    if (config.toml) @cInclude("toml.h");
    if (config.tsx) @cInclude("tsx.h");
    if (config.typescript) @cInclude("typescript.h");
    if (config.vue) @cInclude("vue.h");
    if (config.xml) @cInclude("xml.h");
    if (config.yaml) @cInclude("yaml.h");
    if (config.zig) @cInclude("zig.h");
});

/// tree-sitter's active free function from its overridable allocator
/// (alloc.h: `extern void (*ts_current_free)(void *ptr)`). Defaults to libc
/// free and is updated by `ts_set_allocator`. Buffers that tree-sitter
/// allocated (node strings, range arrays) must be released through this so
/// frees match whatever allocator is currently installed.
pub extern var ts_current_free: *const fn (?*anyopaque) callconv(.c) void;

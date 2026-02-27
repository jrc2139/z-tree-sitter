const std = @import("std");
const config = @import("config");

const Language = @import("treesitter.zig").Language;
const grammars = @import("c.zig").grammars;

pub const LanguageGrammar = enum {
    bash,
    c,
    css,
    cpp,
    c_sharp,
    cmake,
    dart,
    dockerfile,
    elixir,
    elm,
    erlang,
    fsharp,
    go,
    graphql,
    haskell,
    hcl,
    html,
    java,
    javascript,
    json,
    julia,
    kotlin,
    lua,
    make,
    markdown,
    nim,
    nix,
    objc,
    ocaml,
    perl,
    php,
    python,
    r,
    ruby,
    rust,
    scala,
    sql,
    swift,
    toml,
    tsx,
    typescript,
    vue,
    xml,
    yaml,
    zig,
};

pub inline fn loadLanguage(lg: LanguageGrammar) !*const Language {
    const name = @tagName(lg);
    if (!@field(config, name)) return error.FetchingGrammarFail;

    const c_func = @field(grammars, "tree_sitter_" ++ name);
    return if (c_func()) |lang| @ptrCast(lang) else error.InvalidLang;
}

pub inline fn loadLanguageComptime(comptime lg: LanguageGrammar) *const Language {
    const name = @tagName(lg);
    if (!@field(config, name)) @compileError("grammar '" ++ name ++ "' is not enabled in this build");

    const c_func = @field(grammars, "tree_sitter_" ++ name);
    return @ptrCast(c_func() orelse unreachable);
}

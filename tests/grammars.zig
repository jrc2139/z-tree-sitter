const std = @import("std");
const zts = @import("zts");

const Parser = zts.Parser;

test "grammars" {
    const p = try Parser.init();
    defer p.deinit();

    inline for (std.meta.fields(zts.LanguageGrammar)) |lang| {
        const lg: zts.LanguageGrammar = @enumFromInt(lang.value);
        if (zts.loadLanguage(lg)) |grammar| {
            defer grammar.deinit();
            try p.setLanguage(grammar);
        } else |_| {
            // Grammar not enabled in this build - skip
        }
    }
}

test "comptime grammar loading" {
    const zig_lang = zts.loadLanguageComptime(.zig);
    try std.testing.expect(zig_lang.getSymbolCount() > 0);
    try std.testing.expect(zig_lang.getAbiVersion() >= 13);
}

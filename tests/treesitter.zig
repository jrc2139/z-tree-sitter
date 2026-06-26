const std = @import("std");
const zts = @import("zts");

const Parser = zts.Parser;
const Point = zts.Point;
const Range = zts.Range;
const TreeCursor = zts.TreeCursor;
const Query = zts.Query;
const QueryCursor = zts.QueryCursor;
const LookaheadIterator = zts.LookaheadIterator;

const loadLanguage = zts.loadLanguage;

// --- Part 2: Strengthened existing tests ---

test "parser" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);

    // Language is null before set
    try std.testing.expect(p.getLanguage() == null);
    try p.setLanguage(zig);
    // Language is non-null after set
    try std.testing.expect(p.getLanguage() != null);

    const sp = Point{ .column = 0, .row = 0 };
    const ep = Point{ .column = 1, .row = 1 };

    const ranges = [_]Range{
        .{ .start_point = sp, .end_point = ep, .start_byte = 0, .end_byte = 0 },
    };
    try p.setIncludedRanges(&ranges);
    const included = p.getIncludedRanges();
    try std.testing.expectEqual(@as(usize, 1), included.len);

    const text = "const Foo = 0;";

    const tree1 = try p.parseString(null, text);
    tree1.deinit();
    const tree2 = try p.parseStringEncoding(null, text, .utf16_le);
    tree2.deinit();

    p.reset();
    p.printDotGraphs(-1);
}

test "tree" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const text = "const Foo = 0;";

    const tree = try p.parseString(null, text);
    defer tree.deinit();

    const tree_copy = try tree.copy();
    defer tree_copy.deinit();

    const root = tree.rootNode();
    try std.testing.expectEqualStrings("source_file", root.getType());

    const oe = Point{ .column = 0, .row = 0 };
    _ = tree.rootNodeWithOffset(0, oe);

    try std.testing.expect(tree.getLanguage() != null);

    const included = tree.getIncludedRanges();
    defer included.deinit();
    try std.testing.expect(included.slice().len > 0);

    const ie = zts.InputEdit{
        .start_byte = 6,
        .old_end_byte = 9,
        .new_end_byte = 10,
        .start_point = Point{ .row = 0, .column = 6 },
        .old_end_point = Point{ .row = 0, .column = 9 },
        .new_end_point = Point{ .row = 0, .column = 10 },
    };
    tree.edit(&ie);
    const changed = tree.getChangedRanges(tree_copy);
    defer changed.deinit();
}

test "language" {
    const lang = try loadLanguage(.zig);
    defer lang.deinit();

    const lang_copy = try lang.copy();
    defer lang_copy.deinit();

    try std.testing.expect(lang.getSymbolCount() > 0);
    try std.testing.expect(lang.getStateCount() > 0);
    try std.testing.expect(lang.getFieldCount() > 0);
    try std.testing.expect(lang.getAbiVersion() >= 13);
    // getName() may return null for grammars built without name metadata
    _ = lang.getName();

    _ = lang.getSymbolName(1);
    _ = lang.getSymbolForName("if", true);
    _ = lang.getFieldNameForId(1);
    _ = lang.getFieldIdForName("if");
    _ = lang.getSymbolType(1);
    _ = lang.getNextState(1, 1);
    _ = lang.getMetadata();

    _ = lang.getSupertypes();
}

test "node" {
    const text = "const Foo  = 0;";
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, text);
    defer tree.deinit();
    const node = tree.rootNode();

    try std.testing.expectEqualStrings("source_file", node.getType());
    try std.testing.expect(node.isNamed());
    try std.testing.expect(!node.isNull());
    try std.testing.expect(!node.hasError());
    try std.testing.expect(node.getChildCount() > 0);
    try std.testing.expect(node.getParent() == null);

    _ = node.getSymbol();
    _ = node.getLanguage();
    _ = node.getGrammarType();
    _ = node.getGrammarSymbol();
    _ = node.getStartByte();
    _ = node.getStartPoint();
    _ = node.getEndByte();
    _ = node.getEndPoint();

    const node_str = node.toString();
    defer node_str.deinit();
    try std.testing.expect(node_str.slice().len > 0);

    _ = node.isMissing();
    _ = node.isExtra();
    _ = node.isError();
    _ = node.getParseState();
    _ = node.getNextParseState();

    if (node.getChild(0)) |child| {
        _ = node.childWithDescendant(child);
    }

    _ = node.getFieldNameForChild(0);
    _ = node.getFieldNameForNamedChild(0);
    _ = node.getNamedChild(0);
    _ = node.getNamedChildCount();
    _ = node.getChildByFieldName("foo");
    _ = node.getNextSibling();
    _ = node.getPrevSibling();
    _ = node.getDescendantCount();
    _ = node.getDescendantForByteRange(0, text.len);

    var edit_input = zts.InputEdit{
        .start_byte = 6,
        .old_end_byte = 9,
        .new_end_byte = 10,
        .start_point = Point{ .row = 0, .column = 6 },
        .old_end_point = Point{ .row = 0, .column = 9 },
        .new_end_point = Point{ .row = 0, .column = 10 },
    };
    var edited = node;
    zts.editNode(&edited, &edit_input);

    _ = node.eq(node);
}

test "tree cursor" {
    const text = "const Foo = 0;";
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, text);
    defer tree.deinit();
    const root_node = tree.rootNode();

    var cursor = TreeCursor.init(root_node);
    defer cursor.deinit();

    // Initial depth is 0 (root)
    try std.testing.expectEqual(@as(u32, 0), cursor.currentDepth());

    // Go to first child, depth becomes 1
    try std.testing.expect(cursor.gotoFirstChild());
    try std.testing.expectEqual(@as(u32, 1), cursor.currentDepth());

    // Go back to parent, depth returns to 0
    try std.testing.expect(cursor.gotoParent());
    try std.testing.expectEqual(@as(u32, 0), cursor.currentDepth());

    _ = cursor.currentNode();
    _ = cursor.currentFieldName();
    _ = cursor.currentFieldId();
    _ = cursor.gotoNextSibling();
    _ = cursor.gotoPreviousSibling();
    _ = cursor.gotoLastChild();
    cursor.gotoDescendant(0);
    _ = cursor.currentDescendantIndex();
    _ = cursor.gotoFirstChildForByte(5);
    _ = cursor.gotoFirstChildForPoint(Point{ .row = 0, .column = 6 });

    var copied_cursor = cursor.copy();
    defer copied_cursor.deinit();

    cursor.reset(root_node);
    cursor.resetTo(&copied_cursor);
}

test "query and query cursor" {
    const text = "const Foo = 0;";
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, text);
    defer tree.deinit();
    const node = tree.rootNode();

    // Use a real query that matches something
    const query_source = "(variable_declaration) @decl";

    var query = try Query.init(zig, query_source);
    defer query.deinit();

    try std.testing.expect(query.patternCount() > 0);
    try std.testing.expect(query.captureCount() > 0);
    _ = query.stringCount();
    _ = query.startByteForPattern(0);
    _ = query.endByteForPattern(0);

    var step_count: u32 = 0;
    _ = query.predicatesForPattern(0, &step_count);
    _ = query.isPatternRooted(0);
    _ = query.isPatternNonLocal(0);
    _ = query.isPatternGuaranteedAtStep(0);

    const capture_name = query.captureNameForId(0);
    try std.testing.expect(capture_name != null);
    try std.testing.expectEqualStrings("decl", capture_name.?);

    _ = query.captureQuantifierForId(0, 0);
    _ = query.stringValueForId(0);

    var cursor = try QueryCursor.init();
    defer cursor.deinit();
    cursor.exec(query, node);

    // Should find at least one match
    var match: zts.QueryMatch = undefined;
    try std.testing.expect(cursor.nextMatch(&match));
    try std.testing.expect(match.capture_count > 0);

    cursor.removeMatch(match.id);
    var capture_index: u32 = 0;
    _ = cursor.nextCapture(&match, &capture_index);

    _ = cursor.didExceedMatchLimit();
    _ = cursor.matchLimit();
    cursor.setMatchLimit(1000);
    _ = cursor.setByteRange(0, text.len);
    _ = cursor.setPointRange(Point{ .row = 0, .column = 0 }, Point{ .row = 1, .column = 0 });
    _ = cursor.setContainingByteRange(0, text.len);
    _ = cursor.setContainingPointRange(Point{ .row = 0, .column = 0 }, Point{ .row = 1, .column = 0 });
    cursor.setMaxStartDepth(5);

    query.disableCapture("decl");
    query.disablePattern(0);
}

test "lookahead iterator" {
    const lang = try loadLanguage(.zig);
    defer lang.deinit();

    const state = 1;
    const iterator = try LookaheadIterator.init(lang, state);
    defer iterator.deinit();

    _ = try iterator.resetState(2);
    _ = try iterator.reset(lang, 3);
    _ = iterator.getLanguage();
    _ = iterator.next();
    _ = iterator.currentSymbol();
    _ = iterator.currentSymbolName();
}

test "parse options" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const options = zts.ParseOptions{};
    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();

    try std.testing.expect(options.payload == null);
    try std.testing.expect(options.progress_callback == null);
}

test "node string memory management" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();

    const root = tree.rootNode();
    const s = root.toString();
    defer s.deinit();

    try std.testing.expect(s.slice().len > 0);
    try std.testing.expect(std.mem.startsWith(u8, s.slice(), "(source_file"));
}

// --- Part 3: Tests for untested functions ---

const InputState = struct {
    data: []const u8,
};

fn readCallback(payload: *anyopaque, byte_offset: u32, _: Point, bytes_read: *u32) callconv(.c) [*]const u8 {
    const s: *InputState = @ptrCast(@alignCast(payload));
    if (byte_offset >= s.data.len) {
        bytes_read.* = 0;
        return s.data.ptr;
    }
    const remaining = s.data.len - byte_offset;
    bytes_read.* = @intCast(remaining);
    return s.data.ptr + byte_offset;
}

fn makeInput(state: *InputState) zts.Input {
    return .{
        .payload = @ptrCast(state),
        .read = &readCallback,
        .encoding = .utf8,
    };
}

test "parser parse with Input struct" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const source = "const x = 1;";
    var state = InputState{ .data = source };
    const input = makeInput(&state);

    const tree = try p.parse(null, input);
    defer tree.deinit();

    try std.testing.expectEqualStrings("source_file", tree.rootNode().getType());
    try std.testing.expect(!tree.rootNode().hasError());
}

test "parser parseWithOptions" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const source = "const x = 1;";
    var state = InputState{ .data = source };
    const input = makeInput(&state);

    const options = zts.ParseOptions{};
    const tree = try p.parseWithOptions(null, input, options);
    defer tree.deinit();

    try std.testing.expectEqualStrings("source_file", tree.rootNode().getType());
}

test "tree printDotGraph" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();

    // Open /dev/null for a valid writable fd
    const devnull = std.posix.openat(std.posix.AT.FDCWD, "/dev/null", .{ .ACCMODE = .WRONLY }, 0) catch return;
    defer _ = std.c.close(devnull);
    tree.printDotGraph(@intCast(devnull));
}

test "node navigation" {
    const source = "const std = @import(\"std\");\nconst x = 1;";
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, source);
    defer tree.deinit();
    const root = tree.rootNode();

    // Should have at least 2 named children (two const declarations)
    try std.testing.expect(root.getNamedChildCount() >= 2);

    const first_decl = root.getNamedChild(0).?;
    const second_decl = root.getNamedChild(1).?;

    // getNextNamedSibling / getPrevNamedSibling round-trip
    const next = first_decl.getNextNamedSibling();
    try std.testing.expect(next != null);
    try std.testing.expect(next.?.eq(second_decl));

    const prev = second_decl.getPrevNamedSibling();
    try std.testing.expect(prev != null);
    try std.testing.expect(prev.?.eq(first_decl));

    // getChildByFieldId: field 0 is invalid, so should return null
    try std.testing.expect(root.getChildByFieldId(0) == null);

    // getFirstChildForByte: byte 0 should find the first child
    const first_by_byte = root.getFirstChildForByte(0);
    try std.testing.expect(first_by_byte != null);

    // getFirstNamedChildForByte: byte in second line
    const second_line_start: u32 = @intCast(std.mem.indexOf(u8, source, "\n").? + 1);
    const named_by_byte = root.getFirstNamedChildForByte(second_line_start);
    try std.testing.expect(named_by_byte != null);

    // getDescendantForPointRange
    const desc = root.getDescendantForPointRange(
        Point{ .row = 0, .column = 0 },
        Point{ .row = 0, .column = 5 },
    );
    try std.testing.expect(desc != null);

    // getNamedDescendantForByteRange
    const named_desc_byte = root.getNamedDescendantForByteRange(0, 5);
    try std.testing.expect(named_desc_byte != null);
    try std.testing.expect(named_desc_byte.?.isNamed());

    // getNamedDescendantForPointRange
    const named_desc_point = root.getNamedDescendantForPointRange(
        Point{ .row = 0, .column = 0 },
        Point{ .row = 0, .column = 5 },
    );
    try std.testing.expect(named_desc_point != null);
    try std.testing.expect(named_desc_point.?.isNamed());
}

test "language getSubtypes" {
    const lang = try loadLanguage(.zig);
    defer lang.deinit();

    const supertypes = lang.getSupertypes();

    if (supertypes.len > 0) {
        const first_supertype = supertypes[0];
        _ = lang.getSubtypes(first_supertype);
    }
}

test "query cursor execWithOptions" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();

    var query = try Query.init(zig, "(variable_declaration) @decl");
    defer query.deinit();

    var cursor = try QueryCursor.init();
    defer cursor.deinit();

    const options = zts.QueryCursorOptions{};
    cursor.execWithOptions(query, tree.rootNode(), &options);

    var match: zts.QueryMatch = undefined;
    try std.testing.expect(cursor.nextMatch(&match));
    try std.testing.expect(match.capture_count > 0);
}

test "setAllocator" {
    // Reset to defaults by passing all nulls
    zts.setAllocator(null, null, null, null);

    // Verify parser still works after allocator reset
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();

    try std.testing.expectEqualStrings("source_file", tree.rootNode().getType());
}

// Libc-backed allocator that counts net live allocations and free() calls.
// Used to verify that buffers tree-sitter allocated (node strings, range
// arrays) are released back through whatever allocator is currently installed
// rather than always through libc free (see zts-gyq.1).
const TrackingAlloc = struct {
    var live: isize = 0;
    var free_calls: usize = 0;

    fn reset() void {
        live = 0;
        free_calls = 0;
    }

    fn malloc(size: usize) callconv(.c) ?*anyopaque {
        const p = std.c.malloc(size);
        if (p != null) live += 1;
        return p;
    }

    fn calloc(count: usize, size: usize) callconv(.c) ?*anyopaque {
        const p = std.c.calloc(count, size);
        if (p != null) live += 1;
        return p;
    }

    fn realloc(ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
        const p = std.c.realloc(ptr, size);
        // A non-null ptr is a resize (net zero live); only a null ptr is a new alloc.
        if (ptr == null and p != null) live += 1;
        return p;
    }

    fn free(ptr: ?*anyopaque) callconv(.c) void {
        if (ptr != null) {
            live -= 1;
            free_calls += 1;
        }
        std.c.free(ptr);
    }
};

test "RangeSlice/NodeString deinit free through the installed allocator" {
    // Install a libc-backed tracking allocator as tree-sitter's allocator,
    // then restore the default (libc) allocator for subsequent tests. The reset
    // defer is registered first so it runs LAST -- after the parser and tree
    // below are freed back through the tracking allocator.
    TrackingAlloc.reset();
    zts.setAllocator(
        TrackingAlloc.malloc,
        TrackingAlloc.calloc,
        TrackingAlloc.realloc,
        TrackingAlloc.free,
    );
    defer zts.setAllocator(null, null, null, null);

    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();
    const root = tree.rootNode();

    // NodeString: ts_node_string allocates via the tracking allocator, so deinit
    // must release it through that same allocator (exactly one tracked free).
    {
        const live_before = TrackingAlloc.live;
        const node_str = root.toString();
        try std.testing.expect(node_str.ptr != null);
        const frees_before = TrackingAlloc.free_calls;
        node_str.deinit();
        try std.testing.expectEqual(frees_before + 1, TrackingAlloc.free_calls);
        try std.testing.expectEqual(live_before, TrackingAlloc.live);
    }

    // RangeSlice: ts_tree_included_ranges allocates via the tracking allocator,
    // so deinit must release it through that same allocator (one tracked free).
    {
        const live_before = TrackingAlloc.live;
        const ranges = tree.getIncludedRanges();
        try std.testing.expect(ranges.ptr != null);
        const frees_before = TrackingAlloc.free_calls;
        ranges.deinit();
        try std.testing.expectEqual(frees_before + 1, TrackingAlloc.free_calls);
        try std.testing.expectEqual(live_before, TrackingAlloc.live);
    }
}

test "C-interop ABI widths match tree-sitter" {
    // TSLogType and TSQueryPredicateStepType are 4-byte C enums. Narrowing them
    // to u8 passes the wrong arg width when C invokes a Zig logger and only reads
    // the predicate-step type correctly on little-endian (see zts-gyq.2).
    try std.testing.expectEqual(@sizeOf(c_uint), @sizeOf(zts.LogType));
    try std.testing.expectEqual(@sizeOf(c_uint), @sizeOf(zts.QueryPredicateStepType));
}

test "parseTimeout aborts a looping parse on a tiny budget" {
    const p = try Parser.init();
    defer p.deinit();
    try p.setLanguage(try loadLanguage(.zig));

    // An input that never signals EOF: parsing can only stop via the progress
    // callback, so a zero budget must abort it. Use token-rich content (not one
    // unbounded identifier) so the parse loop -- where the callback fires -- runs.
    const Infinite = struct {
        var buf = ("const x = 0;\n".*) ** 8;
        fn read(_: *anyopaque, _: u32, _: Point, bytes_read: *u32) callconv(.c) [*]const u8 {
            bytes_read.* = buf.len;
            return &buf;
        }
    };
    const input = zts.Input{
        .payload = &Infinite.buf,
        .read = &Infinite.read,
        .encoding = .utf8,
    };
    try std.testing.expectError(error.ParseTimeout, p.parseTimeout(null, input, 0));
}

test "parseStringTimeout returns a tree within budget" {
    const p = try Parser.init();
    defer p.deinit();
    try p.setLanguage(try loadLanguage(.zig));

    const tree = try p.parseStringTimeout(null, "const x = 1;", std.time.ns_per_s);
    defer tree.deinit();
    try std.testing.expectEqualStrings("source_file", tree.rootNode().getType());
}

test "parseStringTimeout without a language surfaces ParseFail, not ParseTimeout" {
    const p = try Parser.init();
    defer p.deinit();
    // No setLanguage: the null result is a parse failure, not a timeout, even
    // though the timeout machinery is installed.
    try std.testing.expectError(error.ParseFail, p.parseStringTimeout(null, "x", std.time.ns_per_s));
}

test "markdown external scanner parses without a UBSan trap" {
    // The markdown scanner uses the legit deserialize(payload, NULL, 0) idiom,
    // which trips a UBSan false positive. Parsing it must not trap under
    // Debug/ReleaseSafe. Skips when markdown is not built (e.g. --language zig).
    const lang = zts.loadLanguage(.markdown) catch return;
    defer lang.deinit();

    const p = try Parser.init();
    defer p.deinit();
    try p.setLanguage(lang);

    const tree = try p.parseString(null,
        \\# Title
        \\
        \\- a
        \\- b
        \\
    );
    defer tree.deinit();
    try std.testing.expect(!tree.rootNode().isNull());
}

test "parseStringStrict accepts clean input and rejects broken input without leaking" {
    // Route tree-sitter allocations through the tracking allocator so the
    // rejected tree's cleanup is verifiable: after everything is freed, the
    // net live-allocation count must return to zero.
    TrackingAlloc.reset();
    zts.setAllocator(
        TrackingAlloc.malloc,
        TrackingAlloc.calloc,
        TrackingAlloc.realloc,
        TrackingAlloc.free,
    );
    defer zts.setAllocator(null, null, null, null);

    {
        const p = try Parser.init();
        defer p.deinit();
        try p.setLanguage(try loadLanguage(.zig));

        // Clean input parses strictly and yields an error-free tree.
        const ok = try p.parseStringStrict(null, "const x = 1;");
        try std.testing.expect(!ok.rootNode().hasError());
        ok.deinit();

        // Broken input is rejected (the tolerant parseString would accept it).
        try std.testing.expectError(
            error.SyntaxTreeHasErrors,
            p.parseStringStrict(null, "}{ ++ )( const = ;"),
        );
    }
    try std.testing.expectEqual(@as(isize, 0), TrackingAlloc.live);
}

test "matches applies a default match limit but respects an explicit one" {
    const p = try Parser.init();
    defer p.deinit();
    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);
    const tree = try p.parseString(null, "const Foo = 0;");
    defer tree.deinit();
    const node = tree.rootNode();

    var query = try Query.init(zig, "(variable_declaration) @decl");
    defer query.deinit();

    // A fresh cursor starts at the core default (UINT32_MAX); the convenience
    // path replaces it with the conservative default.
    var cursor = try QueryCursor.init();
    defer cursor.deinit();
    try std.testing.expectEqual(std.math.maxInt(u32), cursor.matchLimit());
    var it = cursor.matches(query, node);
    while (it.next()) |_| {}
    try std.testing.expectEqual(QueryCursor.default_match_limit, cursor.matchLimit());

    // An explicit limit set by the caller is left untouched.
    var cursor2 = try QueryCursor.init();
    defer cursor2.deinit();
    cursor2.setMatchLimit(7);
    var it2 = cursor2.matches(query, node);
    while (it2.next()) |_| {}
    try std.testing.expectEqual(@as(u32, 7), cursor2.matchLimit());
}

test "matchesChecked surfaces match-limit overflow" {
    const p = try Parser.init();
    defer p.deinit();
    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);
    const tree = try p.parseString(null, "const Foo = 0;");
    defer tree.deinit();
    const node = tree.rootNode();

    // Happy path: a normal query drains without error.
    {
        var query = try Query.init(zig, "(variable_declaration) @decl");
        defer query.deinit();
        var cursor = try QueryCursor.init();
        defer cursor.deinit();
        var it = cursor.matchesChecked(query, node);
        var count: usize = 0;
        while (try it.next()) |_| count += 1;
        try std.testing.expect(count > 0);
    }

    // Overflow path: 8 wildcard patterns all match the root node at once,
    // exceeding an explicit 1-state limit, so the cursor drops matches; the
    // checked iterator reports it instead of silently truncating.
    {
        const src = "(_) @a\n(_) @b\n(_) @c\n(_) @d\n(_) @e\n(_) @f\n(_) @g\n(_) @h";
        var query = try Query.init(zig, src);
        defer query.deinit();
        var cursor = try QueryCursor.init();
        defer cursor.deinit();
        cursor.setMatchLimit(1);
        var it = cursor.matchesChecked(query, node);
        var saw_overflow = false;
        while (true) {
            const maybe = it.next() catch {
                saw_overflow = true;
                break;
            };
            if (maybe == null) break;
        }
        try std.testing.expect(saw_overflow);
        try std.testing.expect(cursor.didExceedMatchLimit());
    }
}

test "const-correct Tree reads and getTypeZ" {
    const p = try Parser.init();
    defer p.deinit();
    try p.setLanguage(try loadLanguage(.zig));
    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();

    // Read-only methods must be callable through a *const Tree.
    const ct: *const zts.Tree = tree;
    const root = ct.rootNode();
    try std.testing.expect(ct.getLanguage() != null);
    const ranges = ct.getIncludedRanges();
    defer ranges.deinit();
    try std.testing.expect(ranges.slice().len > 0);

    // getTypeZ returns the same text as getType without a length scan.
    try std.testing.expectEqualStrings(root.getType(), std.mem.span(root.getTypeZ()));
    try std.testing.expectEqualStrings(root.getGrammarType(), std.mem.span(root.getGrammarTypeZ()));
}

test "installZigAllocator backs tree-sitter and frees cleanly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // Defers run LIFO: uninstall restores libc + clears the shim first, then the
    // GPA leak check runs -- so the GPA is torn down after the shim stops using
    // it, and both happen even if an assertion below fails.
    defer std.testing.expect(gpa.deinit() == .ok) catch @panic("tree-sitter leaked under Zig allocator");
    defer zts.uninstallZigAllocator();

    zts.installZigAllocator(gpa.allocator());

    {
        const p = try Parser.init();
        defer p.deinit();
        try p.setLanguage(try loadLanguage(.zig));

        const tree = try p.parseString(null, "const x = 1; pub fn f() void { return; }");
        defer tree.deinit();
        try std.testing.expect(!tree.rootNode().hasError());

        // toString routes its free through ts_current_free -> the shim too.
        const s = tree.rootNode().toString();
        defer s.deinit();
        try std.testing.expect(s.slice().len > 0);
    }
    // All tree-sitter objects are freed at block exit; the deferred GPA check
    // then confirms the size-prefixing shim leaked nothing.
}

test "editPoint" {
    // Insert 3 bytes at column 5
    const edit = zts.InputEdit{
        .start_byte = 5,
        .old_end_byte = 5,
        .new_end_byte = 8,
        .start_point = Point{ .row = 0, .column = 5 },
        .old_end_point = Point{ .row = 0, .column = 5 },
        .new_end_point = Point{ .row = 0, .column = 8 },
    };

    // Point at column 10 (after the edit point) should shift to column 13
    var point = Point{ .row = 0, .column = 10 };
    var point_byte: u32 = 10;
    zts.editPoint(&point, &point_byte, &edit);

    try std.testing.expectEqual(@as(u32, 13), point.column);
    try std.testing.expectEqual(@as(u32, 13), point_byte);
}

test "editRange" {
    // Insert 3 bytes at byte 5
    const edit = zts.InputEdit{
        .start_byte = 5,
        .old_end_byte = 5,
        .new_end_byte = 8,
        .start_point = Point{ .row = 0, .column = 5 },
        .old_end_point = Point{ .row = 0, .column = 5 },
        .new_end_point = Point{ .row = 0, .column = 8 },
    };

    // Range starting and ending after the edit point should shift by 3
    var range = Range{
        .start_byte = 10,
        .end_byte = 20,
        .start_point = Point{ .row = 0, .column = 10 },
        .end_point = Point{ .row = 0, .column = 20 },
    };
    zts.editRange(&range, &edit);

    try std.testing.expectEqual(@as(u32, 13), range.start_byte);
    try std.testing.expectEqual(@as(u32, 23), range.end_byte);
}

// --- Part 4: Real usage pattern tests ---

test "parse and verify AST structure" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const source = "const x: u32 = 42;";
    const tree = try p.parseString(null, source);
    defer tree.deinit();

    const root = tree.rootNode();

    // Root is source_file
    try std.testing.expectEqualStrings("source_file", root.getType());
    try std.testing.expect(!root.hasError());

    // First named child is a variable_declaration
    const decl = root.getNamedChild(0).?;
    try std.testing.expectEqualStrings("variable_declaration", decl.getType());

    // Byte range spans full source
    try std.testing.expectEqual(@as(u32, 0), root.getStartByte());
    try std.testing.expectEqual(@as(u32, source.len), root.getEndByte());

    // S-expression contains "variable_declaration"
    const s_expr = root.toString();
    defer s_expr.deinit();
    try std.testing.expect(std.mem.indexOf(u8, s_expr.slice(), "variable_declaration") != null);
}

test "query pattern matching with captures" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const source = "fn foo() void {}\nfn bar() void {}";
    const tree = try p.parseString(null, source);
    defer tree.deinit();

    const query_source = "(function_declaration name: (identifier) @fn_name)";
    var query = try Query.init(zig, query_source);
    defer query.deinit();

    try std.testing.expectEqual(@as(u32, 1), query.patternCount());
    try std.testing.expectEqual(@as(u32, 1), query.captureCount());

    // Verify capture name is "fn_name"
    const capture_name = query.captureNameForId(0);
    try std.testing.expectEqualStrings("fn_name", capture_name.?);

    var cursor = try QueryCursor.init();
    defer cursor.deinit();
    cursor.exec(query, tree.rootNode());

    var match_count: u32 = 0;
    var match: zts.QueryMatch = undefined;
    while (cursor.nextMatch(&match)) {
        match_count += 1;
    }
    try std.testing.expectEqual(@as(u32, 2), match_count);
}

test "incremental parsing" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    // Initial parse
    const old_source = "const x = 1;";
    var tree = try p.parseString(null, old_source);

    // Edit: change "1" to "42" (byte 10..11 -> 10..12)
    const edit = zts.InputEdit{
        .start_byte = 10,
        .old_end_byte = 11,
        .new_end_byte = 12,
        .start_point = Point{ .row = 0, .column = 10 },
        .old_end_point = Point{ .row = 0, .column = 11 },
        .new_end_point = Point{ .row = 0, .column = 12 },
    };
    tree.edit(&edit);

    // Reparse with old tree
    const new_source = "const x = 42;";
    const new_tree = try p.parseString(tree, new_source);
    defer new_tree.deinit();
    tree.deinit();

    const root = new_tree.rootNode();
    try std.testing.expect(!root.hasError());
    try std.testing.expectEqual(@as(u32, 0), root.getStartByte());
    try std.testing.expectEqual(@as(u32, new_source.len), root.getEndByte());
}

test "tree cursor depth-first traversal" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();

    const root = tree.rootNode();
    var cursor = TreeCursor.init(root);
    defer cursor.deinit();

    // Depth-first traversal counting all nodes
    var node_count: u32 = 0;
    var max_depth: u32 = 0;
    var reached_end = false;

    while (!reached_end) {
        node_count += 1;
        const depth = cursor.currentDepth();
        if (depth > max_depth) max_depth = depth;

        // Try to go deeper first
        if (cursor.gotoFirstChild()) {
            continue;
        }
        // Then try next sibling
        if (cursor.gotoNextSibling()) {
            continue;
        }
        // Walk up until we find a sibling or reach root
        var found_sibling = false;
        while (cursor.gotoParent()) {
            if (cursor.gotoNextSibling()) {
                found_sibling = true;
                break;
            }
        }
        if (!found_sibling) reached_end = true;
    }

    // Node count should match descendant count (which includes the root)
    try std.testing.expectEqual(root.getDescendantCount(), node_count);
    try std.testing.expect(max_depth >= 2);
}

test "node children iterator" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;\nconst y = 2;");
    defer tree.deinit();
    const root = tree.rootNode();

    var iter = root.children();
    var count: u32 = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(root.getChildCount(), count);
}

test "node named children iterator" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;\nconst y = 2;");
    defer tree.deinit();
    const root = tree.rootNode();

    var iter = root.namedChildren();
    var count: u32 = 0;
    while (iter.next()) |child| {
        try std.testing.expect(child.isNamed());
        count += 1;
    }
    try std.testing.expectEqual(root.getNamedChildCount(), count);
}

test "query cursor match iterator" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, "fn foo() void {}\nfn bar() void {}");
    defer tree.deinit();

    var query = try Query.init(zig, "(function_declaration name: (identifier) @fn_name)");
    defer query.deinit();

    var cursor = try QueryCursor.init();
    defer cursor.deinit();

    var iter = cursor.matches(query, tree.rootNode());
    var count: u32 = 0;
    while (iter.next()) |match| {
        try std.testing.expect(match.capture_count > 0);
        count += 1;
    }
    try std.testing.expectEqual(@as(u32, 2), count);
}

test "query match captureSlice" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    defer zig.deinit();

    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();

    var query = try Query.init(zig, "(variable_declaration) @decl");
    defer query.deinit();

    var cursor = try QueryCursor.init();
    defer cursor.deinit();
    cursor.exec(query, tree.rootNode());

    var match: zts.QueryMatch = undefined;
    try std.testing.expect(cursor.nextMatch(&match));

    const captures = match.captureSlice();
    try std.testing.expectEqual(@as(usize, 1), captures.len);
    try std.testing.expectEqualStrings("variable_declaration", captures[0].node.getType());
}

test "comptime grammar loading" {
    const zig_lang = zts.loadLanguageComptime(.zig);
    try std.testing.expect(zig_lang.getSymbolCount() > 0);
}

test "RangeSlice deinit" {
    const p = try Parser.init();
    defer p.deinit();

    const zig = try loadLanguage(.zig);
    try p.setLanguage(zig);

    const tree = try p.parseString(null, "const x = 1;");
    defer tree.deinit();

    const ranges = tree.getIncludedRanges();
    defer ranges.deinit();
    try std.testing.expect(ranges.slice().len > 0);
}

const std = @import("std");
const zts = @import("zts");

const Parser = zts.Parser;

pub fn main() !void {
    const stdin_file = std.fs.File.stdin();
    const stdout_file = std.fs.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    const p = try Parser.init();
    defer p.deinit();

    const zig = try zts.loadLanguage(.zig);
    try p.setLanguage(zig);

    try stdout.print("Enter a Zig expression to parse:\n", .{});
    try stdout.flush();

    var input_buf: [256]u8 = undefined;
    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = stdin_file.reader(&stdin_buf);
    const input_text = try stdin_reader.interface.readUntilDelimiter(&input_buf, '\n');
    const text = std.mem.trimRight(u8, input_text, "\r");

    const tree = try p.parseString(null, text);
    defer tree.deinit();
    const root = tree.rootNode();

    const node_str = root.toString();
    defer node_str.deinit();

    try stdout.print("Parsing result:\n{s}\n", .{node_str.slice()});
    try stdout.flush();
}

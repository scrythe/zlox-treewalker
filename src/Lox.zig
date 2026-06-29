const std = @import("std");
const Scanner = @import("Scanner.zig");
const Allocator = std.mem.Allocator;
// const Lox = @This();

pub fn runFile(gpa: Allocator, io: std.Io, filename: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var file_handle = try std.Io.Dir.cwd().openFile(io, filename, .{});
    var buffer2: [1024]u8 = undefined;
    _ = try file_handle.realPath(io, &buffer2);
    std.debug.print("{s}\n", .{buffer2});
    const file = try std.Io.Dir.cwd().readFile(io, filename, &buffer);
    try run(gpa, file);
}

pub fn runPrompt(gpa: Allocator, stdout_writer: *std.Io.Writer, stdin_reader: *std.Io.Reader) !void {
    while (true) {
        try stdout_writer.print("> ", .{});
        try stdout_writer.flush();
        const line = try stdin_reader.takeDelimiter('\n');
        if (line) |line_value| {
            try run(gpa, line_value);
        } else {
            try stdout_writer.print("\n", .{});
            try stdout_writer.flush();
            break;
        }
    }
}

pub fn run(gpa: Allocator, code: []const u8) !void {
    var scanner = try Scanner.init(gpa, code);
    defer scanner.deinit(gpa);
    try scanner.scanTokens(gpa);
    scanner.printTokens();
}

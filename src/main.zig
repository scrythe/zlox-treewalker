const std = @import("std");
const log = std.log.scoped(.zlox);
const lox = @import("lox.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr_writer = &stderr_file_writer.interface;

    const args = init.minimal.args;

    if (args.vector.len > 2) {
        try stderr_writer.print("Usage: jlox [script]\n", .{});
        try stderr_writer.flush();
        std.process.exit(64);
    } else if (args.vector.len == 2) {
        const filename: []const u8 = std.mem.span(args.vector[1]);
        try lox.runFile(gpa, io, filename);
    } else {
        var stdin_buffer: [1024]u8 = undefined;
        var stdin_file_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
        const stdin_reader = &stdin_file_reader.interface;
        try lox.runPrompt(gpa, stdout_writer, stdin_reader);
    }
}

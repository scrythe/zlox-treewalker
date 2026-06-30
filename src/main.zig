const std = @import("std");
const Io = std.Io;
const log = std.log.scoped(.zlox);
const Lox = @import("Lox.zig");
const Reporter = @import("Reporter.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr_writer = &stderr_file_writer.interface;
    const reporter = Reporter.init(stderr_writer);

    const args = init.minimal.args;

    if (args.vector.len > 2) {
        try stderr_writer.print("Usage: jlox [script]\n", .{});
        try stderr_writer.flush();
        std.process.exit(64);
    } else if (args.vector.len == 2) {
        const filename: []const u8 = std.mem.span(args.vector[1]);
        try Lox.runFile(gpa, io, reporter, filename);
    } else {
        var stdin_buffer: [1024]u8 = undefined;
        var stdin_file_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
        const stdin_reader = &stdin_file_reader.interface;
        try Lox.runPrompt(gpa, reporter, stdout_writer, stdin_reader);
    }
}

test {
    std.testing.refAllDecls(@This());
}

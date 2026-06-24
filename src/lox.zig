const std = @import("std");

pub fn runFile(io: std.Io, filename: []const u8) std.Io.Dir.ReadFileError!void {
    var buffer: [1024]u8 = undefined;
    const file = try std.Io.Dir.cwd().readFile(io, filename, &buffer);
    run(file);
}

pub fn runPrompt(stdout_writer: *std.Io.Writer, stdin_reader: *std.Io.Reader) !void {
    while (true) {
        try stdout_writer.print("> ", .{});
        try stdout_writer.flush();
        const line = try stdin_reader.takeDelimiter('\n');
        if (line) |line_value| {
            run(line_value);
        } else {
            try stdout_writer.print("\n", .{});
            try stdout_writer.flush();
            break;
        }
    }
}

pub fn run(code: []const u8) void {
    std.debug.print("{s}\n", .{code});
}

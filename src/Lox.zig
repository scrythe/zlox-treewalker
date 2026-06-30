const std = @import("std");
const Scanner = @import("Scanner.zig");
const Reporter = @import("Reporter.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{CompileError};

pub fn runFile(gpa: Allocator, io: std.Io, reporter: Reporter, filename: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    const file = try std.Io.Dir.cwd().readFile(io, filename, &buffer);
    try run(gpa, reporter, file);
}

pub fn runPrompt(gpa: Allocator, reporter: Reporter, stdout_writer: *std.Io.Writer, stdin_reader: *std.Io.Reader) !void {
    while (true) {
        try stdout_writer.print("> ", .{});
        try stdout_writer.flush();
        const line = try stdin_reader.takeDelimiter('\n');
        if (line) |line_value| {
            try run(gpa, reporter, line_value);
        } else {
            try stdout_writer.print("\n", .{});
            try stdout_writer.flush();
            break;
        }
    }
}

pub fn run(gpa: Allocator, reporter: Reporter, code: []const u8) !void {
    var scanner = try Scanner.init(gpa, code);
    defer scanner.deinit(gpa);
    var hasError = false;
    scanner.scanTokens(gpa, reporter) catch |err| {
        if (err != Error.CompileError) {
            hasError = true;
            return err;
        }
    };
    scanner.printTokens();
}

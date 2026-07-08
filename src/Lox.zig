const std = @import("std");
const Reporter = @import("Reporter.zig");
const Allocator = std.mem.Allocator;
const Scanner = @import("Scanner.zig");
const Parser = @import("Parser.zig");
const AstPrinter = @import("AstPrinter.zig");

pub const Error = error{CompileError};

pub fn runFile(gpa: Allocator, io: std.Io, stdout_writer: *std.Io.Writer, reporter: Reporter, filename: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    const file = try std.Io.Dir.cwd().readFile(io, filename, &buffer);
    try run(gpa, stdout_writer, reporter, file);
}

pub fn runPrompt(gpa: Allocator, stdout_writer: *std.Io.Writer, stdin_reader: *std.Io.Reader, reporter: Reporter) !void {
    while (true) {
        try stdout_writer.print("> ", .{});
        try stdout_writer.flush();
        const line = try stdin_reader.takeDelimiter('\n');
        if (line) |line_value| {
            try run(gpa, stdout_writer, reporter, line_value);
        } else {
            try stdout_writer.print("\n", .{});
            try stdout_writer.flush();
            break;
        }
    }
}

pub fn run(gpa: Allocator, stdout_writer: *std.Io.Writer, reporter: Reporter, code: []const u8) !void {
    var scanner = try Scanner.init(gpa, code);
    defer scanner.deinit(gpa);
    var hasError = false;
    scanner.scanTokens(gpa, reporter) catch |err| {
        if (err != Error.CompileError) {
            hasError = true;
            return err;
        }
    };
    var parser = try Parser.init(gpa, code, scanner.tokens.items);
    defer parser.deinit(gpa);
    if (parser.parse(gpa, reporter)) |exprId| {
        const astPrinter = AstPrinter.init(parser.expressions.items);
        try astPrinter.print(stdout_writer, exprId);
    } else |_| {}
}

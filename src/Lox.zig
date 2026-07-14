const std = @import("std");
const Reporter = @import("Reporter.zig");
const Allocator = std.mem.Allocator;
const Scanner = @import("Scanner.zig");
const Parser = @import("Parser.zig");
// const PrettyPrinter = @import("PrettyPrinter.zig");
const Interpreter = @import("Interpreter.zig");
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Error = error{ CompileError, RuntimeError };

pub fn runFile(gpa: Allocator, io: std.Io, stdout_writer: *std.Io.Writer, reporter: Reporter, filename: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    const file = try std.Io.Dir.cwd().readFile(io, filename, &buffer);
    run(gpa, stdout_writer, reporter, file) catch |err| {
        switch (err) {
            Error.CompileError => std.process.exit(65),
            Error.RuntimeError => std.process.exit(70),
            else => return err,
        }
    };
}

pub fn runPrompt(gpa: Allocator, stdout_writer: *std.Io.Writer, stdin_reader: *std.Io.Reader, reporter: Reporter) !void {
    while (true) {
        try stdout_writer.print("> ", .{});
        try stdout_writer.flush();
        const line = try stdin_reader.takeDelimiter('\n');
        if (line) |line_value| {
            run(gpa, stdout_writer, reporter, line_value) catch |err| {
                switch (err) {
                    Interpreter.Error.RuntimeError, Interpreter.Error.CompileError => continue,
                    else => return err,
                }
            };
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
    var hasScanError = false;
    scanner.scanTokens(gpa, reporter) catch |err| {
        if (err != Error.CompileError) {
            return err;
        }
        hasScanError = true;
    };
    var parser = try Parser.init(gpa, code, scanner.tokens.items);
    defer parser.deinit(gpa);

    // try scanner.printTokens(stdout_writer);

    try parser.parse(gpa, reporter);

    if (hasScanError) {
        return;
    }

    // const prettyPrinter = PrettyPrinter.init(parser.expressions.items);
    // try prettyPrinter.print(stdout_writer, exprId);

    var arena_instance = ArenaAllocator.init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();
    var interpreter = Interpreter.init(gpa, parser.expressions.items, parser.statements.items);
    defer interpreter.deinit();
    try interpreter.interpret(arena, stdout_writer, reporter);
}

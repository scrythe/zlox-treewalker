const std = @import("std");
const Reporter = @import("Reporter.zig");
const Allocator = std.mem.Allocator;
const Scanner = @import("Scanner.zig");
const Parser = @import("Parser.zig");
const Environment = @import("Environment.zig");
const PrettyPrinter = @import("PrettyPrinter.zig");
const Interpreter = @import("Interpreter.zig");
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Error = error{ CompileError, RuntimeError };

global_environment: Environment,
global_arena: ArenaAllocator,
global_arena_allocator: Allocator,
pub const Lox = @This();

pub fn init(gpa: Allocator, lox: *Lox) void {
    lox.global_environment = Environment.init(gpa);
    lox.global_arena = std.heap.ArenaAllocator.init(gpa);
    lox.global_arena_allocator = lox.global_arena.allocator();
}

pub fn deinit(self: *Lox) void {
    self.global_environment.deinit();
    self.global_arena.deinit();
}

pub fn runFile(self: *Lox, gpa: Allocator, io: std.Io, stdout_writer: *std.Io.Writer, reporter: Reporter, filename: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    const file = try std.Io.Dir.cwd().readFile(io, filename, &buffer);
    self.run(gpa, stdout_writer, reporter, file) catch |err| {
        switch (err) {
            Error.CompileError => std.process.exit(65),
            Error.RuntimeError => std.process.exit(70),
            else => return err,
        }
    };
}

pub fn runPrompt(self: *Lox, gpa: Allocator, stdout_writer: *std.Io.Writer, stdin_reader: *std.Io.Reader, reporter: Reporter) !void {
    while (true) {
        try stdout_writer.print("> ", .{});
        try stdout_writer.flush();
        const line = try stdin_reader.takeDelimiter('\n');
        if (line) |line_value| {
            self.run(gpa, stdout_writer, reporter, line_value) catch |err| {
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

pub fn run(self: *Lox, gpa: Allocator, stdout_writer: *std.Io.Writer, reporter: Reporter, code: []const u8) !void {
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

    const prettyPrinter = PrettyPrinter.init(parser.expressions.items, parser.program_statements.items, parser.scoped_statements.items, parser.arguments_list.items);
    try prettyPrinter.printProgramStatements(stdout_writer);

    var arena_instance = ArenaAllocator.init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();
    var interpreter = Interpreter.init(&self.global_environment, parser.expressions.items, parser.program_statements.items, parser.scoped_statements.items);
    // defer interpreter.deinit();
    try interpreter.interpret(self.global_arena_allocator, arena, stdout_writer, reporter);
}

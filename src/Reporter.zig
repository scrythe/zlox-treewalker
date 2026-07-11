const std = @import("std");

const Reporter = @This();
stderr_writer: *std.Io.Writer,

pub fn init(stderr_writer: *std.Io.Writer) Reporter {
    return Reporter{ .stderr_writer = stderr_writer };
}

pub fn report(self: Reporter, line: u32, comptime message: []const u8) std.Io.Writer.Error!void {
    try self.stderr_writer.print("[line {d}] Error: {s}\n", .{ line, message });
    try self.stderr_writer.flush();
}

pub fn reportWithContext(self: Reporter, line: u32, tokenLexeme: []const u8, comptime message: []const u8) std.Io.Writer.Error!void {
    try self.stderr_writer.print("[line {d}] Error at '{s}': {s}\n", .{ line, tokenLexeme, message });
    try self.stderr_writer.flush();
}

pub fn reportWithContextAtEnd(self: Reporter, line: u32, comptime message: []const u8) std.Io.Writer.Error!void {
    try self.stderr_writer.print("[line {d}] Error at end: {s}\n", .{ line, message });
    try self.stderr_writer.flush();
}

pub fn reportRuntimeError(self: Reporter, errorMessage: []const u8, line: u32) std.Io.Writer.Error!void {
    try self.stderr_writer.print("{s}\n[line {d}]\n", .{ errorMessage, line });
    try self.stderr_writer.flush();
}

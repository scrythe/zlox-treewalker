const std = @import("std");

const Reporter = @This();
stderr_writer: *std.Io.Writer,

pub fn init(stderr_writer: *std.Io.Writer) Reporter {
    return Reporter{ .stderr_writer = stderr_writer };
}

pub fn report(self: Reporter, line: u32, errWhere: []const u8, message: []const u8) std.Io.Writer.Error!void {
    try self.stderr_writer.print("[line {d}] Error {s}: {s}\n", .{ line, errWhere, message });
    try self.stderr_writer.flush();
}

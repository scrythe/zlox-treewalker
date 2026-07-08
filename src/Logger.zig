const std = @import("std");

var logBuffer: [1024]u8 = undefined;
var fileWriter: std.Io.File.Writer = undefined;
var writer: *std.Io.Writer = undefined;

pub fn init(io: std.Io) !void {
    // var fileNameBuffer: [16]u8 = undefined;
    // const filename = try std.fmt.bufPrint(&fileNameBuffer, "{d}.log", .{std.os.linux.getpid()});
    const filename = "main.log";
    const file = try std.Io.Dir.cwd().createFile(io, filename, .{ .truncate = false });
    fileWriter = file.writer(io, &logBuffer);
    const fileLength = try file.length(io);
    try fileWriter.seekTo(fileLength);
    writer = &fileWriter.interface;
}

/// must call Logger.init before logging anything
pub fn logFn(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    writer.print("{s}", .{level.asText()}) catch {};
    if (scope != .default) writer.print("({t})", .{scope}) catch {};
    writer.print(": " ++ format ++ "\n", args) catch {};
    writer.flush() catch unreachable;
}

pub const Printer = struct {
    logBuffer: [1024]u8 = undefined,
    file: std.Io.File = undefined,
    fileWriter: std.Io.File.Writer = undefined,
    writer: *std.Io.Writer = undefined,
    pub fn init(comptime scope: @EnumLiteral()) *Printer {
        const io = std.Options.debug_io;
        const printer = std.heap.page_allocator.create(Printer) catch unreachable;
        const filename = std.fmt.comptimePrint("{t}.log", .{scope});
        printer.file = std.Io.Dir.cwd().createFile(io, filename, .{ .truncate = false }) catch unreachable;
        printer.fileWriter = printer.file.writer(io, &printer.logBuffer);
        const fileLength = printer.file.length(io) catch unreachable;
        printer.fileWriter.seekTo(fileLength) catch unreachable;
        printer.writer = &printer.fileWriter.interface;
        return printer;
    }
    pub fn print(self: *Printer, comptime fmt: []const u8, args: anytype) void {
        self.writer.print(fmt, args) catch {};
        self.writer.flush() catch {};
    }
};

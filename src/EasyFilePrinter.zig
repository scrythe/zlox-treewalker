const std = @import("std");

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

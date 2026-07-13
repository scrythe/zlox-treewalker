const std = @import("std");
const LiteralValue = @import("Expressions.zig").LiteralValue;
const Allocator = std.mem.Allocator;
const Reporter = @import("Reporter.zig");
const Interpreter = @import("Interpreter.zig");
// const Lox = @import("Lox.zig");

const ValuesType = std.StringHashMap(LiteralValue);

values: ValuesType,
const Environment = @This();

pub fn init(gpa: Allocator) Environment {
    return Environment{
        .values = ValuesType.init(gpa),
    };
}

pub fn define(self: *Environment, name: []const u8, value: LiteralValue) Allocator.Error!void {
    return self.values.put(name, value);
}

pub fn get(self: *Environment, reporter: Reporter, name: []const u8, line: u32) Interpreter.Error!LiteralValue {
    return self.values.get(name) orelse {
        try reporter.reportRuntimeErrorUndefinedVariable(name, line);
        return Interpreter.Error.RuntimeError;
    };
}

pub fn deinit(self: *Environment) void {
    self.values.deinit();
}

const std = @import("std");
const LiteralValue = @import("Expressions.zig").LiteralValue;
const Allocator = std.mem.Allocator;
const Reporter = @import("Reporter.zig");
const Interpreter = @import("Interpreter.zig");

const ValuesType = std.StringHashMap(LiteralValue);

values: ValuesType,
enclosing: ?*Environment,
const Environment = @This();

pub fn init(gpa: Allocator) Environment {
    return Environment{
        .values = ValuesType.init(gpa),
        .enclosing = null,
    };
}

pub fn deinit(self: *Environment) void {
    self.values.deinit();
}

pub fn define(self: *Environment, arena: Allocator, name: []const u8, value: LiteralValue) Allocator.Error!void {
    // in repl the name (slice of source code) might be cleaned up and not exist therefore
    // could maybe also just let it live
    const env_name = try arena.alloc(u8, name.len);
    @memcpy(env_name, name);
    if (value == .String) {
        const string_value = try arena.alloc(u8, value.String.len);
        @memcpy(string_value, value.String);
        const literal_value = LiteralValue{ .String = string_value };
        return self.values.put(env_name, literal_value);
    } else {
        return self.values.put(env_name, value);
    }
}

pub fn get(self: *Environment, reporter: Reporter, name: []const u8, line: u32) Interpreter.Error!LiteralValue {
    return self.values.get(name) orelse {
        if (self.enclosing) |enclosing| {
            return enclosing.get(reporter, name, line);
        } else {
            try reporter.reportRuntimeErrorUndefinedVariable(name, line);
            return Interpreter.Error.RuntimeError;
        }
    };
}

pub fn get_at(self: *Environment, name: []const u8, distance: u32) Interpreter.Error!LiteralValue {
    var hops: u32 = 0;
    var environment = self;
    while (hops < distance) : (hops += 1) {
        environment = environment.enclosing orelse unreachable;
    }
    return environment.values.get(name) orelse unreachable;
}

pub fn assign(self: *Environment, reporter: Reporter, arena: Allocator, name: []const u8, value: LiteralValue, line: u32) Interpreter.Error!void {
    if (!self.values.contains(name)) {
        if (self.enclosing) |enclosing| {
            return enclosing.assign(reporter, arena, name, value, line);
        } else {
            try reporter.reportRuntimeErrorUndefinedVariable(name, line);
            return Interpreter.Error.RuntimeError;
        }
    } else {
        if (value == .String) {
            const string_value = try arena.alloc(u8, value.String.len);
            @memcpy(string_value, value.String);
            const literal_value = LiteralValue{ .String = string_value };
            self.values.putAssumeCapacity(name, literal_value);
        } else {
            self.values.putAssumeCapacity(name, value);
        }
    }
}

pub fn assign_at(self: *Environment, arena: Allocator, name: []const u8, value: LiteralValue, distance: u32) Interpreter.Error!void {
    var hops: u32 = 0;
    var environment = self;
    while (hops < distance) : (hops += 1) {
        environment = environment.enclosing orelse unreachable;
    }
    if (value == .String) {
        const string_value = try arena.alloc(u8, value.String.len);
        @memcpy(string_value, value.String);
        const literal_value = LiteralValue{ .String = string_value };
        self.values.putAssumeCapacity(name, literal_value);
    } else {
        self.values.putAssumeCapacity(name, value);
    }
}

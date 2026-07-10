const std = @import("std");
const Expressions = @import("Expressions.zig");
const Expression = Expressions.Expression;
const Reporter = @import("Reporter.zig");
const Lox = @import("Lox.zig");

expressions: []const Expression,
const Interpreter = @This();

const Error = Lox.Error || std.Io.Writer.Error;

pub fn init(expresssions: []const Expression) Interpreter {
    return Interpreter{ .expressions = expresssions };
}

pub fn interpret(self: *Interpreter, reporter: Reporter, exprId: Expressions.ExprId) !void {
    const value = self.evaluate(reporter, exprId) catch |err| {
        switch (err) {
            Error.RuntimeError => {
                return;
            },
            else => return err,
        }
    };
    switch (value) {
        .None => std.debug.print("None\n", .{}),
        .Bool => |boolVal| std.debug.print("{}\n", .{boolVal}),
        .Number => |number| std.debug.print("{d}\n", .{number}),
        .String => |string| std.debug.print("\"{s}\"\n", .{string}),
    }
}

pub fn evaluate(self: *Interpreter, reporter: Reporter, exprId: Expressions.ExprId) Error!Expressions.LiteralValue {
    return switch (self.expressions[exprId]) {
        .BinaryExpr => |binaryExpr| {
            const left = try self.evaluate(reporter, binaryExpr.left);
            const right = try self.evaluate(reporter, binaryExpr.right);
            switch (binaryExpr.operator) {
                .BangEqual => {
                    // const leftExpr = self.evaluate(binaryExpr.left);
                    // const rightExpr = self.evaluate(binaryExpr.right);
                },
                .EqualEqual => {},
                .Less => {},
                .LessEqual => {},
                .Greater => {},
                .GreaterEqual => {},
                .Plus => {
                    if (left == .Number and right == .Number) {
                        return Expressions.LiteralValue{ .Number = left.Number + right.Number };
                    } else if (left == .String and right == .String) {
                        return Expressions.LiteralValue{ .String = left.String }; // TODO
                    }
                    try reporter.reportRuntimeError("Operands must be numbers", binaryExpr.line);
                    return Error.RuntimeError;
                },
                .Minus => {
                    if (left != .Number or right != .Number) {
                        try reporter.reportRuntimeError("Operands must be numbers", binaryExpr.line);
                        return Error.RuntimeError;
                    }
                    return Expressions.LiteralValue{ .Number = left.Number - right.Number };
                },
                .Star => {
                    if (left != .Number or right != .Number) {
                        try reporter.reportRuntimeError("Operands must be numbers", binaryExpr.line);
                        return Error.RuntimeError;
                    }
                    return Expressions.LiteralValue{ .Number = left.Number * right.Number };
                },
                .Slash => {
                    if (left != .Number or right != .Number) {
                        try reporter.reportRuntimeError("Operands must be numbers", binaryExpr.line);
                        return Error.RuntimeError;
                    }
                    return Expressions.LiteralValue{ .Number = left.Number / right.Number };
                },

                else => unreachable,
            }
            unreachable;
        },
        .GroupingExpr => |groupingExpr| {
            _ = groupingExpr; // autofix
            unreachable;
        },
        .LiteralExpr => |literalExpr| literalExpr.value,
        .UnaryExpr => |unaryExpr| {
            _ = unaryExpr; // autofix
            unreachable;
        },
    };
}

pub fn checkNumberOperators(left: Expressions.LiteralValue, right: Expressions.LiteralValue) struct { f32, f32 } {
    if (left == .Number and right == .Number) {
        return .{ left.Number, right.Number };
    }
    unreachable;
}

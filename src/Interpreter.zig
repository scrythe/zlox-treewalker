const std = @import("std");
const Expressions = @import("Expressions.zig");
const Expression = Expressions.Expression;

expressions: []const Expression,
const Interpreter = @This();

pub fn init(expresssions: []const Expression) Interpreter {
    return Interpreter{ .expressions = expresssions };
}

pub fn interpret(self: *Interpreter, exprId: Expressions.ExprId) void {
    const value = self.evaluate(exprId);
    switch (value) {
        .None => std.debug.print("None\n", .{}),
        .Bool => |boolVal| std.debug.print("{}\n", .{boolVal}),
        .Number => |number| std.debug.print("{d}\n", .{number}),
        .String => |string| std.debug.print("\"{s}\"\n", .{string}),
    }
}

pub fn evaluate(self: *Interpreter, exprId: Expressions.ExprId) Expressions.LiteralValue {
    return switch (self.expressions[exprId]) {
        .BinaryExpr => |binaryExpr| {
            const left = self.evaluate(binaryExpr.left);
            const right = self.evaluate(binaryExpr.right);
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
                    const res = left.Number + right.Number;
                    return Expressions.LiteralValue{ .Number = res };
                },
                .Minus => {},
                .Star => {},
                .Slash => {},

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

// fn isEql

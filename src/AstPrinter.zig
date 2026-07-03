const std = @import("std");
const Expressions = @import("Expressions.zig");
const Expression = Expressions.Expression;
const ExprId = Expressions.ExprId;

const AstPrinter = @This();
expressions: []const Expression,

pub fn init(expressions: []const Expression) AstPrinter {
    return AstPrinter{ .expressions = expressions };
}

pub fn print(self: *const AstPrinter, stdout_writer: *std.Io.Writer, exprId: ExprId) std.Io.Writer.Error!void {
    try self.printExpression(stdout_writer, exprId);
    try stdout_writer.print("\n", .{});
    try stdout_writer.flush();
}

pub fn printExpression(self: *const AstPrinter, stdout_writer: *std.Io.Writer, exprId: ExprId) std.Io.Writer.Error!void {
    switch (self.expressions[exprId]) {
        .BinaryExpr => |binaryExpr| {
            try stdout_writer.print("(", .{});
            try self.printExpression(stdout_writer, binaryExpr.left);
            try stdout_writer.print(" {} ", .{binaryExpr.operator});
            try self.printExpression(stdout_writer, binaryExpr.right);
            try stdout_writer.print(")", .{});
        },
        .GroupingExpr => |groupingExpr| {
            try stdout_writer.print("(", .{});
            try self.printExpression(stdout_writer, groupingExpr.expression);
            try stdout_writer.print(")", .{});
        },
        .LiteralExpr => |literalExpr| {
            switch (literalExpr.value) {
                .None => std.debug.print("None", .{}),
                .Bool => |boolVal| try stdout_writer.print("{}", .{boolVal}),
                .Number => |number| try stdout_writer.print("{d}", .{number}),
                .String => |string| try stdout_writer.print("{s}", .{string}),
            }
            // self.printExpression(literalExpr.value);
        },
        .UnaryExpr => |unaryExpr| {
            try stdout_writer.print("{}", .{unaryExpr.operator});
            try self.printExpression(stdout_writer, unaryExpr.right);
        },
    }
}

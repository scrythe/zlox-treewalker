const std = @import("std");
const Expressions = @import("Expressions.zig");
const Expression = Expressions.Expression;
const ExprId = Expressions.ExprId;
const Scanner = @import("Scanner.zig");
const TokenType = Scanner.TokenType;

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
            try self.printExpression(stdout_writer, binaryExpr.left);
            try stdout_writer.print(" {s} ", .{convertTokenTypeToString(binaryExpr.operator)});
            try self.printExpression(stdout_writer, binaryExpr.right);
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
        },
        .UnaryExpr => |unaryExpr| {
            try stdout_writer.print("{s}", .{convertTokenTypeToString(unaryExpr.operator)});
            try self.printExpression(stdout_writer, unaryExpr.right);
        },
    }
}

fn convertTokenTypeToString(tokenType: TokenType) []const u8 {
    return switch (tokenType) {
        TokenType.Minus => "-",
        TokenType.Plus => "+",
        TokenType.Slash => "/",
        TokenType.Star => "*",
        TokenType.Bang => "!",
        TokenType.BangEqual => "!=",
        TokenType.Equal => "=",
        TokenType.EqualEqual => "==",
        TokenType.Greater => ">",
        TokenType.GreaterEqual => ">=",
        TokenType.Less => "<",
        TokenType.LessEqual => "<=",
        else => unreachable,
    };
}

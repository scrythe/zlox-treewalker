const std = @import("std");
const Expressions = @import("Expressions.zig");
const Expression = Expressions.Expression;
const ExprId = Expressions.ExprId;
const Scanner = @import("Scanner.zig");
const TokenType = Scanner.TokenType;
const Statements = @import("Statements.zig");
const Statement = Statements.Statement;

const AstPrinter = @This();
expressions: []const Expression,
program_statements: []const Statement,
scoped_statements: []const Statement,

pub fn init(expressions: []const Expression, program_statements: []const Statement, scoped_statements: []const Statement) AstPrinter {
    return AstPrinter{
        .expressions = expressions,
        .program_statements = program_statements,
        .scoped_statements = scoped_statements,
    };
}

// pub fn print(self: *const AstPrinter, stdout_writer: *std.Io.Writer) std.Io.Writer.Error!void {
//     try self.printExpression(stdout_writer, exprId);
//     try stdout_writer.print("\n", .{});
//     try stdout_writer.flush();
// }

pub fn printProgramStatements(self: *const AstPrinter, stdout_writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (self.program_statements) |program_statement| {
        try self.printStatement(stdout_writer, program_statement, 0);
        try stdout_writer.print("\n", .{});
    }
    try stdout_writer.flush();
}

pub fn printStatement(self: *const AstPrinter, stdout_writer: *std.Io.Writer, statement: Statement, block_depth: u32) std.Io.Writer.Error!void {
    switch (statement) {
        .BlockStmt => |blockStmt| {
            for (0..block_depth) |_| {
                try stdout_writer.print(" ", .{});
            }
            try stdout_writer.print("{{\n", .{});
            for (0..block_depth + 1) |_| {
                try stdout_writer.print(" ", .{});
            }
            for (self.scoped_statements[blockStmt.start..blockStmt.endExclusive]) |inside_block_statement| {
                try self.printStatement(stdout_writer, inside_block_statement, block_depth + 1);
            }
            try stdout_writer.print("\n", .{});
            for (0..block_depth) |_| {
                try stdout_writer.print(" ", .{});
            }
            try stdout_writer.print("}}", .{});
        },
        .WhileStmt => |whileStmt| {
            try stdout_writer.print("while (", .{});
            try self.printExpression(stdout_writer, whileStmt.conditionExprId);
            try stdout_writer.print(")\n", .{});
            const whileBodyStmt = self.scoped_statements[whileStmt.bodyStmtId];
            try self.printStatement(stdout_writer, whileBodyStmt, block_depth);
        },
        .ExpressionStmt => |expressionStmt| {
            try self.printExpression(stdout_writer, expressionStmt.exprId);
            try stdout_writer.print(";", .{});
        },
        .IfStmt => |ifStmt| {
            _ = ifStmt; // autofix
        },
        .PrintStmt => |printStmt| {
            _ = printStmt; // autofix
        },
        .VarDeclStmt => |varDeclStmt| {
            try stdout_writer.print("var {s} = ", .{varDeclStmt.varName});
            try self.printExpression(stdout_writer, varDeclStmt.valueExprId);
            try stdout_writer.print(";\n", .{});
            for (0..block_depth) |_| {
                try stdout_writer.print(" ", .{});
            }
        },
    }
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
            try self.printExpression(stdout_writer, groupingExpr.exprId);
            try stdout_writer.print(")", .{});
        },
        .LiteralExpr => |literalExpr| {
            switch (literalExpr.value) {
                .None => try stdout_writer.print("None", .{}),
                .Bool => |boolVal| try stdout_writer.print("{}", .{boolVal}),
                .Number => |number| try stdout_writer.print("{d}", .{number}),
                .String => |string| try stdout_writer.print("\"{s}\"", .{string}),
            }
        },
        .Logical => |logical| {
            _ = logical; // autofix
        },
        .UnaryExpr => |unaryExpr| {
            try stdout_writer.print("{s}", .{convertTokenTypeToString(unaryExpr.operator)});
            try self.printExpression(stdout_writer, unaryExpr.right);
        },
        .VariableExpr => |variableExpr| {
            try stdout_writer.print("{s}", .{variableExpr.varName});
        },
        .AssignmentExpr => |assignmentExpr| {
            try stdout_writer.print("{s} = ", .{assignmentExpr.varName});
            try self.printExpression(stdout_writer, assignmentExpr.valueExprId);
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

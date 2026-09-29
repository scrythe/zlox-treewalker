const std = @import("std");
const Expressions = @import("Expressions.zig");
const Expression = Expressions.Expression;
const ExprId = Expressions.ExprId;
const Scanner = @import("Scanner.zig");
const TokenType = Scanner.TokenType;
const Statements = @import("Statements.zig");
const Statement = Statements.Statement;

const N_TAB_SPACES = "  ";

const AstPrinter = @This();
expressions: []const Expression,
program_statements: []const Statement,
scoped_statements: []const Statement,
arguments_list: []const ExprId,
parameters_list: []const []const u8,

pub fn init(
    expressions: []const Expression,
    program_statements: []const Statement,
    scoped_statements: []const Statement,
    arguments_list: []const ExprId,
    parameters_list: []const []const u8,
) AstPrinter {
    return AstPrinter{
        .expressions = expressions,
        .program_statements = program_statements,
        .scoped_statements = scoped_statements,
        .arguments_list = arguments_list,
        .parameters_list = parameters_list,
    };
}

pub fn printProgramStatements(self: *const AstPrinter, stdout_writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (self.program_statements) |program_statement| {
        try self.printStatement(stdout_writer, program_statement, 0);
        try stdout_writer.print("\n", .{});
    }
    try stdout_writer.flush();
}

// for (self.scoped_statements[blockStmt.start + 1 .. blockStmt.endExclusive]) |inside_block_statement| {
pub fn printStatement(self: *const AstPrinter, stdout_writer: *std.Io.Writer, statement: Statement, block_depth: u32) std.Io.Writer.Error!void {
    switch (statement) {
        .BlockStmt => |blockStmt| {
            try stdout_writer.print("{{", .{});
            var indexOfStmtInBlock = blockStmt.start;
            while (indexOfStmtInBlock < blockStmt.endExclusive) {
                const stmtInBlock = self.scoped_statements[indexOfStmtInBlock];
                try stdout_writer.print("\n", .{});
                for (0..block_depth + 1) |_| {
                    try stdout_writer.print(N_TAB_SPACES, .{});
                }
                try self.printStatement(stdout_writer, stmtInBlock, block_depth + 1);
                while (true) {
                    const check_where_to_continue = self.scoped_statements[indexOfStmtInBlock];
                    switch (check_where_to_continue) {
                        .IfStmt => |ifStmt| {
                            if (ifStmt.elseBranchId) |elseBranchId| {
                                indexOfStmtInBlock = elseBranchId;
                            } else {
                                indexOfStmtInBlock = ifStmt.thenBranchId;
                            }
                        },
                        .WhileStmt => |whileStmt| {
                            indexOfStmtInBlock = whileStmt.bodyStmtId;
                        },
                        .FunDeclStmt => |funStmt| {
                            indexOfStmtInBlock = funStmt.funBlockStmtId;
                        },
                        .BlockStmt => |anotherBlockStmt| {
                            indexOfStmtInBlock = anotherBlockStmt.endExclusive - 1;
                        },
                        else => {
                            break;
                        },
                    }
                }
                indexOfStmtInBlock += 1;
            }
            try stdout_writer.print("\n", .{});
            for (0..block_depth) |_| {
                try stdout_writer.print(N_TAB_SPACES, .{});
            }
            try stdout_writer.print("}}", .{});
        },
        .WhileStmt => |whileStmt| {
            try stdout_writer.print("while (", .{});
            try self.printExpression(stdout_writer, whileStmt.conditionExprId);
            try stdout_writer.print(") ", .{});
            const whileBodyStmt = self.scoped_statements[whileStmt.bodyStmtId];
            try self.printStatement(stdout_writer, whileBodyStmt, block_depth);
        },
        .ExpressionStmt => |expressionStmt| {
            try self.printExpression(stdout_writer, expressionStmt.exprId);
            try stdout_writer.print(";", .{});
        },
        .IfStmt => |ifStmt| {
            try stdout_writer.print("if (", .{});
            try self.printExpression(stdout_writer, ifStmt.conditionExprId);
            try stdout_writer.print(") ", .{});
            const ifThenStmt = self.scoped_statements[ifStmt.thenBranchId];
            try self.printStatement(stdout_writer, ifThenStmt, block_depth);
            if (ifStmt.elseBranchId) |elseBranchId| {
                try stdout_writer.print(" else ", .{});
                const ifElseStmt = self.scoped_statements[elseBranchId];
                try self.printStatement(stdout_writer, ifElseStmt, block_depth);
            }
        },
        .PrintStmt => |printStmt| {
            try stdout_writer.print("print ", .{});
            try self.printExpression(stdout_writer, printStmt.exprId);
            try stdout_writer.print(";", .{});
        },
        .VarDeclStmt => |varDeclStmt| {
            try stdout_writer.print("var {s} = ", .{varDeclStmt.varName});
            try self.printExpression(stdout_writer, varDeclStmt.valueExprId);
            try stdout_writer.print(";", .{});
        },
        .FunDeclStmt => |funDeclStmt| {
            try stdout_writer.print("fun {s}(", .{funDeclStmt.funName});
            if ((funDeclStmt.parameters_end_exclusive - funDeclStmt.parameters_start) > 0) {
                try stdout_writer.print("{s}", .{self.parameters_list[funDeclStmt.parameters_start]});
                for (self.parameters_list[funDeclStmt.parameters_start + 1 .. funDeclStmt.parameters_end_exclusive]) |parameter_name| {
                    try stdout_writer.print(", {s}", .{parameter_name});
                }
            }
            try stdout_writer.print(") ", .{});
            const funBlockStmt = self.scoped_statements[funDeclStmt.funBlockStmtId];
            try self.printStatement(stdout_writer, funBlockStmt, block_depth);
        },
        .ReturnStmt => |returnStmt| {
            try stdout_writer.print("return ", .{});
            try self.printExpression(stdout_writer, returnStmt.exprId);
            try stdout_writer.print(";", .{});
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
                // TODO: maybe print function name
                .Function => try stdout_writer.print("function", .{}),
            }
        },
        .Logical => |logical| {
            try self.printExpression(stdout_writer, logical.left);
            try stdout_writer.print(" {s} ", .{convertTokenTypeToString(logical.operator)});
            try self.printExpression(stdout_writer, logical.right);
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
        .CallExpr => |callExpr| {
            try self.printExpression(stdout_writer, callExpr.calleeExprId);
            try stdout_writer.print("(", .{});

            if (callExpr.argListStart < callExpr.argListExclusiveEnd) {
                try self.printExpression(stdout_writer, self.arguments_list[callExpr.argListStart]);

                for (self.arguments_list[callExpr.argListStart + 1 .. callExpr.argListExclusiveEnd]) |argExprId| {
                    try stdout_writer.print(", ", .{});
                    try self.printExpression(stdout_writer, @intCast(argExprId));
                }
            }
            try stdout_writer.print(")", .{});
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
        TokenType.And => "and",
        else => unreachable,
    };
}

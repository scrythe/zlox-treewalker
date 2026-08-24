const std = @import("std");
const Expressions = @import("Expressions.zig");
const Expression = Expressions.Expression;
const Statements = @import("Statements.zig");
const Statement = Statements.Statement;
const Reporter = @import("Reporter.zig");
const Lox = @import("Lox.zig");
const Environment = @import("Environment.zig");
const Allocator = std.mem.Allocator;

const LiteralValue = Expressions.LiteralValue;

expressions: []const Expression,
program_statements: []const Statement,
scoped_statements: []const Statement,
environment: *Environment,
const Interpreter = @This();

pub const Error = Lox.Error || std.Io.Writer.Error || Allocator.Error;

pub fn init(global_environment: *Environment, expresssions: []const Expression, program_statements: []const Statement, scoped_statements: []const Statement) Interpreter {
    return Interpreter{
        .expressions = expresssions,
        .program_statements = program_statements,
        .scoped_statements = scoped_statements,
        .environment = global_environment,
    };
}

// pub fn deinit(self: *Interpreter) void {
//     self.environment.deinit();
// }

pub fn interpret(self: *Interpreter, global_arena: Allocator, arena: Allocator, interpreterPrinter: *std.Io.Writer, reporter: Reporter) Error!void {
    for (self.program_statements) |statement| {
        try self.execute(global_arena, arena, interpreterPrinter, reporter, statement);
    }
}

pub fn execute(self: *Interpreter, global_arena: Allocator, arena: Allocator, interpreterPrinter: *std.Io.Writer, reporter: Reporter, statement: Statement) Error!void {
    switch (statement) {
        .IfStmt => |ifStmt| {
            const condition = try self.evaluate(arena, reporter, ifStmt.conditionExprId);
            if (isTruthy(condition)) {
                const thenBranch = self.scoped_statements[ifStmt.thenBranchId];
                try self.execute(global_arena, arena, interpreterPrinter, reporter, thenBranch);
            } else {
                if (ifStmt.elseBranchId) |elseBranchId| {
                    const elseBranch = self.scoped_statements[elseBranchId];
                    try self.execute(global_arena, arena, interpreterPrinter, reporter, elseBranch);
                }
            }
        },
        .PrintStmt => |printStmt| {
            const value = try self.evaluate(arena, reporter, printStmt.exprId);

            switch (value) {
                .None => try interpreterPrinter.print("None\n", .{}),
                .Bool => |boolVal| try interpreterPrinter.print("{}\n", .{boolVal}),
                .Number => |number| try interpreterPrinter.print("{d}\n", .{number}),
                .String => |string| try interpreterPrinter.print("\"{s}\"\n", .{string}),
            }
            try interpreterPrinter.flush();
        },
        .WhileStmt => |whileStmt| {
            var condition = true;
            while (condition) {
                const bodyStmt = self.scoped_statements[whileStmt.bodyStmtId];
                try self.execute(global_arena, arena, interpreterPrinter, reporter, bodyStmt);
                const conditionLiteral = try self.evaluate(arena, reporter, whileStmt.conditionExprId);
                condition = isTruthy(conditionLiteral);
            }
        },
        .ExpressionStmt => |expressionStmt| {
            _ = try self.evaluate(arena, reporter, expressionStmt.exprId);
        },
        .VarDeclStmt => |varDeclStmt| {
            const value = try self.evaluate(arena, reporter, varDeclStmt.valueExprId);
            try self.environment.define(global_arena, varDeclStmt.varName, value);
        },
        .BlockStmt => |blockStmt| {
            // const stmtsInBlock = self.scoped_statements[blockStmt.start..blockStmt.endExclusive];
            var newEnvironment = Environment.init(arena);
            const oldEnvironment = self.environment;
            newEnvironment.enclosing = oldEnvironment;
            self.environment = &newEnvironment;
            var indexOfStmtInBlock = blockStmt.start;
            while (indexOfStmtInBlock < blockStmt.endExclusive) : (indexOfStmtInBlock += 1) {
                const stmtInBlock = self.scoped_statements[indexOfStmtInBlock];
                try self.execute(global_arena, arena, interpreterPrinter, reporter, stmtInBlock);
                if (stmtInBlock == .BlockStmt) {
                    indexOfStmtInBlock = stmtInBlock.BlockStmt.endExclusive - 1;
                }
            }
            self.environment = oldEnvironment;
        },
    }
}

pub fn evaluate(self: *Interpreter, arena: Allocator, reporter: Reporter, exprId: Expressions.ExprId) Error!LiteralValue {
    return switch (self.expressions[exprId]) {
        .BinaryExpr => |binaryExpr| {
            const left = try self.evaluate(arena, reporter, binaryExpr.left);
            const right = try self.evaluate(arena, reporter, binaryExpr.right);
            switch (binaryExpr.operator) {
                .BangEqual => return LiteralValue{ .Bool = !equals(left, right) },
                .EqualEqual => return LiteralValue{ .Bool = equals(left, right) },
                .Less => {
                    try checkNumberOperators(reporter, left, right, binaryExpr.line);
                    return LiteralValue{ .Bool = left.Number < right.Number };
                },
                .LessEqual => {
                    try checkNumberOperators(reporter, left, right, binaryExpr.line);
                    return LiteralValue{ .Bool = left.Number <= right.Number };
                },
                .Greater => {
                    try checkNumberOperators(reporter, left, right, binaryExpr.line);
                    return LiteralValue{ .Bool = left.Number > right.Number };
                },
                .GreaterEqual => {
                    try checkNumberOperators(reporter, left, right, binaryExpr.line);
                    return LiteralValue{ .Bool = left.Number >= right.Number };
                },
                .Plus => {
                    if (left == .Number and right == .Number) {
                        return LiteralValue{ .Number = left.Number + right.Number };
                    } else if (left == .String and right == .String) {
                        const res = try std.mem.concat(arena, u8, &.{ left.String, right.String });
                        return LiteralValue{ .String = res };
                    }
                    try reporter.reportRuntimeError("Operands must be two numbers or two strings", binaryExpr.line);
                    return Error.RuntimeError;
                },
                .Minus => {
                    try checkNumberOperators(reporter, left, right, binaryExpr.line);
                    return LiteralValue{ .Number = left.Number - right.Number };
                },
                .Star => {
                    try checkNumberOperators(reporter, left, right, binaryExpr.line);
                    return LiteralValue{ .Number = left.Number * right.Number };
                },
                .Slash => {
                    try checkNumberOperators(reporter, left, right, binaryExpr.line);
                    return LiteralValue{ .Number = left.Number / right.Number };
                },
                else => unreachable,
            }
        },
        .GroupingExpr => |groupingExpr| {
            return self.evaluate(arena, reporter, groupingExpr.exprId);
        },
        .LiteralExpr => |literalExpr| literalExpr.value,
        .Logical => |logical| {
            const left = try self.evaluate(arena, reporter, logical.left);
            if (!isTruthy(left) and logical.operator == .And) {
                return LiteralValue{ .Bool = false };
            } else if (isTruthy(left) and logical.operator == .Or) {
                return LiteralValue{ .Bool = true };
            } else {
                return try self.evaluate(arena, reporter, logical.right);
            }
        },
        .UnaryExpr => |unaryExpr| {
            const right = try self.evaluate(arena, reporter, unaryExpr.right);
            switch (unaryExpr.operator) {
                .Bang => return LiteralValue{ .Bool = !isTruthy(right) },
                .Minus => {
                    if (right != .Number) {
                        try reporter.reportRuntimeError("Operand must be a number", unaryExpr.line);
                        return Error.RuntimeError;
                    }
                    return LiteralValue{ .Number = -right.Number };
                },
                else => unreachable,
            }
        },
        .VariableExpr => |variableExpr| try self.environment.get(reporter, variableExpr.varName, variableExpr.line),
        .AssignmentExpr => |assignmentExpr| {
            const value = try self.evaluate(arena, reporter, assignmentExpr.valueExprId);
            try self.environment.assign(reporter, arena, assignmentExpr.varName, value, assignmentExpr.line);
            return value;
        },
        .CallExpr => |callExpr| {
            _ = callExpr; // autofix
            unreachable; // TODO:
        },
    };
}

fn checkNumberOperators(reporter: Reporter, left: LiteralValue, right: LiteralValue, line: u32) Error!void {
    if (left == .Number and right == .Number) return;
    try reporter.reportRuntimeError("Operands must be numbers", line);
    return Error.RuntimeError;
}

const LiteralValueTagType = @typeInfo(LiteralValue).@"union".tag_type.?;
fn equals(left: LiteralValue, right: LiteralValue) bool {
    if (@as(LiteralValueTagType, left) != @as(LiteralValueTagType, right)) return false;
    switch (left) {
        .Number => return left.Number == right.Number,
        .String => return std.mem.eql(u8, left.String, right.String),
        .Bool => return left.Bool == right.Bool,
        .None => return left.None == right.None,
    }
    unreachable;
}

fn isTruthy(literalValue: LiteralValue) bool {
    return switch (literalValue) {
        .None => false,
        .Bool => |val| val,
        else => true,
    };
}

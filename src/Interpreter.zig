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
statements: []const Statement,
environment: Environment,
const Interpreter = @This();

pub const Error = Lox.Error || std.Io.Writer.Error || Allocator.Error;

pub fn init(gpa: Allocator, expresssions: []const Expression, statements: []const Statement) Interpreter {
    return Interpreter{
        .expressions = expresssions,
        .statements = statements,
        .environment = Environment.init(gpa),
    };
}

pub fn deinit(self: *Interpreter) void {
    self.environment.deinit();
}

pub fn interpret(self: *Interpreter, arena: Allocator, interpreterPrinter: *std.Io.Writer, reporter: Reporter) Error!void {
    for (self.statements) |statement| {
        try self.execute(arena, interpreterPrinter, reporter, statement);
    }
}

pub fn execute(self: *Interpreter, arena: Allocator, interpreterPrinter: *std.Io.Writer, reporter: Reporter, statement: Statement) Error!void {
    switch (statement) {
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
        .ExpressionStmt => |expressionStmt| {
            _ = try self.evaluate(arena, reporter, expressionStmt.exprId);
        },
        .VarDeclStmt => |varDeclStmt| {
            const value = try self.evaluate(arena, reporter, varDeclStmt.valueExprId);
            try self.environment.define(varDeclStmt.varName, value);
        },
        .BlockStmt => |blockStmt| {
            _ = blockStmt; // autofix
            unreachable; // TODO:
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
            try self.environment.assign(reporter, assignmentExpr.varName, value, assignmentExpr.line);
            return value;
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

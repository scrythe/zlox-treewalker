const std = @import("std");
const Expressions = @import("Expressions.zig");
const Expression = Expressions.Expression;
const Statements = @import("Statements.zig");
const Statement = Statements.Statement;
const Reporter = @import("Reporter.zig");
const Lox = @import("Lox.zig");
const Environment = @import("Environment.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Resolver = @import("Resolver.zig");

const LiteralValue = Expressions.LiteralValue;

expressions: []const Expression,
program_statements: []const Statement,
scoped_statements: []const Statement,
arguments_list: []const Expressions.ExprId,
parameters_list: []const []const u8,
environment: *Environment,
global_environment: *Environment,
var_expr_distance_map: Resolver.VarExprDistanceMap,

const Interpreter = @This();

pub const Error = Lox.Error || std.Io.Writer.Error || Allocator.Error;

pub fn init(
    global_environment: *Environment,
    expresssions: []const Expression,
    program_statements: []const Statement,
    scoped_statements: []const Statement,
    arguments_list: []const Expressions.ExprId,
    parameters_list: []const []const u8,
    var_expr_depth_map: Resolver.VarExprDistanceMap,
) !Interpreter {
    return Interpreter{
        .expressions = expresssions,
        .program_statements = program_statements,
        .scoped_statements = scoped_statements,
        .arguments_list = arguments_list,
        .parameters_list = parameters_list,
        .environment = global_environment,
        .global_environment = global_environment,
        .var_expr_distance_map = var_expr_depth_map,
    };
}

pub fn interpret(self: *Interpreter, io: Io, global_arena: Allocator, arena: Allocator, interpreterPrinter: *std.Io.Writer, reporter: Reporter) Error!void {
    for (self.program_statements) |statement| {
        _ = try self.execute(io, global_arena, arena, interpreterPrinter, reporter, statement);
    }
}

pub fn execute(self: *Interpreter, io: Io, global_arena: Allocator, arena: Allocator, interpreterPrinter: *std.Io.Writer, reporter: Reporter, statement: Statement) Error!?LiteralValue {
    switch (statement) {
        .IfStmt => |ifStmt| {
            const condition = try self.evaluate(io, arena, interpreterPrinter, reporter, ifStmt.conditionExprId);
            if (isTruthy(condition)) {
                const thenBranch = self.scoped_statements[ifStmt.thenBranchId];
                const optReturnValue = try self.execute(io, global_arena, arena, interpreterPrinter, reporter, thenBranch);
                if (optReturnValue) |returnValue| return returnValue;
            } else {
                if (ifStmt.elseBranchId) |elseBranchId| {
                    const elseBranch = self.scoped_statements[elseBranchId];
                    const optReturnValue = try self.execute(io, global_arena, arena, interpreterPrinter, reporter, elseBranch);
                    if (optReturnValue) |returnValue| return returnValue;
                }
            }
        },
        .PrintStmt => |printStmt| {
            const value = try self.evaluate(io, arena, interpreterPrinter, reporter, printStmt.exprId);

            switch (value) {
                .None => try interpreterPrinter.print("None\n", .{}),
                .Bool => |boolVal| try interpreterPrinter.print("{}\n", .{boolVal}),
                .Number => |number| try interpreterPrinter.print("{d}\n", .{number}),
                .String => |string| try interpreterPrinter.print("\"{s}\"\n", .{string}),
                .Function => |function| try interpreterPrinter.print("{s}\n", .{function.string}),
            }
            try interpreterPrinter.flush();
        },
        .WhileStmt => |whileStmt| {
            var condition = true;
            while (condition) {
                const bodyStmt = self.scoped_statements[whileStmt.bodyStmtId];
                const optReturnValue = try self.execute(io, global_arena, arena, interpreterPrinter, reporter, bodyStmt);
                if (optReturnValue) |returnValue| return returnValue;
                const conditionLiteral = try self.evaluate(io, arena, interpreterPrinter, reporter, whileStmt.conditionExprId);
                condition = isTruthy(conditionLiteral);
            }
        },
        .ExpressionStmt => |expressionStmt| {
            _ = try self.evaluate(io, arena, interpreterPrinter, reporter, expressionStmt.exprId);
        },
        .VarDeclStmt => |varDeclStmt| {
            const value = try self.evaluate(io, arena, interpreterPrinter, reporter, varDeclStmt.valueExprId);
            try self.environment.define(global_arena, varDeclStmt.varName, value);
        },
        .FunDeclStmt => |funDeclStmt| {
            // TODO:
            const func = LiteralValue{ .Function = .{
                .arity = funDeclStmt.parameters_end_exclusive - funDeclStmt.parameters_start,
                .parameters_start = funDeclStmt.parameters_start,
                .parameters_end_exclusive = funDeclStmt.parameters_end_exclusive,
                .callable = .{ .UserFunction = .{
                    .body = funDeclStmt.funBlockStmtId,
                    .environment = self.environment,
                } },
                .string = try std.fmt.allocPrint(arena, "<fn {s}>", .{funDeclStmt.funName}),
            } };
            try self.environment.define(arena, funDeclStmt.funName, func);
            // unreachable;
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
                const optReturnValue = try self.execute(io, global_arena, arena, interpreterPrinter, reporter, stmtInBlock);
                if (optReturnValue) |returnValue| return returnValue;

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
            }
            self.environment = oldEnvironment;
        },
        .ReturnStmt => |returnStmt| {
            return try self.evaluate(io, arena, interpreterPrinter, reporter, returnStmt.exprId);
        },
    }
    return null;
}

pub fn evaluate(self: *Interpreter, io: Io, arena: Allocator, interpreterPrinter: *std.Io.Writer, reporter: Reporter, exprId: Expressions.ExprId) Error!LiteralValue {
    return switch (self.expressions[exprId]) {
        .BinaryExpr => |binaryExpr| {
            const left = try self.evaluate(io, arena, interpreterPrinter, reporter, binaryExpr.left);
            const right = try self.evaluate(io, arena, interpreterPrinter, reporter, binaryExpr.right);
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
            return self.evaluate(io, arena, interpreterPrinter, reporter, groupingExpr.exprId);
        },
        .LiteralExpr => |literalExpr| literalExpr.value,
        .Logical => |logical| {
            const left = try self.evaluate(io, arena, interpreterPrinter, reporter, logical.left);
            if (!isTruthy(left) and logical.operator == .And) {
                return LiteralValue{ .Bool = false };
            } else if (isTruthy(left) and logical.operator == .Or) {
                return LiteralValue{ .Bool = true };
            } else {
                const right = try self.evaluate(io, arena, interpreterPrinter, reporter, logical.right);
                return LiteralValue{ .Bool = isTruthy(right) };
            }
        },
        .UnaryExpr => |unaryExpr| {
            const right = try self.evaluate(io, arena, interpreterPrinter, reporter, unaryExpr.right);
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
        .VariableExpr => |variableExpr| {
            const optDistance = self.var_expr_distance_map.get(exprId);
            if (optDistance) |distance| {
                return try self.environment.get_at(variableExpr.varName, distance);
            } else {
                return try self.global_environment.get(reporter, variableExpr.varName, variableExpr.line);
            }
        },

        .AssignmentExpr => |assignmentExpr| {
            const value = try self.evaluate(io, arena, interpreterPrinter, reporter, assignmentExpr.valueExprId);

            const optDistance = self.var_expr_distance_map.get(exprId);
            if (optDistance) |distance| {
                try self.environment.assign_at(arena, assignmentExpr.varName, value, distance);
            } else {
                try self.global_environment.assign(reporter, arena, assignmentExpr.varName, value, assignmentExpr.line);
            }

            return value;
        },
        .CallExpr => |callExpr| {
            var returnValue: LiteralValue = LiteralValue.None;
            var callee = try self.evaluate(io, arena, interpreterPrinter, reporter, callExpr.calleeExprId);
            if (callee != .Function) {
                try reporter.reportRuntimeError("Can only call functions and classes", callExpr.line);
                return Error.RuntimeError;
            } else {
                const args_len = callExpr.argListExclusiveEnd - callExpr.argListStart;
                if (args_len != callee.Function.arity) {
                    try reporter.reportRuntimeErrorUnequalFunctionParametersAndArity(callee.Function.arity, args_len, callExpr.line);
                    return Error.RuntimeError;
                } else {
                    const eval_args = try arena.alloc(LiteralValue, args_len);
                    for (self.arguments_list[callExpr.argListStart..callExpr.argListExclusiveEnd], 0..) |callExprId, i| {
                        const arg_literal_value = try self.evaluate(io, arena, interpreterPrinter, reporter, callExprId);
                        eval_args[i] = arg_literal_value;
                    }
                    const calleeObj = &callee.Function;
                    switch (callee.Function.callable) {
                        .UserFunction => |userFunction| {
                            const parent_environment = userFunction.environment;
                            const prev_environment = self.environment;
                            // var iterator = userFunction.environment.values.iterator();
                            //
                            // var temp_names: [10][]const u8 = undefined;
                            // var temp_values: [10]LiteralValue = undefined;
                            // var entry_i: u32 = 0;
                            // while (iterator.next()) |entry| : (entry_i += 1) {
                            //     temp_names[entry_i] = entry.key_ptr.*;
                            //     temp_values[entry_i] = entry.value_ptr.*;
                            // }

                            self.environment = try arena.create(Environment);
                            self.environment.* = Environment.init(arena);
                            self.environment.enclosing = parent_environment;

                            const parameters = self.parameters_list[calleeObj.parameters_start..calleeObj.parameters_end_exclusive];

                            for (eval_args, 0..) |arg, i| {
                                const parameter = parameters[i];
                                try self.environment.define(arena, parameter, arg);
                            }
                            const functionBody = self.scoped_statements[userFunction.body].BlockStmt;
                            var indexOfStmtInBlock = functionBody.start;
                            while (indexOfStmtInBlock < functionBody.endExclusive) : (indexOfStmtInBlock += 1) {
                                const stmtInBlock = self.scoped_statements[indexOfStmtInBlock];
                                // TODO: global_arena instead of arena?
                                const optReturnValue = try self.execute(io, arena, arena, interpreterPrinter, reporter, stmtInBlock);
                                if (optReturnValue) |somereturnValue| {
                                    returnValue = somereturnValue;
                                    break;
                                }

                                // could maybe call execute on block but potentially issue regarding return statement
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
                            }

                            self.environment = prev_environment;

                            return returnValue;
                        },
                        .NativeFunction => |nativeFunction| {
                            return nativeFunction(calleeObj, io, eval_args);
                        },
                    }
                }
            }
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
        // TODO:
        .Function => unreachable,
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

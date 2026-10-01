const std = @import("std");
const Expressions = @import("Expressions.zig");
const Expression = Expressions.Expression;
const ExprId = Expressions.ExprId;
const Statements = @import("Statements.zig");
const Statement = Statements.Statement;
const Allocator = std.mem.Allocator;
const Reporter = @import("Reporter.zig");
const Lox = @import("Lox.zig");

const ScopeType = std.StringHashMap(bool);

const Resolver = @This();
expressions: []const Expression,
program_statements: []const Statement,
scoped_statements: []const Statement,
arguments_list: []const ExprId,
parameters_list: []const []const u8,
scopes: std.ArrayList(ScopeType),

pub fn init(
    expressions: []const Expression,
    program_statements: []const Statement,
    scoped_statements: []const Statement,
    arguments_list: []const ExprId,
    parameters_list: []const []const u8,
) Resolver {
    return Resolver{
        .expressions = expressions,
        .program_statements = program_statements,
        .scoped_statements = scoped_statements,
        .arguments_list = arguments_list,
        .parameters_list = parameters_list,
        .scopes = .empty,
    };
}

pub fn resolve_program_statements(self: *Resolver, arena: Allocator, reporter: Reporter) !void {
    for (self.program_statements) |program_statement| {
        try self.resolve_statement(arena, reporter, program_statement);
    }
}

pub fn resolve_statement(self: *Resolver, arena: Allocator, reporter: Reporter, statement: Statement) !void {
    switch (statement) {
        .BlockStmt => |blockStmt| {
            const scope = ScopeType.init(arena);
            try self.scopes.append(arena, scope);

            var indexOfStmtInBlock = blockStmt.start;
            while (indexOfStmtInBlock < blockStmt.endExclusive) {
                const stmtInBlock = self.scoped_statements[indexOfStmtInBlock];
                try self.resolve_statement(arena, reporter, stmtInBlock);

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

            self.scopes.items.len -= 1;
        },
        .VarDeclStmt => |varDeclStmt| {
            if (self.scopes.items.len < 1) return;
            const scope = &self.scopes.items[self.scopes.items.len - 1];
            try scope.put(varDeclStmt.varName, false);
            try self.resolve_expression(reporter, varDeclStmt.valueExprId);
            try scope.put(varDeclStmt.varName, true);
        },
        .FunDeclStmt => |funDeclStmt| {
            if (self.scopes.items.len < 1) return;
            const outer_function_scope = &self.scopes.items[self.scopes.items.len - 1];
            try outer_function_scope.put(funDeclStmt.funName, false);

            const inner_function_scope = try self.scopes.addOne(arena);
            inner_function_scope.* = ScopeType.init(arena);

            for (self.parameters_list[funDeclStmt.parameters_start..funDeclStmt.parameters_end_exclusive]) |parameter_name| {
                // try inner_function_scope.put(funDeclStmt.varName, false);
                try inner_function_scope.put(parameter_name, true);
            }
            const fun_body_stmt = self.scoped_statements[funDeclStmt.funBlockStmtId];
            try self.resolve_statement(arena, reporter, fun_body_stmt);

            self.scopes.items.len -= 1;

            try outer_function_scope.put(funDeclStmt.funName, true);
        },
        .ExpressionStmt => |exprStmt| {
            try self.resolve_expression(reporter, exprStmt.exprId);
        },
        .IfStmt => |ifStmt| {
            try self.resolve_expression(reporter, ifStmt.conditionExprId);
            try self.resolve_statement(arena, reporter, self.scoped_statements[ifStmt.thenBranchId]);
            if (ifStmt.elseBranchId) |elseBranchId| {
                try self.resolve_statement(arena, reporter, self.scoped_statements[elseBranchId]);
            }
        },
        .PrintStmt => |printStmt| {
            try self.resolve_expression(reporter, printStmt.exprId);
        },
        .ReturnStmt => |returnStmt| {
            try self.resolve_expression(reporter, returnStmt.exprId);
        },
        .WhileStmt => |whileStmt| {
            try self.resolve_expression(reporter, whileStmt.conditionExprId);
            try self.resolve_statement(arena, reporter, self.scoped_statements[whileStmt.bodyStmtId]);
        },
    }
}

fn resolve_expression(self: Resolver, reporter: Reporter, exprId: ExprId) !void {
    switch (self.expressions[exprId]) {
        .VariableExpr => |varExpr| {
            if (self.scopes.items.len < 1) return;

            const is_declared_not_defined = self.scopes.items[self.scopes.items.len - 1].get(varExpr.varName) orelse true;
            if (!is_declared_not_defined) {
                try reporter.reportWithContext(varExpr.line, varExpr.varName, "Can't read local variable in its own initializer.");
                return Lox.Error.CompileError;
            }
            self.resolve_local_var(varExpr.varName);
        },
        .AssignmentExpr => |assignExpr| {
            try self.resolve_expression(reporter, assignExpr.valueExprId);
            self.resolve_local_var(assignExpr.varName);
        },
        .BinaryExpr => |binaryExpr| {
            try self.resolve_expression(reporter, binaryExpr.left);
            try self.resolve_expression(reporter, binaryExpr.right);
        },
        .CallExpr => |callExpr| {
            try self.resolve_expression(reporter, callExpr.calleeExprId);

            for (self.arguments_list[callExpr.argListStart..callExpr.argListExclusiveEnd]) |argument| {
                try self.resolve_expression(reporter, argument);
            }
        },
        .GroupingExpr => |groupingExpr| {
            try self.resolve_expression(reporter, groupingExpr.exprId);
        },
        .LiteralExpr => {},
        .Logical => |logical| {
            try self.resolve_expression(reporter, logical.left);
            try self.resolve_expression(reporter, logical.right);
        },
        .UnaryExpr => |unaryExpr| {
            try self.resolve_expression(reporter, unaryExpr.right);
        },
    }
}

fn resolve_local_var(self: Resolver, varName: []const u8) void {
    var i: isize = @bitCast(self.scopes.items.len - 1);
    while (i >= 0) : (i -= 1) {
        const scope = self.scopes.items[@bitCast(i)];
        if (scope.contains(varName)) {
            // TODO: interpreter resolve
            std.debug.print("{s} at depth {d}\n", .{ varName, i }); // NOTE: only temp
            return;
        }
    }
}

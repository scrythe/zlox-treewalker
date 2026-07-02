const std = @import("std");
const Scanner = @import("Scanner.zig");
const Expressions = @import("Expressions.zig");
const Allocator = std.mem.Allocator;

const Parser = @This();
code: []const u8,
tokens: []const Scanner.Token,
current: u32,
expressions: std.ArrayList(Expressions.Expression),

pub fn init(gpa: Allocator, code: []const u8, tokens: []const Scanner.Token) !Parser {
    const expressions = try std.ArrayList(Expressions.Expression).initCapacity(gpa, tokens.len);
    return Parser{ .code = code, .tokens = tokens, .current = 0, .expressions = expressions };
}

pub fn deinit(self: *Parser, gpa: Allocator) void {
    self.expressions.deinit(gpa);
}

pub fn parse(self: *Parser, gpa: Allocator) !void {
    // const token = self.tokens[self.current];
    const expression = try self.parseExpression(gpa);
    std.debug.print("expression: {}\n", .{expression});
    // std.debug.print("{}\n", .{self.tokens[self.current]});
    for (self.expressions.items) |expr| {
        std.debug.print("expression: {}\n", .{expr});
    }
}

/// expression -> equality
fn parseExpression(self: *Parser, gpa: Allocator) !Expressions.ExprionId {
    return self.parseEquality(gpa);
}

/// equality -> comparison ( ( "!=" | "==" ) comparison )*
fn parseEquality(self: *Parser, gpa: Allocator) !Expressions.ExprionId {
    var comparisonExprId = try self.parseComparison(gpa);
    var tokenType = self.tokens[self.current].tokenType;
    while (tokenType == Scanner.TokenType.BangEqual or tokenType == Scanner.TokenType.EqualEqual) {
        self.current += 1;
        const rightComparisonExprId = try self.parseComparison(gpa);
        const equalityExpr = Expressions.Expression{ .BinaryExpr = Expressions.BinaryExpr{ .left = comparisonExprId, .operator = tokenType, .right = rightComparisonExprId } };
        comparisonExprId = try self.addExpression(gpa, equalityExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return comparisonExprId;
}

/// comparison -> term ( ( ">" | ">=" | "<" | "<=" ) term )*
fn parseComparison(self: *Parser, gpa: Allocator) !Expressions.ExprionId {
    var termExprId = try self.parseTerm(gpa);
    var tokenType = self.tokens[self.current].tokenType;
    while (tokenType == Scanner.TokenType.Less or tokenType == Scanner.TokenType.LessEqual or tokenType == Scanner.TokenType.Greater or tokenType == Scanner.TokenType.GreaterEqual) {
        self.current += 1;
        const rightTermExprId = try self.parseTerm(gpa);
        const comparisonExpr = Expressions.Expression{ .BinaryExpr = Expressions.BinaryExpr{ .left = termExprId, .operator = tokenType, .right = rightTermExprId } };
        termExprId = try self.addExpression(gpa, comparisonExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return termExprId;
}

/// term -> factor ( ( "+" | "-" ) factor )*
fn parseTerm(self: *Parser, gpa: Allocator) !Expressions.ExprionId {
    const expr = Expressions.Expression{ .LiteralExpr = Expressions.LiteralExpr{ .value = Expressions.LiteralValue{ .Bool = false } } };
    self.current += 1;
    return try self.addExpression(gpa, expr);
}

/// factor -> unary ( ( "*" | "/" ) unary )*
fn parseFactor(_: *Parser) Expressions.Expression {
    unreachable;
}

/// unary -> ( "*" | "/" ) unary
///         | primary
fn parseUnary(_: *Parser) Expressions.Expression {
    unreachable;
}

/// primary -> Number | String | "true" | "false" | "nil"
///         | "(" expression ")"
fn parsePrimary(_: *Parser) Expressions.Expression {
    unreachable;
}

fn addExpression(self: *Parser, gpa: Allocator, expr: Expressions.Expression) !Expressions.ExprionId {
    const id = self.expressions.items.len;
    try self.expressions.append(gpa, expr);
    return @intCast(id);
}

// return Expressions.Expression{ .LiteralExpr = Expressions.LiteralExpr{ .value = Expressions.LiteralValue{ .Bool = false } } };

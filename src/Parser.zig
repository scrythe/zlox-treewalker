const std = @import("std");
const Scanner = @import("Scanner.zig");
const Expressions = @import("Expressions.zig");
const Allocator = std.mem.Allocator;
const Lox = @import("Lox.zig");

pub const ParseError = Allocator.Error || Lox.Error || std.fmt.ParseIntError;

const Parser = @This();
code: []const u8,
tokens: []const Scanner.Token,
current: u32,
expressions: std.ArrayList(Expressions.Expression),

pub fn init(gpa: Allocator, code: []const u8, tokens: []const Scanner.Token) ParseError!Parser {
    const expressions = try std.ArrayList(Expressions.Expression).initCapacity(gpa, tokens.len);
    return Parser{ .code = code, .tokens = tokens, .current = 0, .expressions = expressions };
}

pub fn deinit(self: *Parser, gpa: Allocator) void {
    self.expressions.deinit(gpa);
}

pub fn parse(self: *Parser, gpa: Allocator) ParseError!void {
    for (self.tokens) |token| {
        std.debug.print("token: {}\n", .{token});
    }
    // const token = self.tokens[self.current];
    const expression = try self.parseExpression(gpa);
    std.debug.print("expression: {}\n", .{expression});
    // std.debug.print("{}\n", .{self.tokens[self.current]});
    for (self.expressions.items) |expr| {
        std.debug.print("expression: {}\n", .{expr});
    }
}

/// expression -> equality
fn parseExpression(self: *Parser, gpa: Allocator) ParseError!Expressions.ExprionId {
    return self.parseEquality(gpa);
}

/// equality -> comparison ( ( "!=" | "==" ) comparison )*
fn parseEquality(self: *Parser, gpa: Allocator) ParseError!Expressions.ExprionId {
    var comparisonExprId = try self.parseComparison(gpa);
    var tokenType = self.tokens[self.current].tokenType;
    while (equalsTokenTypes(tokenType, &.{ .BangEqual, .EqualEqual })) {
        self.current += 1;
        const rightComparisonExprId = try self.parseComparison(gpa);
        const equalityExpr = Expressions.Expression{ .BinaryExpr = Expressions.BinaryExpr{ .left = comparisonExprId, .operator = tokenType, .right = rightComparisonExprId } };
        comparisonExprId = try self.addExpression(gpa, equalityExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return comparisonExprId;
}

/// comparison -> term ( ( ">" | ">=" | "<" | "<=" ) term )*
fn parseComparison(self: *Parser, gpa: Allocator) ParseError!Expressions.ExprionId {
    var termExprId = try self.parseTerm(gpa);
    var tokenType = self.tokens[self.current].tokenType;
    while (equalsTokenTypes(tokenType, &.{ .Less, .LessEqual, .Greater, .GreaterEqual })) {
        self.current += 1;
        const rightTermExprId = try self.parseTerm(gpa);
        const comparisonExpr = Expressions.Expression{ .BinaryExpr = Expressions.BinaryExpr{ .left = termExprId, .operator = tokenType, .right = rightTermExprId } };
        termExprId = try self.addExpression(gpa, comparisonExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return termExprId;
}

/// term -> factor ( ( "+" | "-" ) factor )*
fn parseTerm(self: *Parser, gpa: Allocator) ParseError!Expressions.ExprionId {
    var factorExprId = try self.parseFactor(gpa);
    var tokenType = self.tokens[self.current].tokenType;
    while (equalsTokenTypes(tokenType, &.{ .Plus, .Minus })) {
        self.current += 1;
        const rightFactorExprId = try self.parseFactor(gpa);
        const termExpr = Expressions.Expression{ .BinaryExpr = Expressions.BinaryExpr{ .left = factorExprId, .operator = tokenType, .right = rightFactorExprId } };
        factorExprId = try self.addExpression(gpa, termExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return factorExprId;
}

/// factor -> unary ( ( "*" | "/" ) unary )*
fn parseFactor(self: *Parser, gpa: Allocator) ParseError!Expressions.ExprionId {
    var unaryExprId = try self.parseUnary(gpa);
    var tokenType = self.tokens[self.current].tokenType;
    while (equalsTokenTypes(tokenType, &.{ .Star, .Slash })) {
        self.current += 1;
        const rightUnaryExprId = try self.parseUnary(gpa);
        const factorExpr = Expressions.Expression{ .BinaryExpr = Expressions.BinaryExpr{ .left = unaryExprId, .operator = tokenType, .right = rightUnaryExprId } };
        unaryExprId = try self.addExpression(gpa, factorExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return unaryExprId;
}

/// unary -> ( "!" | "-" ) unary
///         | primary
fn parseUnary(self: *Parser, gpa: Allocator) ParseError!Expressions.ExprionId {
    const tokenType = self.tokens[self.current].tokenType;
    if (equalsTokenTypes(tokenType, &.{ Scanner.TokenType.Bang, Scanner.TokenType.Minus })) {
        self.current += 1;
        const rightUnaryExprId = try self.parseUnary(gpa);
        const totalUnaryExpr = Expressions.Expression{ .UnaryExpr = Expressions.UnaryExpr{ .operator = tokenType, .right = rightUnaryExprId } };
        return self.addExpression(gpa, totalUnaryExpr);
    }
    return self.parsePrimary(gpa);
}

/// primary -> Number | String | "true" | "false" | "nil"
///         | "(" expression ")"
fn parsePrimary(self: *Parser, gpa: Allocator) ParseError!Expressions.ExprionId {
    const token = self.tokens[self.current];
    self.current += 1;
    const expr = switch (token.tokenType) {
        .False => Expressions.Expression{ .LiteralExpr = Expressions.LiteralExpr{ .value = Expressions.LiteralValue{ .Bool = false } } },
        .True => Expressions.Expression{ .LiteralExpr = Expressions.LiteralExpr{ .value = Expressions.LiteralValue{ .Bool = true } } },
        .Nil => Expressions.Expression{ .LiteralExpr = Expressions.LiteralExpr{ .value = Expressions.LiteralValue{ .None = {} } } },
        .Number => blk: {
            const nextTokenStart = self.tokens[self.current].start;
            const tokenLexeme = self.code[token.start..nextTokenStart];

            var numberStringEnd = tokenLexeme.len;
            for (tokenLexeme, 0..) |char, i| {
                if (!std.ascii.isDigit(char) and char != '.') {
                    numberStringEnd = i;
                    break;
                }
            }
            const numberString = tokenLexeme[0..numberStringEnd];
            const number = try std.fmt.parseInt(u32, numberString, 10);
            break :blk Expressions.Expression{ .LiteralExpr = Expressions.LiteralExpr{ .value = Expressions.LiteralValue{ .Number = number } } };
        },
        .String => blk: {
            const nextTokenStart = self.tokens[self.current].start;
            const tokenLexeme = self.code[token.start..nextTokenStart][1..];

            var stringEnd = tokenLexeme.len;
            for (tokenLexeme, 0..) |char, i| {
                if (char == '"') {
                    stringEnd = i;
                    break;
                }
            }
            const string = tokenLexeme[0..stringEnd];
            std.debug.print("{s}\n", .{string});
            break :blk Expressions.Expression{ .LiteralExpr = Expressions.LiteralExpr{ .value = Expressions.LiteralValue{ .String = string } } };
        },
        .LeftParen => blk: {
            const exprId = try self.parseExpression(gpa);
            if (self.tokens[self.current].tokenType != Scanner.TokenType.RightParen) {
                return Lox.Error.CompileError;
            }
            self.current += 1;
            break :blk Expressions.Expression{ .GroupingExpr = Expressions.GroupingExpr{ .expression = exprId } };
        },
        else => unreachable,
    };
    return try self.addExpression(gpa, expr);
}

fn addExpression(self: *Parser, gpa: Allocator, expr: Expressions.Expression) Allocator.Error!Expressions.ExprionId {
    const id = self.expressions.items.len;
    try self.expressions.append(gpa, expr);
    return @intCast(id);
}

fn equalsTokenTypes(tokenType: Scanner.TokenType, comptime tokenTypes: []const Scanner.TokenType) bool {
    inline for (tokenTypes) |expectedToken| {
        if (tokenType == expectedToken) return true;
    }
    return false;
}

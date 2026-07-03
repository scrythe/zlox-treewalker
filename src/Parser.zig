const std = @import("std");
const Scanner = @import("Scanner.zig");
const Expressions = @import("Expressions.zig");
const Lox = @import("Lox.zig");
const Reporter = @import("Reporter.zig");

const Expression = Expressions.Expression;
const LiteralValue = Expressions.LiteralValue;
const Allocator = std.mem.Allocator;
const ExprId = Expressions.ExprId;
const TokenType = Scanner.TokenType;

pub const ParseError = Allocator.Error || Lox.Error || std.fmt.ParseFloatError || std.Io.Writer.Error;

const Parser = @This();
code: []const u8,
tokens: []const Scanner.Token,
current: u32,
expressions: std.ArrayList(Expression),

pub fn init(gpa: Allocator, code: []const u8, tokens: []const Scanner.Token) ParseError!Parser {
    const expressions = try std.ArrayList(Expression).initCapacity(gpa, tokens.len);
    return Parser{ .code = code, .tokens = tokens, .current = 0, .expressions = expressions };
}

pub fn deinit(self: *Parser, gpa: Allocator) void {
    self.expressions.deinit(gpa);
}

pub fn parse(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    return try self.parseExpression(gpa, reporter);
}

/// expression -> equality
fn parseExpression(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    return self.parseEquality(gpa, reporter);
}

/// equality -> comparison ( ( "!=" | "==" ) comparison )*
fn parseEquality(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    var comparisonExprId = try self.parseComparison(gpa, reporter);
    var tokenType = self.tokens[self.current].tokenType;
    while (equalsTokenTypes(tokenType, &.{ .BangEqual, .EqualEqual })) {
        self.current += 1;
        const rightComparisonExprId = try self.parseComparison(gpa, reporter);
        const equalityExprValue: Expressions.BinaryExpr = .{ .left = comparisonExprId, .operator = tokenType, .right = rightComparisonExprId };
        const equalityExpr = Expression{ .BinaryExpr = equalityExprValue };
        comparisonExprId = try self.addExpression(gpa, equalityExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return comparisonExprId;
}

/// comparison -> term ( ( ">" | ">=" | "<" | "<=" ) term )*
fn parseComparison(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    var termExprId = try self.parseTerm(gpa, reporter);
    var tokenType = self.tokens[self.current].tokenType;
    while (equalsTokenTypes(tokenType, &.{ .Less, .LessEqual, .Greater, .GreaterEqual })) {
        self.current += 1;
        const rightTermExprId = try self.parseTerm(gpa, reporter);
        const comparisonExprValue: Expressions.BinaryExpr = .{ .left = termExprId, .operator = tokenType, .right = rightTermExprId };
        const comparisonExpr = Expression{ .BinaryExpr = comparisonExprValue };
        termExprId = try self.addExpression(gpa, comparisonExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return termExprId;
}

/// term -> factor ( ( "+" | "-" ) factor )*
fn parseTerm(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    var factorExprId = try self.parseFactor(gpa, reporter);
    var tokenType = self.tokens[self.current].tokenType;
    while (equalsTokenTypes(tokenType, &.{ .Plus, .Minus })) {
        self.current += 1;
        const rightFactorExprId = try self.parseFactor(gpa, reporter);
        const termExprValue: Expressions.BinaryExpr = .{ .left = factorExprId, .operator = tokenType, .right = rightFactorExprId };
        const termExpr = Expression{ .BinaryExpr = termExprValue };
        factorExprId = try self.addExpression(gpa, termExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return factorExprId;
}

/// factor -> unary ( ( "*" | "/" ) unary )*
fn parseFactor(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    var unaryExprId = try self.parseUnary(gpa, reporter);
    var tokenType = self.tokens[self.current].tokenType;
    while (equalsTokenTypes(tokenType, &.{ .Star, .Slash })) {
        self.current += 1;
        const rightUnaryExprId = try self.parseUnary(gpa, reporter);
        const factorExprValue: Expressions.BinaryExpr = .{ .left = unaryExprId, .operator = tokenType, .right = rightUnaryExprId };
        const factorExpr = Expression{ .BinaryExpr = factorExprValue };
        unaryExprId = try self.addExpression(gpa, factorExpr);

        tokenType = self.tokens[self.current].tokenType;
    }
    return unaryExprId;
}

/// unary -> ( "!" | "-" ) unary
///         | primary
fn parseUnary(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    const tokenType = self.tokens[self.current].tokenType;
    if (equalsTokenTypes(tokenType, &.{ TokenType.Bang, TokenType.Minus })) {
        self.current += 1;
        const rightUnaryExprId = try self.parseUnary(gpa, reporter);
        const totalUnaryExprValue: Expressions.UnaryExpr = .{ .operator = tokenType, .right = rightUnaryExprId };
        const totalUnaryExpr = Expression{ .UnaryExpr = totalUnaryExprValue };
        return self.addExpression(gpa, totalUnaryExpr);
    }
    return self.parsePrimary(gpa, reporter);
}

/// primary -> Number | String | "true" | "false" | "nil"
///         | "(" expression ")"
fn parsePrimary(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    const token = self.tokens[self.current];
    self.current += 1;
    const expr = switch (token.tokenType) {
        .False => Expression{ .LiteralExpr = .{ .value = LiteralValue{ .Bool = false } } },
        .True => Expression{ .LiteralExpr = .{ .value = LiteralValue{ .Bool = true } } },
        .Nil => Expression{ .LiteralExpr = .{ .value = LiteralValue{ .None = {} } } },
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
            const number = try std.fmt.parseFloat(f32, numberString);
            const literalValue: LiteralValue = .{ .Number = number };
            break :blk Expression{ .LiteralExpr = .{ .value = literalValue } };
        },
        .String => blk: {
            const nextTokenStart = self.tokens[self.current].start;
            const tokenLexeme = self.code[token.start + 1 .. nextTokenStart];

            var stringEnd = tokenLexeme.len;
            for (tokenLexeme, 0..) |char, i| {
                if (char == '"') {
                    stringEnd = i;
                    break;
                }
            }
            const string = tokenLexeme[0..stringEnd];
            const literalValue: LiteralValue = .{ .String = string };
            break :blk Expression{ .LiteralExpr = .{ .value = literalValue } };
        },
        .LeftParen => blk: {
            const exprId = try self.parseExpression(gpa, reporter);
            const nextToken = self.tokens[self.current];
            if (nextToken.tokenType != TokenType.RightParen) {
                const tokenLexeme = self.code[token.start..nextToken.start];
                var lexemeEnd = tokenLexeme.len;
                for (tokenLexeme, 0..) |char, i| {
                    if (char == '\r' or char == '\t' or char == '\n' or char == ' ') {
                        lexemeEnd = i;
                        break;
                    }
                }
                const lexeme = tokenLexeme[0..lexemeEnd];
                const messagePart = "at ";
                const message = try gpa.alloc(u8, messagePart.len + lexeme.len);
                defer gpa.free(message);
                @memcpy(message[0..messagePart.len], messagePart);
                @memcpy(message[messagePart.len..], lexeme);
                try reporter.report(nextToken.line, message, "Expect ')' after expression");
                return Lox.Error.CompileError;
            }
            self.current += 1;
            break :blk Expression{ .GroupingExpr = .{ .expression = exprId } };
        },
        else => unreachable,
    };
    return try self.addExpression(gpa, expr);
}

fn addExpression(self: *Parser, gpa: Allocator, expr: Expression) Allocator.Error!ExprId {
    const id = self.expressions.items.len;
    try self.expressions.append(gpa, expr);
    return @intCast(id);
}

fn equalsTokenTypes(tokenType: TokenType, comptime tokenTypes: []const TokenType) bool {
    inline for (tokenTypes) |expectedToken| {
        if (tokenType == expectedToken) return true;
    }
    return false;
}

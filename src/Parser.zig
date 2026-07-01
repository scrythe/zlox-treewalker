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

pub fn parse(self: *Parser) void {
    while (self.tokens[self.current].tokenType != Scanner.TokenType.Eof) {
        // const token = self.tokens[self.current];
        const expression = self.parseExpression();
        std.debug.print("expression: {}\n", .{expression});
        // std.debug.print("{}\n", .{self.tokens[self.current]});
        self.current += 1;
    }
}

/// expression -> equality
fn parseExpression(self: *Parser) Expressions.Expression {
    return self.parseEquality();
}

/// equality -> comparison ( ( "!=" | "==" ) comparison )*
fn parseEquality(_: *Parser) Expressions.Expression {
    unreachable;
}

/// comparison -> term ( ( ">" | ">=" | "<" | "<=" ) term )*
fn parseComparison(_: *Parser) Expressions.Expression {
    unreachable;
}

/// term -> factor ( ( "+" | "-" ) factor )*
fn parseTerm(_: *Parser) Expressions.Expression {
    unreachable;
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

// return Expressions.Expression{ .LiteralExpr = Expressions.LiteralExpr{ .value = Expressions.LiteralValue{ .Bool = false } } };

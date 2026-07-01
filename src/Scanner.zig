const std = @import("std");
const Allocator = std.mem.Allocator;
const Reporter = @import("Reporter.zig");
const Lox = @import("Lox.zig");

const StaticStringMap = std.static_string_map.StaticStringMap;
const tokenKeywordMap = StaticStringMap(TokenType).initComptime(.{
    .{ "and", TokenType.And },
    .{ "class", TokenType.Class },
    .{ "else", TokenType.Else },
    .{ "false", TokenType.False },
    .{ "for", TokenType.For },
    .{ "fun", TokenType.Fun },
    .{ "if", TokenType.If },
    .{ "nil", TokenType.Nil },
    .{ "or", TokenType.Or },
    .{ "print", TokenType.Print },
    .{ "return", TokenType.Return },
    .{ "super", TokenType.Super },
    .{ "this", TokenType.This },
    .{ "true", TokenType.True },
    .{ "var", TokenType.Var },
    .{ "while", TokenType.While },
});

const Scanner = @This();
line: u32,
start: u32,
current: u32,
code: []const u8,
tokens: std.ArrayList(Token),

pub const ScanTokensError = Allocator.Error || Lox.Error || std.Io.Writer.Error;

pub const TokenType = enum {
    // Single-character tokens.
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Slash,
    Star,
    // One or two character tokens.
    Bang,
    BangEqual,
    Equal,
    EqualEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,

    // Literals
    String,
    Number,
    Identifier,

    // Keywords
    And,
    Class,
    Else,
    False,
    Fun,
    For,
    If,
    Nil,
    Or,
    Print,
    Return,
    Super,
    This,
    True,
    Var,
    While,

    Eof,
};

pub const Token = struct {
    tokenType: TokenType,
    start: u32,
    fn init(tokenType: TokenType, start: u32) Token {
        return Token{ .tokenType = tokenType, .start = start };
    }
};

pub fn init(gpa: Allocator, code: []const u8) Allocator.Error!Scanner {
    const tokens = try std.ArrayList(Token).initCapacity(gpa, code.len);
    return Scanner{
        .line = 1,
        .start = 0,
        .current = 0,
        .code = code,
        .tokens = tokens,
    };
}

pub fn deinit(self: *Scanner, gpa: Allocator) void {
    self.tokens.deinit(gpa);
}

pub fn scanTokens(self: *Scanner, gpa: Allocator, reporter: Reporter) ScanTokensError!void {
    var scanError = false;
    while (!self.isAtEnd()) {
        self.start = self.current;
        const char = self.code[self.current];
        self.current += 1;
        switch (char) {
            '(' => try self.addToken(gpa, TokenType.LeftParen),
            ')' => try self.addToken(gpa, TokenType.RightParen),
            '{' => try self.addToken(gpa, TokenType.LeftBrace),
            '}' => try self.addToken(gpa, TokenType.RightBrace),
            ',' => try self.addToken(gpa, TokenType.Comma),
            '.' => try self.addToken(gpa, TokenType.Dot),
            '-' => try self.addToken(gpa, TokenType.Minus),
            '+' => try self.addToken(gpa, TokenType.Plus),
            ';' => try self.addToken(gpa, TokenType.Semicolon),
            '*' => try self.addToken(gpa, TokenType.Star),

            '!' => {
                const tokenType = if (self.matchChar('=')) TokenType.BangEqual else TokenType.Bang;
                try self.addToken(gpa, tokenType);
            },
            '=' => {
                const tokenType = if (self.matchChar('=')) TokenType.EqualEqual else TokenType.Equal;
                try self.addToken(gpa, tokenType);
            },
            '<' => {
                const tokenType = if (self.matchChar('=')) TokenType.LessEqual else TokenType.Less;
                try self.addToken(gpa, tokenType);
            },
            '>' => {
                const tokenType = if (self.matchChar('=')) TokenType.GreaterEqual else TokenType.Greater;
                try self.addToken(gpa, tokenType);
            },
            '/' => {
                if (self.matchChar('/')) {
                    while (!self.isAtEnd() and self.code[self.current] != '\n') {
                        self.current += 1;
                    }
                } else {
                    try self.addToken(gpa, TokenType.Slash);
                }
            },
            ' ', '\r', '\t' => undefined,
            '\n' => self.line += 1,
            '"' => {
                while (!self.isAtEnd() and self.code[self.current] != '"') {
                    if (self.code[self.current] == '\n') self.line += 1;
                    self.current += 1;
                }
                if (self.isAtEnd()) {
                    try reporter.report(self.line, "", "Unterminated String");
                    scanError = true;
                }
                // consume "
                self.current += 1;
                try self.addToken(gpa, TokenType.String);
            },
            '0'...'9' => {
                while (std.ascii.isDigit(self.code[self.current])) {
                    self.current += 1;
                }
                if (self.code[self.current] == '.' and std.ascii.isDigit(self.code[self.current + 1])) {
                    self.current += 1;
                    while (std.ascii.isDigit(self.code[self.current])) {
                        self.current += 1;
                    }
                }
                try self.addToken(gpa, TokenType.Number);
            },
            'a'...'z', 'A'...'Z', '_' => {
                while (!self.isAtEnd() and std.ascii.isAlphanumeric(self.code[self.current])) {
                    self.current += 1;
                }
                const identifierText = self.code[self.start..self.current];
                const identifierTokenType = tokenKeywordMap.get(identifierText) orelse TokenType.Identifier;
                try self.addToken(gpa, identifierTokenType);
            },
            else => {
                var message = comptime blk: {
                    const message = "Unexpected Character ";
                    var buf: [message.len + 1]u8 = undefined;
                    @memcpy(buf[0..message.len], message);
                    break :blk buf;
                };
                message[message.len - 1] = char;
                try reporter.report(self.line, "", &message);
                scanError = true;
            },
        }
    }
    try self.addToken(gpa, TokenType.Eof);
    if (scanError) {
        return Lox.Error.CompileError;
    }
}

pub fn printTokens(self: *const Scanner) void {
    std.debug.print("Tokens: \n", .{});
    for (self.tokens.items) |token| {
        std.debug.print("TokenType: {}, text: {u}\n", .{ token.tokenType, self.code[token.start] });
    }
    std.debug.print("\n", .{});
}

fn isAtEnd(self: *const Scanner) bool {
    return self.current >= self.code.len;
}

fn addToken(self: *Scanner, gpa: Allocator, tokenType: TokenType) Allocator.Error!void {
    const token = Token.init(tokenType, self.start);
    try self.tokens.append(gpa, token);
}

fn matchChar(self: *Scanner, token: u8) bool {
    if (self.isAtEnd() or self.code[self.current] != token) return false;
    self.current += 1;
    return true;
}

const testing = std.testing;

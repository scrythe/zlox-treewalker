const std = @import("std");
const Allocator = std.mem.Allocator;

const TokenType = enum {
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

const Token = struct {
    tokenType: TokenType,
    start: u32,
    fn init(tokenType: TokenType, start: u32) Token {
        return Token{ .tokenType = tokenType, .start = start };
    }
};

pub const Scanner = struct {
    current: u32 = 0,
    code: []const u8,
    tokens: std.ArrayList(TokenType),

    pub fn init(gpa: Allocator, code: []const u8) !Scanner {
        const tokens = try std.ArrayList(TokenType).initCapacity(gpa, code.len);
        return Scanner{ .code = code, .tokens = tokens };
    }

    pub fn deinit(self: *Scanner, gpa: Allocator) void {
        self.tokens.deinit(gpa);
    }

    pub fn scanTokens(self: *Scanner, gpa: Allocator) !void {
        while (!self.isAtEnd()) {
            switch (self.advance()) {
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
                else => undefined,
            }
        }
    }

    pub fn printTokens(self: *const Scanner) void {
        std.debug.print("Tokens: ", .{});
        for (self.tokens.items) |token| {
            std.debug.print("{} ", .{token});
        }
        std.debug.print("\n", .{});
    }

    fn isAtEnd(self: *const Scanner) bool {
        return self.current >= self.code.len;
    }

    fn advance(self: *Scanner) u8 {
        const char = self.code[self.current];
        self.current += 1;
        return char;
    }

    fn addToken(self: *Scanner, gpa: Allocator, tokenType: TokenType) !void {
        try self.tokens.append(gpa, tokenType);
    }

    fn matchChar(self: *Scanner, token: u8) bool {
        if (self.isAtEnd() or self.code[self.current] != token) return false;
        self.current += 1;
        return true;
    }
};

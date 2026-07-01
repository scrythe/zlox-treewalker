const std = @import("std");
const Scanner = @import("Scanner.zig");
const Expressions = @import("Expressions.zig");

const Parser = @This();
code: []const u8,
tokens: []const Scanner.Token,
current: u32,

pub fn init(code: []const u8, tokens: []const Scanner.Token) Parser {
    return Parser{ .code = code, .tokens = tokens, .current = 0 };
}

pub fn parse(self: *Parser) void {
    while (self.tokens[self.current].tokenType != Scanner.TokenType.Eof) {
        // const token = self.tokens[self.current];
        self.expression();
        // std.debug.print("{}\n", .{self.tokens[self.current]});
        self.current += 1;
    }
}
fn expression(_: Parser) Expressions.Expression {}

fn equality(_: Parser) void {}

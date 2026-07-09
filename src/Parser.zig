const std = @import("std");
const Scanner = @import("Scanner.zig");
const Expressions = @import("Expressions.zig");
const Lox = @import("Lox.zig");
const Reporter = @import("Reporter.zig");
const PrettyPrinter = @import("PrettyPrinter.zig");

const Expression = Expressions.Expression;
const LiteralValue = Expressions.LiteralValue;
const Allocator = std.mem.Allocator;
const ExprId = Expressions.ExprId;
const TokenType = Scanner.TokenType;

pub const ParseError = Allocator.Error || Lox.Error || std.fmt.ParseFloatError || std.Io.Writer.Error;

const log = std.log.scoped(.parser);

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
            if (std.math.isInf(number)) {
                const errWhere = if (self.current < self.tokens.len) err: {
                    const nextToken = self.tokens[self.current];
                    break :err try self.getTokenErrWhere(gpa, token, nextToken);
                } else err: {
                    break :err "";
                };
                defer if (self.current < self.tokens.len) gpa.free(errWhere);
                try reporter.report(token.line, errWhere, "Number to big, casted to infinite");
                return Lox.Error.CompileError;
            }
            const literalValue: LiteralValue = .{ .Number = number };
            break :blk Expression{ .LiteralExpr = .{ .value = literalValue } };
        },
        .String => blk: {
            const nextToken = self.tokens[self.current];
            const tokenLexeme = self.code[token.start + 1 .. nextToken.start];

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
                const errWhere = try self.getTokenErrWhere(gpa, token, nextToken);
                defer gpa.free(errWhere);
                try reporter.report(nextToken.line, errWhere, "Expect ')' after expression");
                return Lox.Error.CompileError;
            }
            self.current += 1;
            break :blk Expression{ .GroupingExpr = .{ .expression = exprId } };
        },
        else => {
            const errWhere = if (self.current < self.tokens.len) blk: {
                const nextToken = self.tokens[self.current];
                break :blk try self.getTokenErrWhere(gpa, token, nextToken);
            } else blk: {
                break :blk "";
            };
            defer if (self.current < self.tokens.len) gpa.free(errWhere);
            try reporter.report(token.line, errWhere, "Expect expression");
            return Lox.Error.CompileError;
        },
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

fn getTokenErrWhere(self: *const Parser, gpa: Allocator, token: Scanner.Token, nextToken: Scanner.Token) ![]const u8 {
    const tokenLexeme = self.code[token.start..nextToken.start];
    var lexemeEnd = tokenLexeme.len;
    for (tokenLexeme, 0..) |char, i| {
        if (char == '\r' or char == '\t' or char == '\n' or char == ' ') {
            lexemeEnd = i;
            break;
        }
    }
    const lexeme = tokenLexeme[0..lexemeEnd];
    const errWhereStart = "at ";
    const errWhere = try gpa.alloc(u8, errWhereStart.len + lexeme.len);
    @memcpy(errWhere[0..errWhereStart.len], errWhereStart);
    @memcpy(errWhere[errWhereStart.len..], lexeme);
    return errWhere;
}

fn fuzzTestOneScannerAndParser(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    const gpa = std.testing.allocator;

    var stderr_file_writer = std.Io.Writer.Discarding.init(&.{});
    const stderr_writer = &stderr_file_writer.writer;

    const reporter = Reporter.init(stderr_writer);

    const len = smith.valueRangeAtMost(u32, 0, 150);
    const code = try gpa.alloc(u8, len);
    defer gpa.free(code);
    _ = smith.slice(code);

    var scanner = try Scanner.init(gpa, code);
    defer scanner.deinit(gpa);

    try stderr_writer.print("{s}", .{code});
    scanner.scanTokens(gpa, reporter) catch |err| if (err != Scanner.ScanTokensError.CompileError) return err;
    try scanner.printTokens(stderr_writer);

    var parser = try Parser.init(gpa, code, scanner.tokens.items);
    defer parser.deinit(gpa);

    const exprId = parser.parse(gpa, reporter) catch |err| switch (err) {
        Scanner.ScanTokensError.CompileError => return,
        else => return err,
    };
    _ = exprId;
}

fn fuzzTestOneParserAndPrettyPrinter(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    const gpa = std.testing.allocator;

    // var stderr_file_writer = std.Io.File.stderr().writer(std.testing.io, &.{});
    // const stderr_writer = &stderr_file_writer.interface;
    var stderr_file_writer = std.Io.Writer.Discarding.init(&.{});
    const stderr_writer = &stderr_file_writer.writer;

    const reporter = Reporter.init(stderr_writer);

    const len = smith.valueRangeAtMost(u32, 0, 150);
    const code = try gpa.alloc(u8, len);
    defer gpa.free(code);
    _ = smith.slice(code);

    var scanner = try Scanner.init(gpa, code);
    defer scanner.deinit(gpa);

    try stderr_writer.print("{s}", .{code});
    scanner.scanTokens(gpa, reporter) catch |err| if (err != Scanner.ScanTokensError.CompileError) return err;
    try scanner.printTokens(stderr_writer);

    var parser = try Parser.init(gpa, code, scanner.tokens.items);
    defer parser.deinit(gpa);

    const exprId = parser.parse(gpa, reporter) catch |err| switch (err) {
        Scanner.ScanTokensError.CompileError => return,
        else => return err,
    };

    var prettyPrinterWriterBuffer: [1024]u8 = undefined;
    var prettyPrinterWriterOwner = std.Io.Writer.fixed(&prettyPrinterWriterBuffer);
    const prettyPrinterWriter = &prettyPrinterWriterOwner;
    // var prettyPrinterFileWriter = std.Io.File.stderr().writer(std.testing.io, &prettyPrinterWriterBuffer);
    // const prettyPrinterWriter = &prettyPrinterFileWriter.interface;

    const prettyPrinter = PrettyPrinter.init(parser.expressions.items);
    try prettyPrinter.print(prettyPrinterWriter, exprId);
    const prettyCode: []const u8 = prettyPrinterWriterBuffer[0..prettyPrinterWriter.end];

    var prettyScanner = try Scanner.init(gpa, prettyCode);
    defer prettyScanner.deinit(gpa);
    try prettyScanner.scanTokens(gpa, reporter);
    // try std.testing.expectEqualSlices(Scanner.Token, scanner.tokens.items, newScanner.tokens.items);

    var prettyParser = try Parser.init(gpa, prettyCode, prettyScanner.tokens.items);
    defer prettyParser.deinit(gpa);
    const prettyExprId = try prettyParser.parse(gpa, reporter);

    // try std.testing.expectEqualSlices(Expression, parser.expressions.items, prettyParser.expressions.items);

    var prettyPrettyPrinterWriterBuffer: [1024]u8 = undefined;
    var prettyPrettyPrinterWriter = std.Io.Writer.fixed(&prettyPrettyPrinterWriterBuffer);

    const prettyPrettyPrinter = PrettyPrinter.init(prettyParser.expressions.items);
    try prettyPrettyPrinter.print(&prettyPrettyPrinterWriter, prettyExprId);

    const prettyPrettyCode = prettyPrettyPrinterWriterBuffer[0..prettyPrettyPrinterWriter.end];
    try std.testing.expectEqualStrings(prettyCode, prettyPrettyCode);
}

// test "fuzz scanner and parser" {
//     try std.testing.fuzz({}, fuzzTestOneScannerAndParser, .{});
// }

test "fuzz scanner and parser and pretty printer" {
    try std.testing.fuzz({}, fuzzTestOneParserAndPrettyPrinter, .{});
}

test "test crashed parser fuzz" {
    @disableInstrumentation();
    if (@import("builtin").fuzz) return;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const crash = std.Io.Dir.cwd().readFileAlloc(io, ".zig-cache/f/crash", gpa, std.Io.Limit.unlimited) catch return;
    defer gpa.free(crash);
    var smith = std.testing.Smith{ .in = crash };
    // try fuzzTestOneScannerAndParser({}, &smith);
    try fuzzTestOneParserAndPrettyPrinter({}, &smith);
}

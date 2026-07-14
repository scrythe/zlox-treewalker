const std = @import("std");
const Scanner = @import("Scanner.zig");
const Expressions = @import("Expressions.zig");
const Lox = @import("Lox.zig");
const Reporter = @import("Reporter.zig");
const PrettyPrinter = @import("PrettyPrinter.zig");

const Expression = Expressions.Expression;
const Statements = @import("Statements.zig");
const Statement = Statements.Statement;
const StmtId = Statements.StmtId;
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
statements: std.ArrayList(Statement),

pub fn init(gpa: Allocator, code: []const u8, tokens: []const Scanner.Token) ParseError!Parser {
    const expressions = try std.ArrayList(Expression).initCapacity(gpa, tokens.len);
    const statements = try std.ArrayList(Statement).initCapacity(gpa, tokens.len);
    return Parser{
        .code = code,
        .tokens = tokens,
        .current = 0,
        .expressions = expressions,
        .statements = statements,
    };
}

pub fn deinit(self: *Parser, gpa: Allocator) void {
    self.expressions.deinit(gpa);
    self.statements.deinit(gpa);
}

/// program -> delcaration EOF
pub fn parse(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!void {
    var hasError = false;
    var tokenType = self.tokens[self.current].tokenType;
    while (tokenType != .Eof) {
        self.parseDeclaration(gpa, reporter) catch |err| {
            if (err != ParseError.CompileError) return;
            hasError = true;
            self.synchronize();
        };
        if (self.current >= self.tokens.len) break;
        tokenType = self.tokens[self.current].tokenType;
    }
    if (hasError) return ParseError.CompileError;
}

/// declaration -> varDecl | statement
fn parseDeclaration(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!void {
    const tokenType = self.tokens[self.current].tokenType;
    if (tokenType == .Var) {
        self.current += 1;
        try self.parseVarDecl(gpa, reporter);
    } else {
        try self.parseStatement(gpa, reporter);
    }
}

/// varDecl -> "var" Identifier ( "=" expression )? ";"
fn parseVarDecl(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!void {
    const token = self.tokens[self.current];
    try self.checkTokenTypeAndConsumeOnNoError(reporter, .Identifier, "Expect variable name.", token);

    const nextToken = self.tokens[self.current];
    const varName = try self.getLexemeText(token, nextToken);

    const initializerExprId: ExprId =
        if (self.tokens[self.current].tokenType == .Equal) blk: {
            self.current += 1;
            break :blk try self.parseExpression(gpa, reporter);
        } else blk: {
            const literalExpr = Expression{ .LiteralExpr = .{ .value = .None } };
            break :blk try self.addExpression(gpa, literalExpr);
        };

    const varDeclStmtValue = Statements.VarDeclStmt{ .varName = varName, .valueExprId = initializerExprId };
    const varDeclStmt = Statement{ .VarDeclStmt = varDeclStmtValue };
    try self.statements.append(gpa, varDeclStmt);

    const semicolonToken = self.tokens[self.current];
    try self.checkTokenTypeAndConsumeOnNoError(reporter, .Semicolon, "Expect ';' after variable declaration.", semicolonToken);
}

/// statement -> exprStmt | printStmt
fn parseStatement(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!void {
    // could maybe combine some logic from parseExprStmt and parsePrintStmt but will
    // do later if still worth it
    const tokenType = self.tokens[self.current].tokenType;
    if (tokenType == .Print) {
        self.current += 1;
        try self.parsePrintStmt(gpa, reporter);
    } else {
        try self.parseExprStmt(gpa, reporter);
    }
}

fn parseExprStmt(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!void {
    const exprId = try self.parseExpression(gpa, reporter);
    const exprStmtValue = Statements.ExpressionStmt{ .exprId = exprId };
    const exprStmt = Statement{ .ExpressionStmt = exprStmtValue };
    try self.statements.append(gpa, exprStmt);
    const token = self.tokens[self.current];
    try self.checkTokenTypeAndConsumeOnNoError(reporter, .Semicolon, "Expect ';' after expression.", token);
}

/// printStmt -> "print" expression ";"
fn parsePrintStmt(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!void {
    const exprId = try self.parseExpression(gpa, reporter);
    const printStmtValue = Statements.PrintStmt{ .exprId = exprId };
    const printStmt = Statement{ .PrintStmt = printStmtValue };
    try self.statements.append(gpa, printStmt);
    const token = self.tokens[self.current];
    try self.checkTokenTypeAndConsumeOnNoError(reporter, .Semicolon, "Expect ';' after value.", token);
}

/// expression -> assignment
fn parseExpression(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    return self.parseAssignment(gpa, reporter);
}

/// assignment -> equality
fn parseAssignment(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    const equalityExprId = try self.parseEquality(gpa, reporter);
    const token = self.tokens[self.current];
    if (token.tokenType != .Equal) return equalityExprId;
    self.current += 1;
    const valueExprId = try self.parseAssignment(gpa, reporter);

    const equalityExpr = self.expressions.items[equalityExprId];
    if (equalityExpr != .VariableExpr) {
        if (self.current + 1 >= self.tokens.len) {
            try reporter.reportWithContextAtEnd(token.line, "Invalid assignment targt.");
            return ParseError.CompileError;
        } else {
            const tokenLexeme = try self.getLexemeText(token, self.tokens[self.current + 1]);
            try reporter.reportWithContext(token.line, tokenLexeme, "Invalid assignment targt.");
            return ParseError.CompileError;
        }
    }

    const varName = equalityExpr.VariableExpr.varName;
    const assignmentExpr = Expression{ .AssignmentExpr = .{
        .varName = varName,
        .valueExprId = valueExprId,
        .line = token.line,
    } };
    return self.addExpression(gpa, assignmentExpr);
}

/// equality -> comparison ( ( "!=" | "==" ) comparison )*
fn parseEquality(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    var comparisonExprId = try self.parseComparison(gpa, reporter);
    var token = self.tokens[self.current];
    while (equalsTokenTypes(token.tokenType, &.{ .BangEqual, .EqualEqual })) {
        self.current += 1;
        const rightComparisonExprId = try self.parseComparison(gpa, reporter);
        const equalityExprValue = Expressions.BinaryExpr.init(comparisonExprId, token.tokenType, rightComparisonExprId, token.line);
        const equalityExpr = Expression{ .BinaryExpr = equalityExprValue };
        comparisonExprId = try self.addExpression(gpa, equalityExpr);

        token = self.tokens[self.current];
    }
    return comparisonExprId;
}

/// comparison -> term ( ( ">" | ">=" | "<" | "<=" ) term )*
fn parseComparison(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    var termExprId = try self.parseTerm(gpa, reporter);
    var token = self.tokens[self.current];
    while (equalsTokenTypes(token.tokenType, &.{ .Less, .LessEqual, .Greater, .GreaterEqual })) {
        self.current += 1;
        const rightTermExprId = try self.parseTerm(gpa, reporter);
        const comparisonExprValue = Expressions.BinaryExpr.init(termExprId, token.tokenType, rightTermExprId, token.line);
        const comparisonExpr = Expression{ .BinaryExpr = comparisonExprValue };
        termExprId = try self.addExpression(gpa, comparisonExpr);

        token = self.tokens[self.current];
    }
    return termExprId;
}

/// term -> factor ( ( "+" | "-" ) factor )*
fn parseTerm(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    var factorExprId = try self.parseFactor(gpa, reporter);
    var token = self.tokens[self.current];
    while (equalsTokenTypes(token.tokenType, &.{ .Plus, .Minus })) {
        self.current += 1;
        const rightFactorExprId = try self.parseFactor(gpa, reporter);
        const termExprValue = Expressions.BinaryExpr.init(factorExprId, token.tokenType, rightFactorExprId, token.line);
        const termExpr = Expression{ .BinaryExpr = termExprValue };
        factorExprId = try self.addExpression(gpa, termExpr);

        token = self.tokens[self.current];
    }
    return factorExprId;
}

/// factor -> unary ( ( "*" | "/" ) unary )*
fn parseFactor(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    var unaryExprId = try self.parseUnary(gpa, reporter);
    var token = self.tokens[self.current];
    while (equalsTokenTypes(token.tokenType, &.{ .Star, .Slash })) {
        self.current += 1;
        const rightUnaryExprId = try self.parseUnary(gpa, reporter);
        const factorExprValue = Expressions.BinaryExpr.init(unaryExprId, token.tokenType, rightUnaryExprId, token.line);
        const factorExpr = Expression{ .BinaryExpr = factorExprValue };
        unaryExprId = try self.addExpression(gpa, factorExpr);

        token = self.tokens[self.current];
    }
    return unaryExprId;
}

/// unary -> ( "!" | "-" ) unary
///         | primary
fn parseUnary(self: *Parser, gpa: Allocator, reporter: Reporter) ParseError!ExprId {
    const token = self.tokens[self.current];
    if (equalsTokenTypes(token.tokenType, &.{ TokenType.Bang, TokenType.Minus })) {
        self.current += 1;
        const rightUnaryExprId = try self.parseUnary(gpa, reporter);
        const totalUnaryExprValue = Expressions.UnaryExpr.init(token.tokenType, rightUnaryExprId, token.line);
        const totalUnaryExpr = Expression{ .UnaryExpr = totalUnaryExprValue };
        return self.addExpression(gpa, totalUnaryExpr);
    }
    return self.parsePrimary(gpa, reporter);
}

/// primary -> Number | String | "true" | "false" | "nil"
///         | "(" expression ")" | Identifier
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
                try reporter.reportWithContext(token.line, tokenLexeme, "Number to big, casted to infinite");
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
                const tokenLexeme = try self.getLexemeText(token, nextToken);
                try reporter.reportWithContext(nextToken.line, tokenLexeme, "Expect ')' after expression");
                return Lox.Error.CompileError;
            }
            self.current += 1;
            break :blk Expression{ .GroupingExpr = .{ .exprId = exprId } };
        },
        .Identifier => blk: {
            const nextToken = self.tokens[self.current];
            const tokenLexeme = try self.getLexemeText(token, nextToken);
            break :blk Expression{ .VariableExpr = .{ .varName = tokenLexeme, .line = token.line } };
        },
        else => {
            if (self.current < self.tokens.len) {
                const nextToken = self.tokens[self.current];
                const tokenLexeme = try self.getLexemeText(token, nextToken);
                try reporter.reportWithContext(token.line, tokenLexeme, "Expect expression");
                return Lox.Error.CompileError;
            } else {
                try reporter.reportWithContextAtEnd(token.line, "Expect expression");
                return Lox.Error.CompileError;
            }
        },
    };
    return try self.addExpression(gpa, expr);
}

fn addExpression(self: *Parser, gpa: Allocator, expr: Expression) Allocator.Error!ExprId {
    const id = self.expressions.items.len;
    try self.expressions.append(gpa, expr);
    return @intCast(id);
}

fn addStatement(self: *Parser, gpa: Allocator, stmt: Statement) Allocator.Error!StmtId {
    const id = self.statements.items.len;
    try self.statements.append(gpa, stmt);
    return @intCast(id);
}

fn equalsTokenTypes(tokenType: TokenType, comptime tokenTypes: []const TokenType) bool {
    inline for (tokenTypes) |expectedToken| {
        if (tokenType == expectedToken) return true;
    }
    return false;
}

fn getLexemeText(self: *const Parser, token: Scanner.Token, nextToken: Scanner.Token) ![]const u8 {
    const tokenLexeme = self.code[token.start..nextToken.start];
    var lexemeEnd = tokenLexeme.len;
    for (tokenLexeme, 0..) |char, i| {
        if (char == '\r' or char == '\t' or char == '\n' or char == ' ') {
            lexemeEnd = i;
            break;
        }
    }
    return tokenLexeme[0..lexemeEnd];
}

fn checkTokenTypeAndConsumeOnNoError(self: *Parser, reporter: Reporter, comptime tokenType: TokenType, comptime errMessage: []const u8, token: Scanner.Token) ParseError!void {
    if (token.tokenType != tokenType) {
        if (self.current + 1 >= self.tokens.len) {
            try reporter.reportWithContextAtEnd(token.line, errMessage);
            return ParseError.CompileError;
        } else {
            const tokenLexeme = try self.getLexemeText(token, self.tokens[self.current + 1]);
            try reporter.reportWithContext(token.line, tokenLexeme, errMessage);
            return ParseError.CompileError;
        }
    }
    self.current += 1;
}

fn synchronize(self: *Parser) void {
    const prevTokenType = self.tokens[self.current].tokenType;
    self.current += 1;
    if (prevTokenType == .Semicolon) return;
    if (self.current >= self.tokens.len) return;
    var tokenType = self.tokens[self.current].tokenType;
    while (tokenType != .Eof) {
        switch (tokenType) {
            .Class,
            .Fun,
            .Var,
            .For,
            .If,
            .While,
            .Print,
            .Return,
            .Semicolon,
            => return,
            else => {},
        }

        self.current += 1;
        tokenType = self.tokens[self.current].tokenType;
    }
}

// fn fuzzTestOneScannerAndParserAndPrettyPrinter(_: void, smith: *std.testing.Smith) !void {
//     @disableInstrumentation();
//     const gpa = std.testing.allocator;
//
//     // var stderr_file_writer = std.Io.File.stderr().writer(std.testing.io, &.{});
//     // const stderr_writer = &stderr_file_writer.interface;
//     var stderr_file_writer = std.Io.Writer.Discarding.init(&.{});
//     const stderr_writer = &stderr_file_writer.writer;
//
//     const reporter = Reporter.init(stderr_writer);
//
//     const len = smith.valueRangeAtMost(u32, 0, 150);
//     const code = try gpa.alloc(u8, len);
//     defer gpa.free(code);
//     _ = smith.slice(code);
//
//     var scanner = try Scanner.init(gpa, code);
//     defer scanner.deinit(gpa);
//
//     try stderr_writer.print("{s}", .{code});
//     scanner.scanTokens(gpa, reporter) catch |err| if (err != Scanner.ScanTokensError.CompileError) return err;
//     try scanner.printTokens(stderr_writer);
//
//     var parser = try Parser.init(gpa, code, scanner.tokens.items);
//     defer parser.deinit(gpa);
//
//     const exprId = parser.parse(gpa, reporter) catch |err| switch (err) {
//         Scanner.ScanTokensError.CompileError => return,
//         else => return err,
//     };
//
//     var prettyPrinterWriterBuffer: [1024]u8 = undefined;
//     var prettyPrinterWriter = std.Io.Writer.fixed(&prettyPrinterWriterBuffer);
//
//     const prettyPrinter = PrettyPrinter.init(parser.expressions.items);
//     try prettyPrinter.print(&prettyPrinterWriter, exprId);
//     const prettyCode: []const u8 = prettyPrinterWriterBuffer[0..prettyPrinterWriter.end];
//
//     var prettyScanner = try Scanner.init(gpa, prettyCode);
//     defer prettyScanner.deinit(gpa);
//     try prettyScanner.scanTokens(gpa, reporter);
//     // try std.testing.expectEqualSlices(Scanner.Token, scanner.tokens.items, newScanner.tokens.items);
//
//     var prettyParser = try Parser.init(gpa, prettyCode, prettyScanner.tokens.items);
//     defer prettyParser.deinit(gpa);
//     const prettyExprId = try prettyParser.parse(gpa, reporter);
//
//     // try std.testing.expectEqualSlices(Expression, parser.expressions.items, prettyParser.expressions.items);
//
//     var prettyPrettyPrinterWriterBuffer: [1024]u8 = undefined;
//     var prettyPrettyPrinterWriter = std.Io.Writer.fixed(&prettyPrettyPrinterWriterBuffer);
//
//     const prettyPrettyPrinter = PrettyPrinter.init(prettyParser.expressions.items);
//     try prettyPrettyPrinter.print(&prettyPrettyPrinterWriter, prettyExprId);
//
//     const prettyPrettyCode = prettyPrettyPrinterWriterBuffer[0..prettyPrettyPrinterWriter.end];
//     try std.testing.expectEqualStrings(prettyCode, prettyPrettyCode);
// }
//
// test "fuzz scanner and parser and pretty printer" {
//     try std.testing.fuzz({}, fuzzTestOneScannerAndParserAndPrettyPrinter, .{});
// }
//
// test "test crashed fuzz" {
//     @disableInstrumentation();
//     if (@import("builtin").fuzz) return;
//     const gpa = std.testing.allocator;
//     const io = std.testing.io;
//     const crash = std.Io.Dir.cwd().readFileAlloc(io, ".zig-cache/f/crash", gpa, std.Io.Limit.unlimited) catch return;
//     defer gpa.free(crash);
//     var smith = std.testing.Smith{ .in = crash };
//     try fuzzTestOneScannerAndParserAndPrettyPrinter({}, &smith);
// }

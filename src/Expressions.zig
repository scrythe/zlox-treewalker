const Scanner = @import("Scanner.zig");

const ExprionId = u32;

pub const BinaryExpr = struct { left: ExprionId, operator: Scanner.TokenType, right: ExprionId };
pub const GroupingExpr = struct { expression: *Expression };
pub const LiteralExpr = struct { value: LiteralValue };

const LiteralValueEnum = enum { None, String, Number, Bool };
pub const LiteralValue = union(LiteralValueEnum) { None, String: []const u8, Number: u32, Bool: bool };

// fn createExpression(args: anytype) type {
//     return struct {};
// }

const ExpressionEnum = enum {
    BinaryExpr,
    GroupingExpr,
    LiteralExpr,
};

pub const Expression = union(ExpressionEnum) { BinaryExpr: BinaryExpr, GroupingExpr: GroupingExpr, LiteralExpr: LiteralExpr };

const Scanner = @import("Scanner.zig");

pub const ExprionId = u32;

pub const BinaryExpr = struct { left: ExprionId, operator: Scanner.TokenType, right: ExprionId };
pub const UnaryExpr = struct { operator: Scanner.TokenType, right: ExprionId };
pub const GroupingExpr = struct { expression: ExprionId };
pub const LiteralExpr = struct { value: LiteralValue };

pub const LiteralValue = union(enum) { None, String: []const u8, Number: u32, Bool: bool };

// fn createExpression(args: anytype) type {
//     return struct {};
// }

pub const Expression = union(enum) {
    BinaryExpr: BinaryExpr,
    GroupingExpr: GroupingExpr,
    LiteralExpr: LiteralExpr,
    UnaryExpr: UnaryExpr,
    // fn init(Expression: ExpressionEnum, value: {}) void {
    // Expression{}
    // }
};

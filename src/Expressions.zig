const Scanner = @import("Scanner.zig");

const ExprionId = u32;

const BinaryExpr = struct { left: ExprionId, operator: Scanner.TokenType, right: ExprionId };
const GroupingExpr = struct { expression: ExprionId };

const ExpressionEnum = enum {
    BinaryExpr,
    GroupingExpr,
};

pub const Expression = union(ExpressionEnum) { BinaryExpr: BinaryExpr, GroupingExpr: GroupingExpr };

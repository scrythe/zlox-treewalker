const Scanner = @import("Scanner.zig");
const std = @import("std");

pub const ExprId = u32;
pub const LiteralValue = union(enum) { None, String: []const u8, Number: f32, Bool: bool };

pub const BinaryExpr = struct { left: ExprId, operator: Scanner.TokenType, right: ExprId };
pub const UnaryExpr = struct { operator: Scanner.TokenType, right: ExprId };
pub const GroupingExpr = struct { expression: ExprId };
pub const LiteralExpr = struct { value: LiteralValue };

pub const Expression = union(enum) {
    BinaryExpr: BinaryExpr,
    GroupingExpr: GroupingExpr,
    LiteralExpr: LiteralExpr,
    UnaryExpr: UnaryExpr,
};

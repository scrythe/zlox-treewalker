const Expressions = @import("Expressions.zig");
const ExprId = Expressions.ExprId;

pub const StmtId = u32;

pub const ExpressionStmt = struct { exprId: ExprId };
pub const PrintStmt = struct { exprId: ExprId };
pub const VarDeclStmt = struct { varName: []const u8, valueExprId: ExprId };
pub const BlockStmt = struct { start: u32, endExclusive: u32 };

pub const Statement = union(enum) {
    ExpressionStmt: ExpressionStmt,
    PrintStmt: PrintStmt,
    VarDeclStmt: VarDeclStmt,
    BlockStmt: BlockStmt,
};

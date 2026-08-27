const Expressions = @import("Expressions.zig");
const ExprId = Expressions.ExprId;

pub const StmtId = u32;

pub const IfStmt = struct { conditionExprId: ExprId, thenBranchId: StmtId, elseBranchId: ?StmtId };
pub const ExpressionStmt = struct { exprId: ExprId };
pub const PrintStmt = struct { exprId: ExprId };
pub const WhileStmt = struct { conditionExprId: ExprId, bodyStmtId: StmtId };
pub const VarDeclStmt = struct { varName: []const u8, valueExprId: ExprId };
pub const FunDeclStmt = struct { funName: []const u8, parameters_start: u32, parameters_end_exclusive: u32, funBlockStmtId: StmtId };
pub const BlockStmt = struct { start: u32, endExclusive: u32 };

pub const Statement = union(enum) {
    IfStmt: IfStmt,
    ExpressionStmt: ExpressionStmt,
    PrintStmt: PrintStmt,
    WhileStmt: WhileStmt,
    VarDeclStmt: VarDeclStmt,
    FunDeclStmt: FunDeclStmt,
    BlockStmt: BlockStmt,
};

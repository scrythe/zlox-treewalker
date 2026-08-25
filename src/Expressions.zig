const Scanner = @import("Scanner.zig");
const std = @import("std");
const Interpreter = @import("Interpreter.zig");
const Allocator = std.mem.Allocator;
const Reporter = @import("Reporter.zig");

pub const ExprId = u32;
pub const LiteralValue = union(enum) { None, String: []const u8, Number: f32, Bool: bool, Function: Function };
pub const Function = struct {
    arity: u32,
    pub fn call(self: *Function, arguments: []const LiteralValue) LiteralValue {
        _ = self; // autofix
        for (arguments) |arg| {
            // TODO: temp for testing arguments
            switch (arg) {
                .None => std.debug.print("None\n", .{}),
                .Bool => |boolVal| std.debug.print("{}\n", .{boolVal}),
                .Number => |number| std.debug.print("{d}\n", .{number}),
                .String => |string| std.debug.print("\"{s}\"\n", .{string}),
                // TODO:
                .Function => unreachable,
            }
        }
        return LiteralValue{ .Number = 5 };
    }
};

pub const BinaryExpr = struct {
    left: ExprId,
    operator: Scanner.TokenType,
    right: ExprId,
    line: u32,
    pub fn init(left: ExprId, operator: Scanner.TokenType, right: ExprId, line: u32) BinaryExpr {
        return BinaryExpr{ .left = left, .operator = operator, .right = right, .line = line };
    }
};
pub const UnaryExpr = struct {
    operator: Scanner.TokenType,
    right: ExprId,
    line: u32,
    pub fn init(operator: Scanner.TokenType, right: ExprId, line: u32) UnaryExpr {
        return UnaryExpr{ .operator = operator, .right = right, .line = line };
    }
};
pub const GroupingExpr = struct { exprId: ExprId };
pub const LiteralExpr = struct { value: LiteralValue };
pub const Logical = struct { left: ExprId, operator: Scanner.TokenType, right: ExprId };
pub const VariableExpr = struct { varName: []const u8, line: u32 };
pub const AssignmentExpr = struct { varName: []const u8, valueExprId: ExprId, line: u32 };
pub const CallExpr = struct { calleeExprId: ExprId, argListStart: ExprId, argListExclusiveEnd: ExprId, line: u32 };

pub const Expression = union(enum) {
    BinaryExpr: BinaryExpr,
    GroupingExpr: GroupingExpr,
    LiteralExpr: LiteralExpr,
    Logical: Logical,
    UnaryExpr: UnaryExpr,
    VariableExpr: VariableExpr,
    AssignmentExpr: AssignmentExpr,
    CallExpr: CallExpr,
};

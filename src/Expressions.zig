const Scanner = @import("Scanner.zig");
const std = @import("std");

pub const ExprId = u32;
pub const LiteralValue = union(enum) { None, String: []const u8, Number: f32, Bool: bool };

// const BinaryExprOperators = CreateSubSetTokenType(enum {
//     BangEqual,
//     EqualEqual,
//     Less,
//     LessEqual,
//     Greater,
//     GreaterEqual,
//     Plus,
//     Minus,
//     Star,
//     Slash,
// });
//
// fn CreateSubSetTokenType(comptime Enum: type) type {
//     @compileLog(@typeInfo(Enum));
//     const tokenEnumType = @typeInfo(Scanner.TokenType).@"enum";
//     const binaryEnumType = @typeInfo(Enum).@"enum";
//     const binaryEnumFields = binaryEnumType.fields;
//
//     var fieldNames: [binaryEnumFields.len][]const u8 = undefined;
//     var fieldValues: [binaryEnumFields.len]tokenEnumType.tag_type = undefined;
//
//     const KvItem = struct { []const u8, tokenEnumType.tag_type };
//     var kvList: [tokenEnumType.fields.len]KvItem = undefined;
//     for (tokenEnumType.fields, 0..) |field, i| {
//         kvList[i] = .{ field.name, field.value };
//     }
//
//     const map = std.static_string_map.StaticStringMap(tokenEnumType.tag_type).initComptime(kvList);
//
//     for (binaryEnumFields, 0..) |field, i| {
//         fieldNames[i] = field.name;
//         fieldValues[i] = map.get(field.name).?;
//     }
//     const newEnum = @Enum(tokenEnumType.tag_type, .exhaustive, &fieldNames, &fieldValues);
//     return struct { tokenType: newEnum, line: u32 };
// }

pub const BinaryExpr = struct {
    left: ExprId,
    operator: Scanner.TokenType,
    right: ExprId,
    line: u32,
    pub fn init(left: ExprId, operator: Scanner.TokenType, right: ExprId, line: u32) BinaryExpr {
        return BinaryExpr{ .left = left, .operator = operator, .right = right, .line = line };
    }
};
pub const UnaryExpr = struct { operator: Scanner.TokenType, right: ExprId };
pub const GroupingExpr = struct { expression: ExprId };
pub const LiteralExpr = struct { value: LiteralValue };

pub const Expression = union(enum) {
    BinaryExpr: BinaryExpr,
    GroupingExpr: GroupingExpr,
    LiteralExpr: LiteralExpr,
    UnaryExpr: UnaryExpr,
};

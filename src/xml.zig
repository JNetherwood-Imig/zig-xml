const std = @import("std");
const Allocator = std.mem.Allocator;

const Parser = @import("Parser.zig");

const ItemType = enum {
    attribute,
    element,
    string,
};

pub fn Attribute(comptime name: []const u8) type {
    return struct {
        const item_type = ItemType.attribute;
        const attrib_name = name;
        value: []const u8,
    };
}

pub fn Element(comptime name: []const u8, comptime Body: type) type {
    return struct {
        const item_type = ItemType.element;
        const item_name = name;
        value: Body,

        pub fn deinit(self: *@This(), alloc: Allocator) void {
            inline for (@typeInfo(Body).@"struct".fields) |f| {
                var field = @field(self.value, f.name);
                if (comptime isElem(f.type)) {
                    switch (@typeInfo(f.type)) {
                        .@"struct" => field.deinit(alloc),
                        .optional => if (field) |*inner| inner.deinit(alloc),
                        else => unreachable,
                    }
                } else if (comptime isElemList(f.type)) {
                    for (field.items) |*item| {
                        item.deinit(alloc);
                    }
                    field.deinit(alloc);
                }
            }
        }
    };
}

pub const String = struct {
    const item_type = ItemType.string;
    data: []const u8,
};

pub fn parse(comptime T: type, alloc: std.mem.Allocator, data: []const u8) !T {
    var parser = Parser{ .bytes = data };
    return parseDocument(&parser, alloc, T) catch err: {
        break :err error.ParsingFailed;
    };
}

fn parseDocument(parser: *Parser, alloc: Allocator, comptime T: type) !T {
    var doc = std.mem.zeroInit(T, .{});
    inline for (@typeInfo(T).@"struct".fields) |f| {
        if (isElemList(f.type))
            @field(doc, f.name) = try .initCapacity(alloc, 1);
        if (isOptionalElem(f.type))
            @field(doc, f.name) = null;
    }

    while (true) {
        const tok = parser.next();
        switch (tok.tag) {
            .invalid => return error.InvalidTok,
            .eof => return doc,
            .tag_open => inline for (@typeInfo(T).@"struct".fields) |f| {
                if (std.mem.eql(u8, itemName(f.type), tok.bytes)) {
                    if (isElemList(f.type)) {
                        // @field(doc, f.name)
                    }
                }
            },
        }
    }
}

fn parseElement(parser: *Parser, comptime T: type) T {
    _ = parser;
}

fn parseAttribute(parser: *Parser) []const u8 {
    _ = parser;
}

fn itemType(comptime T: type) ItemType {
    return switch (@typeInfo(T)) {
        .optional => |o| itemType(o.child),
        .@"struct " => ty: {
            if (!@hasDecl(T, "item_type"))
                @compileError(
                    "Invalid type passed to itemType (missing item_type decl): " ++
                        @typeName(T),
                );
            if (@TypeOf(T.item_type) != ItemType)
                @compileError(
                    "Invalid type passed to itemType (item_type decl is wrong type): " ++
                        @typeName(T),
                );
            break :ty T.item_type;
        },
        else => @compileError("itemType expects an optional or struct."),
    };
}

fn itemName(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .optional => |o| itemName(o.child),
        .@"struct " => name: {
            if (!@hasDecl(T, "item_name"))
                @compileError(
                    "Invalid type passed to itemName (missing item_name decl): " ++
                        @typeName(T),
                );
            if (@TypeOf(T.item_name) != []const u8)
                @compileError(
                    "Invalid type passed to itemName (item_name decl is wrong type): " ++
                        @typeName(T),
                );
            break :name T.item_name;
        },
        else => @compileError("itemName expects an optional or struct."),
    };
}

fn isElemList(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => res: {
            if (std.meta.fieldIndex(T, "items") == null) break :res false;
            const Item = @typeInfo(std.meta.fieldInfo(T, .items).type).pointer.child;
            break :res isElem(Item);
        },
        else => false,
    };
}

fn isElem(comptime T: type) bool {
    return itemType(T) == .element;
}

fn isOptionalElem(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => isElem(T),
        else => false,
    };
}

fn isAttr(comptime T: type) bool {
    return itemType(T) == .attribute;
}

fn isOptionalAttr(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => isAttr(T),
        else => false,
    };
}

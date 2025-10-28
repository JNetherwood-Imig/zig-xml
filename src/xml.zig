//! WE CANT DO RECURSIVE DOCUMENT MEMORY INITIALIZATIONS BECAUSE OPTIONAL ITEMS ARE LAZY-INITIALIZED.
//! THIS MEANS THAT EVERYTHING WILL HAVE TO BE LAZY-INITIALIZED IN THE PARSER FUNCTION, AND THEN DENIITIALIZED ON AN AS-NEEDED BASIS.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Parser = @import("Parser.zig");

const ItemType = enum {
    attribute,
    element,
    string,
};

pub fn Document(comptime Body: type) type {
    return struct {
        value: Body,

        pub fn init(allocator: Allocator) @This() {
            var body: Body = undefined;
            inline for (@typeInfo(Body).@"struct".fields) |field_info| switch (field_info.type.item_type) {
                .element => @field(body, field_info.name) = .init(allocator),
                .attribute, .string => {},
            };
        }

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            inline for (@typeInfo(Body).@"struct".fields) |field_info| switch (field_info.type.item_type) {
                .element => @field(self.value, field_info.name).deinit(allocator),
                .attribute, .string => {},
            };
        }
    };
}

pub fn Element(comptime name: []const u8, comptime Body: type) type {
    return RawElement(name, .none, Body);
}

pub fn OptionalElement(comptime name: []const u8, comptime Body: type) type {
    return RawElement(name, .optional, Body);
}

pub fn ElementList(comptime name: []const u8, comptime Body: type) type {
    return RawElement(name, .list, Body);
}

fn RawElement(comptime _name: []const u8, comptime _opts: enum { none, optional, list }, comptime Body: type) type {
    return struct {
        const item_type = ItemType.element;
        const name = _name;
        const opts = _opts;
        value: switch (_opts) {
            .none => Body,
            .optional => ?Body,
            .list => ArrayList(Body),
        },

        pub fn init(allocator: Allocator) @This() {
            switch (_opts) {
                .none => initBody(allocator),
                .optional => {},
            }
        }

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            switch (_opts) {
                .none => deinitBody(self.value, allocator),
                .optional => if (self.value) |body| deinitBody(body, allocator),
                .list => {
                    for (self.value.items) |*item| deinitBody(item, allocator);
                    self.value.deinit(allocator);
                },
            }
        }

        fn initBody(allocator: Allocator) Body {
            var body: Body = undefined;
            inline for (@typeInfo(Body).@"struct".fields) |field_info| switch (field_info.type.item_type) {
                .element => @field(body, field_info.name) = .init(allocator),
                .attribute, .string => {},
            };
        }

        fn deinitBody(body: Body, allocator: Allocator) void {
            inline for (@typeInfo(Body).@"struct".fields) |field_info| switch (field_info.type.item_type) {
                .element => @field(body, field_info.name).deinit(allocator),
                .attribute, .string => {},
            };
        }
    };
}

pub fn Attribute(comptime name: []const u8) type {
    return struct {
        const item_type = ItemType.attribute;
        const attrib_name = name;
        value: []const u8,
    };
}

pub fn OptionalAttribute(comptime name: []const u8) type {}

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

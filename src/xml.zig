pub fn Document(comptime Body: type) type {
    return struct {
        value: Body,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            inline for (@typeInfo(Body).@"struct".fields) |field_info| {
                if (field_info.type.item_type == .element)
                    @field(self.value, field_info.name).deinit(allocator);
            }
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

pub fn Attribute(comptime name: []const u8) type {
    return RawAttribute(name, .none);
}

pub fn OptionalAttribute(comptime name: []const u8) type {
    return RawAttribute(name, .optional);
}

pub const String = struct {
    const item_type = ItemType.string;
    data: []const u8,
};

pub fn parse(comptime Doc: type, allocator: Allocator, data: []const u8) !Doc {
    var parser = Parser{ .bytes = data };
    return parseDocument(&parser, Doc, allocator) catch err: {
        break :err error.ParsingFailed;
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Parser = @import("Parser.zig");

const ItemType = enum {
    attribute,
    element,
    string,
};

fn RawElement(
    comptime _name: []const u8,
    comptime _opts: enum { none, optional, list },
    comptime _Body: type,
) type {
    return struct {
        const item_type = ItemType.element;
        const name = _name;
        const opts = _opts;
        const Body = _Body;
        value: switch (opts) {
            .none => Body,
            .optional => ?Body,
            .list => ArrayList(Body),
        } = switch (opts) {
            .none => std.mem.zeroInit(Body, .{}),
            .optional => null,
            .list => .empty,
        },

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            switch (opts) {
                .none => deinitBody(&self.value, allocator),
                .optional => {
                    if (self.value) |*body| deinitBody(body, allocator);
                },
                .list => {
                    for (self.value.items) |*item| deinitBody(item, allocator);
                    self.value.deinit(allocator);
                },
            }
        }

        fn deinitBody(body: *Body, allocator: Allocator) void {
            inline for (@typeInfo(Body).@"struct".fields) |field_info| {
                if (field_info.type.item_type == .element)
                    @field(body, field_info.name).deinit(allocator);
            }
        }
    };
}

fn RawAttribute(
    comptime _name: []const u8,
    _opts: enum { none, optional },
) type {
    return struct {
        const item_type = ItemType.attribute;
        const name = _name;
        const opts = _opts;
        value: switch (opts) {
            .none => []const u8,
            .optional => ?[]const u8,
        } = switch (opts) {
            .none => &.{},
            .optional => null,
        },
    };
}

fn parseDocument(
    parser: *Parser,
    comptime Doc: type,
    allocator: Allocator,
) !Doc {
    var doc = std.mem.zeroInit(Doc, .{});
    const Body = @TypeOf(doc.value);
    inline for (@typeInfo(Body).@"struct".fields) |f|
        if (f.type.item_type == .element and f.type.opts == .list) {
            @field(doc.value, f.name).value = try .initCapacity(allocator, 1);
        };
    errdefer doc.deinit(allocator);
    outer: while (true) {
        const tok = parser.next();
        switch (tok.tag) {
            .attr_key => inline for (@typeInfo(Body).@"struct".fields) |f|
                if (f.type.item_type == .attribute and
                    std.mem.eql(u8, f.type.name, tok.bytes))
                {
                    @field(doc.value, f.name).value = parseAttribute(parser);
                    continue :outer;
                },
            .tag_open => inline for (@typeInfo(Body).@"struct".fields) |f| {
                if (f.type.item_type == .element and
                    std.mem.eql(u8, f.type.name, tok.bytes))
                {
                    switch (f.type.opts) {
                        .list => try @field(doc.value, f.name).value.append(
                            allocator,
                            try parseElement(parser, f.type, allocator),
                        ),
                        else => {
                            @field(doc.value, f.name).value = try parseElement(
                                parser,
                                f.type,
                                allocator,
                            );
                        },
                    }
                }
            },
            .tag_close, .tag_close_empty => return doc,
            .doctype, .attr_value => {},
            else => std.debug.panic(
                "Unexpected token while parsing doc: {s} ({s})",
                .{ tok.bytes, @tagName(tok.tag) },
            ),
        }
    }
}

fn parseElement(
    parser: *Parser,
    comptime Elem: type,
    allocator: Allocator,
) !Elem.Body {
    var body = std.mem.zeroInit(Elem.Body, .{});
    inline for (@typeInfo(Elem.Body).@"struct".fields) |f|
        if (f.type.item_type == .element and f.type.opts == .list) {
            @field(body, f.name).value = try .initCapacity(allocator, 1);
        };
    outer: while (true) {
        const tok = parser.next();
        switch (tok.tag) {
            .content => inline for (@typeInfo(Elem.Body).@"struct".fields) |f|
                if (f.type.item_type == .string) {
                    @field(body, f.name).data = tok.bytes;
                    continue :outer;
                } orelse std.debug.panic(
                    "No fields of type xml.String were found in {s}",
                    .{@typeName(Elem.Body)},
                ),
            .attr_key => inline for (@typeInfo(Elem.Body).@"struct".fields) |f|
                if (f.type.item_type == .attribute and std.mem.eql(u8, f.type.name, tok.bytes)) {
                    @field(body, f.name).value = parseAttribute(parser);
                    continue :outer;
                } orelse std.debug.panic(
                    "Attribute \"{s}\" not found in {s}",
                    .{ tok.tag, @typeName(Elem.Body) },
                ),
            .tag_open => inline for (@typeInfo(Elem.Body).@"struct".fields) |f|
                if (f.type.item_type == .element and std.mem.eql(u8, f.type.name, tok.bytes)) {
                    switch (f.type.opts) {
                        .list => try @field(body, f.name).value.append(
                            allocator,
                            try parseElement(parser, f.type, allocator),
                        ),
                        else => @field(body, f.name).value = try parseElement(
                            parser,
                            f.type,
                            allocator,
                        ),
                    }
                    continue :outer;
                } orelse std.debug.panic(
                    "Element \"{s}\" not found in {s}",
                    .{ tok.tag, @typeName(Elem.Body) },
                ),
            .tag_close, .tag_close_empty => return body,
            .invalid => return error.InvalidTok,
            else => std.debug.panic(
                "Unexpected token while parsing element: {s} ({s})",
                .{ tok.bytes, @tagName(tok.tag) },
            ),
        }
    }
}

fn parseAttribute(parser: *Parser) []const u8 {
    const tok = parser.next();
    switch (tok.tag) {
        .attr_value => return tok.bytes,
        else => std.debug.panic(
            "Unexpected token while parsing attribute: {s} ({s})",
            .{ tok.bytes, @tagName(tok.tag) },
        ),
    }
}
